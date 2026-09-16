# frozen_string_literal: true

require "rcas"
require "rcas/chat"
require "tmpdir"

module RCAS
  # A desktop window for rcas (bin/rcas-app): a worksheet of numbered
  # In/Out cells, results typeset by KaTeX, plots drawn as SVG.
  #
  # It is a local Ruby program and a borrowed browser engine, and nothing
  # else. App::Server (a page and two JSON calls, on the loopback interface)
  # holds the session; App::Window opens one Chromium-family browser with
  # `--app=URL`, the flag that draws a window with no tabs and no address
  # bar. Closing the window ends the program.
  #
  # Borrowing the engine rather than shipping it is the one design decision
  # worth knowing about: an Electron application of this kind carries its
  # own copy of Chromium and weighs several hundred megabytes, while this
  # is the library, one HTML page and three small Ruby files. The cost is
  # the requirement that such a browser be installed - which rcas already
  # asks for when it typesets with the :katex backend.
  #
  # The window is a third front end, beside bin/rcas (irb) and
  # bin/rcas-chat (terminal); all three share the session of RCAS::Results,
  # so In[3] and Out[3] mean the same thing in each.
  module App
    class Error < StandardError; end

    # Where the window starts looking for a free port.
    DEFAULT_PORT = 0

    USAGE = <<~TEXT
      usage: rcas-app [options]

        --port N           listen on this port (default: any free one)
        --output MODE      text, typeset (default), both or latex
        --theme NAME       dark, light or auto (default)
        --no-window        run the server only and print the address
        --install          add rcas to the Dock / Start menu / applications
        --uninstall        remove it again
        --version          print the version
        --help             this text
    TEXT

    module_function

    def root = File.expand_path("../..", __dir__)
    def assets = File.join(__dir__, "app", "public")
    def logo = [File.join(root, "assets", "rcas-logo.jpeg")].find { |f| File.file?(f) }

    # The KaTeX distribution, when it is installed (npm install): the page
    # typesets with it and falls back to the LaTeX source without it.
    def katex_dir
      return @katex_dir if defined?(@katex_dir)
      package = Render::KaTeX.katex_dir
      @katex_dir = package && File.directory?(File.join(package, "dist")) ? File.join(package, "dist") : nil
    end

    # Build the server for +worksheet+: the page, its assets, and the two
    # calls the page makes.
    def build(worksheet, port: DEFAULT_PORT)
      server = Server.new(root: assets, port: port)
      server.mount("/katex", katex_dir) if katex_dir
      server.post("/api/eval") do |request|
        json(worksheet.submit(request.json["source"], theme: request.json["theme"]))
      end
      server.post("/api/complete") do |request|
        json(candidates: worksheet.complete(request.json["prefix"]))
      end
      server.post("/api/incomplete") do |request|
        json(incomplete: worksheet.incomplete?(request.json["source"]))
      end
      server.post("/api/state") { json(worksheet.state) }
      server.post("/api/cells") { json(cells: worksheet.cells) }
      server.get("/api/logo") do
        logo ? [200, "image/jpeg", File.binread(logo)] : [404, "text/plain", Server::NOT_FOUND]
      end
      server
    end

    def json(value) = [200, "application/json; charset=utf-8", JSON.generate(value)]

    # ---- the program ----------------------------------------------------------

    def start(argv = [])
      options = parse(argv)
      return puts(USAGE) if options[:help]
      return puts("rcas #{RCAS::VERSION}") if options[:version]
      return install if options[:install]
      return uninstall if options[:uninstall]
      run(options)
    rescue Error => e
      warn "rcas-app: #{e.message}"
      1
    end

    def parse(argv)
      options = { port: DEFAULT_PORT, window: true }
      until argv.empty?
        case (flag = argv.shift)
        when "--help", "-h" then options[:help] = true
        when "--version", "-v" then options[:version] = true
        when "--install" then options[:install] = true
        when "--uninstall" then options[:uninstall] = true
        when "--no-window" then options[:window] = false
        when "--port" then options[:port] = argv.shift.to_i
        when "--output" then options[:mode] = argv.shift
        when "--theme" then options[:theme] = argv.shift
        else raise Error, "unknown option #{flag} (try --help)"
        end
      end
      options
    end

    def install
      path = Launcher.install
      puts "rcas: installed #{path}"
      puts "rcas: #{Window.missing}" unless Window.available?
      0
    end

    def uninstall
      path = Launcher.uninstall
      puts path ? "rcas: removed #{path}" : "rcas: nothing installed"
      0
    end

    def run(options)
      # The program prints one line and then waits for the window, so its
      # output has to arrive now and not when the pipe is closed.
      $stdout.sync = true
      settings = Chat::Settings.apply(Chat::Settings.load)
      worksheet = Worksheet.new(mode: options[:mode] || settings["output"], theme: options[:theme] || settings["theme"])
      server = build(worksheet, port: options[:port])
      server.start
      raise Error, Window.missing if options[:window] && !Window.available?
      listener = Thread.new { server.run }
      listener.abort_on_exception = false
      options[:window] ? show(server) : serve(server, listener)
      0
    ensure
      server&.stop
    end

    # Open the window and stay alive while it is open.
    def show(server)
      puts "rcas #{RCAS::VERSION} - #{File.basename(Window.browser)} window on #{server.host}:#{server.port}"
      pid = Window.open(server.url)
      Window.wait(pid)
    rescue Interrupt
      nil
    end

    # --no-window: print the address and wait to be interrupted.
    def serve(server, listener)
      puts "rcas #{RCAS::VERSION} - open #{server.url}"
      listener.join
    rescue Interrupt
      nil
    end
  end
end

require_relative "app/server"
require_relative "app/worksheet"
require_relative "app/window"
require_relative "app/launcher"
