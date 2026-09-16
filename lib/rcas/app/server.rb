# frozen_string_literal: true

require "socket"
require "json"
require "uri"
require "securerandom"

module RCAS
  module App
    # A very small HTTP/1.1 server on TCPServer: enough for one local page
    # and its JSON calls and nothing more. No keep-alive, no chunking, no
    # TLS, no gems - the only client is the window this process opened.
    # The message format follows [RFC9112, sec. 2-6].
    #
    #   server = Server.new(root: App.assets)
    #   server.post("/eval") { |req| [200, "application/json", body] }
    #   port = server.start                 # 0 picks a free port
    #   server.run                          # accept loop, one thread each
    #
    # Three things keep the evaluation endpoint to this machine and this
    # window, which matters because /eval runs arbitrary Ruby:
    #
    # * the socket binds to the loopback interface, so nothing off the
    #   machine can reach it at all;
    # * a random token is minted per run, goes into the window's URL and
    #   comes back in the `X-RCAS-Token` header of every API call. A page on
    #   another origin cannot set that header without a CORS preflight,
    #   which this server never answers, and cannot guess the token;
    # * the `Host` header must name the loopback address, which is what
    #   stops a DNS rebinding attack from turning a public name into
    #   127.0.0.1 [RFC9110, sec. 7.2].
    #
    # Static assets are served without the token (a stylesheet is not worth
    # protecting and serving one runs nothing); every route added with
    # #get or #post demands it.
    class Server
      # Sent as-is when a request asks for something that is not there.
      NOT_FOUND = "not found"

      TYPES = {
        ".html" => "text/html; charset=utf-8",
        ".css" => "text/css; charset=utf-8",
        ".js" => "text/javascript; charset=utf-8",
        ".mjs" => "text/javascript; charset=utf-8",
        ".json" => "application/json; charset=utf-8",
        ".svg" => "image/svg+xml",
        ".png" => "image/png",
        ".jpeg" => "image/jpeg",
        ".jpg" => "image/jpeg",
        ".ico" => "image/x-icon",
        ".woff" => "font/woff",
        ".woff2" => "font/woff2",
        ".ttf" => "font/ttf"
      }.freeze

      # One parsed request: the bits the routes actually read.
      Request = Struct.new(:method, :path, :query, :headers, :body, keyword_init: true) do
        def json
          return {} if body.nil? || body.empty?
          value = JSON.parse(body)
          value.is_a?(Hash) ? value : {}
        rescue JSON::ParserError
          {}
        end

        def token = headers["x-rcas-token"] || query["token"]
      end

      attr_reader :host, :port, :token

      def initialize(root: nil, host: "127.0.0.1", port: 0, token: nil)
        @root = root && File.expand_path(root)
        @host = host
        @port = port
        @token = token || SecureRandom.urlsafe_base64(24)
        @mounts = {}
        @routes = {}
        @threads = []
        @lock = Mutex.new
      end

      # Serve the files under +dir+ at +prefix+ (KaTeX lives outside the
      # asset directory, in node_modules).
      def mount(prefix, dir) = @mounts[prefix] = File.expand_path(dir)

      def get(path, &block) = @routes[["GET", path]] = block
      def post(path, &block) = @routes[["POST", path]] = block

      # Bind and start listening; returns the port actually in use.
      def start
        @socket = TCPServer.new(@host, @port)
        @port = @socket.addr[1]
      end

      # The address the window should open.
      def url = "http://#{@host}:#{@port}/?token=#{@token}"

      # Accept until #stop. Each connection is answered on its own thread;
      # the routes themselves serialize where they need to.
      def run
        start unless @socket
        loop do
          client = @socket.accept
          @lock.synchronize { @threads = @threads.select(&:alive?) }
          @lock.synchronize { @threads << Thread.new { serve(client) } }
        rescue IOError, Errno::EBADF, Errno::EINVAL
          break # the socket was closed under us: #stop
        end
      end

      def stop
        socket = @socket
        @socket = nil
        socket&.close
      rescue IOError
        nil
      end

      private

      def serve(client)
        request = read_request(client) or return
        status, type, body = dispatch(request)
        write_response(client, status, type, body)
      rescue Errno::EPIPE, Errno::ECONNRESET, IOError
        nil
      ensure
        begin
          client.close
        rescue StandardError
          nil
        end
      end

      def read_request(client)
        line = client.gets or return nil
        method, target, = line.split(" ")
        return nil if method.nil? || target.nil?
        headers = {}
        while (header = client.gets) && header != "\r\n" && header != "\n"
          name, value = header.split(":", 2)
          headers[name.to_s.strip.downcase] = value.to_s.strip if value
        end
        length = headers["content-length"].to_i
        body = length.positive? ? client.read(length) : nil
        uri = URI.parse(target)
        query = uri.query ? URI.decode_www_form(uri.query).to_h : {}
        Request.new(method: method, path: URI.decode_www_form_component(uri.path), query: query, headers: headers, body: body)
      rescue URI::InvalidURIError, ArgumentError
        nil
      end

      # Route, then mounts, then the asset directory.
      def dispatch(request)
        return [403, "text/plain", "forbidden"] unless local_host?(request)
        if (route = @routes[[request.method, request.path]])
          return [403, "text/plain", "forbidden"] unless authorized?(request)
          return route.call(request)
        end
        return [405, "text/plain", "method not allowed"] unless request.method == "GET"
        static(request.path) || [404, "text/plain", NOT_FOUND]
      rescue StandardError => e
        [500, "application/json", JSON.generate(error: "#{e.class}: #{e.message.lines.first&.strip}")]
      end

      # Only the loopback name this process is listening on. Anything else
      # is a request that reached us through another name (DNS rebinding).
      def local_host?(request)
        host = request.headers["host"].to_s.split(":").first
        host.empty? || %w[127.0.0.1 localhost ::1 [::1]].include?(host)
      end

      # Compared in constant time, so that a wrong token tells an attacker
      # how much of it was right only by being wrong.
      def authorized?(request)
        given = request.token.to_s
        return false unless given.bytesize == @token.bytesize
        given.bytes.zip(@token.bytes).sum { |a, b| a ^ b }.zero?
      end

      def static(path)
        path = "/index.html" if path == "/"
        (mount, dir) = @mounts.find { |prefix, _| path.start_with?("#{prefix}/") }
        file =
          if mount
            resolve(dir, path.delete_prefix("#{mount}/"))
          elsif @root
            resolve(@root, path.delete_prefix("/"))
          end
        return nil unless file && File.file?(file)
        [200, TYPES.fetch(File.extname(file).downcase, "application/octet-stream"), File.binread(file)]
      end

      # +relative+ inside +dir+, or nil when it climbs out (..%2f and the
      # like arrive decoded, so this is the check that matters).
      def resolve(dir, relative)
        return nil if relative.empty?
        file = File.expand_path(File.join(dir, relative))
        file.start_with?("#{dir}#{File::SEPARATOR}") ? file : nil
      end

      def write_response(client, status, type, body)
        body = body.to_s.b
        head = +"HTTP/1.1 #{status} #{reason(status)}\r\n"
        head << "Content-Type: #{type}\r\n"
        head << "Content-Length: #{body.bytesize}\r\n"
        # The page is local and private; nothing here may be cached or embedded.
        head << "Cache-Control: no-store\r\n"
        head << "X-Content-Type-Options: nosniff\r\n"
        head << "Connection: close\r\n\r\n"
        client.write(head.b + body)
      end

      def reason(status)
        { 200 => "OK", 400 => "Bad Request", 403 => "Forbidden", 404 => "Not Found",
          405 => "Method Not Allowed", 500 => "Internal Server Error" }.fetch(status, "OK")
      end
    end
  end
end
