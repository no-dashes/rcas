# frozen_string_literal: true

require "digest"
require "fileutils"
require "open3"
require "tmpdir"
require "shellwords"
require "base64"
require "json"

module RCAS
  # Turns LaTeX into pictures and shows them inline in iTerm2.
  #
  #   e = (:x + 1) / (:x - 1)
  #   e.show                       # inline image in iTerm2, LaTeX source elsewhere
  #   e.to_png("e.png")            # write a PNG
  #   RCAS::Render.backend = :latex
  #
  # Two backends, tried in this order unless Render.backend picks one:
  #
  # * :katex - node + the katex npm package (https://katex.org) typeset the
  #   formula to HTML, headless Chrome rasterizes it. Needs `npm install`
  #   in the project (see package.json) and Google Chrome / Chromium.
  # * :latex - `latex` + `dvipng` (or `pdflatex` + ImageMagick) from a TeX
  #   distribution.
  #
  # Results are cached on disk keyed by the LaTeX source and options.
  # Text colour follows the terminal background (light text on a dark
  # terminal); override with RCAS_TEX_THEME=dark|light.
  module Render
    class Error < StandardError; end

    OSC = "\e]"
    BEL = "\a"

    class << self
      # :auto, :katex or :latex
      attr_writer :backend
      # Zoom factor for the inline display (1.0 = natural size).
      attr_writer :scale
      # "dark" or "light": the terminal background the picture will sit on.
      attr_writer :theme
      # Directory for cached PNGs.
      attr_writer :cache_dir
      # PNG pixels per displayed point; 2 suits Retina displays.
      attr_writer :device_scale
      # true / false to force inline display on or off (nil = detect).
      attr_writer :inline
      attr_writer :wrap
      def wrap = @wrap || (ENV["RCAS_TEX_WRAP"]&.to_i&.then { |w| w.positive? ? w : nil })

      # Pictures written by this process; removed by cleanup! (at exit).
      def created_files = (@created_files ||= [])

      def cleanup!
        created_files.each { |f| File.delete(f) if File.file?(f) }
        created_files.clear
        Dir.rmdir(cache_dir) if Dir.exist?(cache_dir) && Dir.empty?(cache_dir)
      rescue SystemCallError
        nil
      end

      def backend = @backend || ENV.fetch("RCAS_TEX_BACKEND", "auto").to_sym
      def theme_override = @theme
      def scale = @scale || ENV.fetch("RCAS_TEX_SCALE", "1").to_f
      def device_scale = @device_scale || ENV.fetch("RCAS_TEX_DEVICE_SCALE", "2").to_f
      def cache_dir = @cache_dir || ENV["RCAS_CACHE_DIR"] || File.join("/tmp", "rcas")
      def reset! = @theme = @detected_theme = @selected = nil
    end

    module_function

    # ---- public API ---------------------------------------------------------

    # LaTeX source for any rcas value. +wrap+ is a line width in typeset
    # characters (see LaTeX.wrapped), :auto to fit the terminal, nil for none.
    def latex(obj, wrap: nil)
      return obj if obj.is_a?(String)
      wrap = wrap_width if wrap == :auto
      LaTeX.of(obj, wrap: wrap)
    end

    # Typeset characters that fit one terminal line: a math glyph at the
    # default size is about 1.8 columns wide, and the picture is indented.
    def wrap_width(io = $stdout, scale: Render.scale)
      cols = Render.wrap
      return cols if cols&.positive?
      columns = io.respond_to?(:winsize) && io.respond_to?(:tty?) && io.tty? ? io.winsize[1] : ENV.fetch("COLUMNS", "100").to_i
      columns = 100 unless columns.positive?
      (((columns - 4) * 0.55) / scale).floor.clamp(24, 200)
    rescue StandardError
      60
    end

    # PNG bytes for +obj+ (an rcas value or a LaTeX string). With +path+ the
    # bytes are also written there.
    def png(obj, path = nil, display: true, theme: nil, scale: nil, wrap: :auto)
      source = latex(obj, wrap: wrap)
      theme ||= Render.theme
      scale ||= Render.scale
      key = Digest::SHA256.hexdigest([selected.name, source, display, theme, scale.round(3), device_scale].join("\0"))
      file = File.join(cache_dir, "#{key}.png")
      bytes = File.binread(file) if File.file?(file)
      unless bytes
        bytes = selected.render(source, display: display, theme: theme, scale: scale)
        FileUtils.mkdir_p(cache_dir)
        File.binwrite(file, bytes)
        Render.created_files << file
      end
      File.binwrite(path, bytes) if path
      bytes
    end

    # Show +obj+ typeset. In iTerm2 this prints an inline image; anywhere
    # else (or when no backend is installed) the LaTeX source is printed.
    # Returns nil so irb does not echo anything noisy.
    def show(obj, io: $stdout, display: true, wrap: :auto, **options)
      wrap = wrap_width(io) if wrap == :auto
      source = latex(obj, wrap: wrap)
      if inline?(io) && available?
        begin
          io.print(inline_image(png(source, display: display, **options)))
          io.puts
        rescue Error => e
          io.puts "  #{source}"
          io.puts "  (#{e.message.lines.first&.strip})"
        end
      else
        io.puts source
      end
      nil
    end

    # KaTeX HTML fragment (needs node + katex), for embedding in web pages.
    def html(obj, display: true)
      KaTeX.html(latex(obj), display: display)
    end

    # The iTerm2 inline-image escape sequence for PNG bytes, sized so that
    # the picture appears at its natural size on a Retina display.
    def inline_image(bytes, name: "rcas.png")
      w, h = png_dimensions(bytes)
      args = ["inline=1", "size=#{bytes.bytesize}", "name=#{Base64.strict_encode64(name)}", "preserveAspectRatio=1"]
      if w && h
        args << "width=#{(w / device_scale).ceil}px"
        args << "height=#{(h / device_scale).ceil}px"
      end
      body = "1337;File=#{args.join(';')}:#{Base64.strict_encode64(bytes)}"
      tmux? ? "\ePtmux;\e#{OSC}#{body}#{BEL}\e\\" : "#{OSC}#{body}#{BEL}"
    end

    # ---- environment --------------------------------------------------------

    def inline?(io = $stdout)
      return Render.instance_variable_get(:@inline) unless Render.instance_variable_get(:@inline).nil?
      return false if ENV["RCAS_TEX_INLINE"] == "0"
      io.respond_to?(:tty?) && io.tty? && iterm?
    end

    def iterm?
      ENV["TERM_PROGRAM"] == "iTerm.app" || ENV["LC_TERMINAL"] == "iTerm2" || !ENV["ITERM_SESSION_ID"].to_s.empty?
    end

    def tmux? = !ENV["TMUX"].to_s.empty? || ENV["TERM"].to_s.start_with?("screen", "tmux")

    def available? = !selected(strict: false).nil?

    def backends = [KaTeX, TeX]

    def available_backends = backends.select(&:available?)

    # The backend in use, chosen from Render.backend / RCAS_TEX_BACKEND.
    def selected(strict: true)
      @selected ||=
        case Render.backend
        when :auto then available_backends.first
        else backends.find { |b| b.name == Render.backend } || raise(Error, "unknown backend #{Render.backend}; use :katex or :latex")
        end
      if @selected && !@selected.available?
        raise Error, "#{@selected.name} backend is not available: #{@selected.missing}" if strict
        return nil
      end
      raise Error, "no rendering backend available: #{backends.map { |b| "#{b.name} (#{b.missing})" }.join('; ')}" if strict && @selected.nil?
      @selected
    end

    # "dark" or "light": Render.theme= wins, then detection.
    def theme = Render.theme_override || detected_theme

    # "dark" or "light". Asks iTerm2 for its background colour (OSC 11),
    # falls back to COLORFGBG, then assumes dark.
    def detected_theme
      @detected_theme ||= ENV["RCAS_TEX_THEME"] || query_background_theme || colorfgbg_theme || "dark"
    end

    def colorfgbg_theme
      bg = ENV["COLORFGBG"].to_s.split(";").last
      return nil unless bg&.match?(/\A\d+\z/)
      bg.to_i <= 6 || bg.to_i == 8 ? "dark" : "light"
    end

    # Query the terminal for its background colour; nil if it does not answer.
    def query_background_theme(timeout: 0.25)
      return nil unless $stdin.tty? && $stdout.tty? && iterm?
      require "io/console"
      reply = +""
      $stdin.raw do |tty|
        $stdout.print "#{OSC}11;?#{BEL}"
        $stdout.flush
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        loop do
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          break if remaining <= 0 || !IO.select([tty], nil, nil, remaining)
          reply << tty.read_nonblock(256)
          break if reply.include?(BEL) || reply.include?("\e\\")
        end
      end
      m = reply.match(%r{11;rgb:([0-9a-f]+)/([0-9a-f]+)/([0-9a-f]+)}i) or return nil
      r, g, b = m.captures.map { |c| c[0, 2].to_i(16) }
      (0.299 * r + 0.587 * g + 0.114 * b) < 128 ? "dark" : "light"
    rescue StandardError
      nil
    end

    def text_color(theme) = theme.to_s == "light" ? "#000000" : "#ffffff"

    # ---- helpers ------------------------------------------------------------

    def png_dimensions(bytes)
      return nil unless bytes[0, 8] == "\x89PNG\r\n\x1a\n".b
      bytes[16, 8].unpack("NN")
    end

    def which(*names)
      names.each do |n|
        next if n.to_s.empty?
        return n if n.include?("/") && File.executable?(n)
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |dir|
          f = File.join(dir, n)
          return f if File.executable?(f) && !File.directory?(f)
        end
      end
      nil
    end

    def run(*cmd, chdir: nil, input: nil)
      out, err, status = Open3.capture3(*cmd, chdir: chdir || Dir.pwd, stdin_data: input)
      raise Error, "#{File.basename(cmd.first)} failed: #{(err + out).strip.lines.last(8).join}" unless status.success?
      out
    end

    # Crop transparent margins, leaving +pad+ pixels. ImageMagick when
    # present, otherwise chunky_png, otherwise the picture is left as is.
    def trim(bytes, pad: 6)
      if (magick = which("magick"))
        run(magick, "png:-", "-trim", "+repage", "-bordercolor", "none", "-border", pad.to_s, "png:-", input: bytes).b
      elsif (convert = which("convert"))
        run(convert, "png:-", "-trim", "+repage", "-bordercolor", "none", "-border", pad.to_s, "png:-", input: bytes).b
      else
        chunky_trim(bytes, pad)
      end
    end

    def chunky_trim(bytes, pad)
      require "chunky_png"
      img = ChunkyPNG::Image.from_blob(bytes)
      x0, y0, x1, y1 = img.width, img.height, -1, -1
      img.height.times do |y|
        row = img.row(y)
        row.each_with_index do |px, x|
          next if ChunkyPNG::Color.a(px).zero?
          x0 = x if x < x0
          x1 = x if x > x1
          y0 = y if y < y0
          y1 = y
        end
      end
      return bytes if x1 < 0
      x0 = [x0 - pad, 0].max
      y0 = [y0 - pad, 0].max
      x1 = [x1 + pad, img.width - 1].min
      y1 = [y1 + pad, img.height - 1].min
      img.crop(x0, y0, x1 - x0 + 1, y1 - y0 + 1).to_blob
    rescue LoadError
      bytes
    end

    def project_root = File.expand_path("../..", __dir__)

    # ---- backends -----------------------------------------------------------

    # KaTeX in node produces HTML, headless Chrome takes the picture.
    module KaTeX
      module_function

      def name = :katex

      CHROME_CANDIDATES = [
        ENV["RCAS_CHROME"],
        "google-chrome", "google-chrome-stable", "chromium", "chromium-browser", "chrome", "brave-browser", "microsoft-edge",
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        "/Applications/Chromium.app/Contents/MacOS/Chromium",
        "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
        "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
        "/Applications/Arc.app/Contents/MacOS/Arc"
      ].compact.freeze

      def node = @node ||= Render.which(ENV["RCAS_NODE"], "node")
      def chrome = @chrome ||= Render.which(*CHROME_CANDIDATES)

      # Directory of the katex npm package: RCAS_KATEX_DIR, the project's
      # node_modules, or wherever node resolves it from the project root.
      def katex_dir
        return @katex_dir if defined?(@katex_dir)
        @katex_dir = [ENV["RCAS_KATEX_DIR"], File.join(Render.project_root, "node_modules", "katex")].compact.find { |d| File.file?(File.join(d, "package.json")) }
        if @katex_dir.nil? && node
          out, _err, status = Open3.capture3(node, "-p", "require('path').dirname(require.resolve('katex/package.json'))", chdir: Render.project_root)
          @katex_dir = out.strip if status.success? && File.directory?(out.strip)
        end
        @katex_dir
      end

      def available? = !(node.nil? || katex_dir.nil? || chrome.nil?)

      def missing
        [node ? nil : "node", katex_dir ? nil : "katex npm package (run `npm install`)", chrome ? nil : "Google Chrome / Chromium"].compact.join(", ")
      end

      def html(source, display: true)
        raise Error, "KaTeX needs node and the katex package: #{missing}" if node.nil? || katex_dir.nil?
        script = <<~JS
          const katex = require(process.argv[1]);
          const input = JSON.parse(require('fs').readFileSync(0, 'utf8'));
          process.stdout.write(katex.renderToString(input.tex, {displayMode: input.display, throwOnError: true, output: 'html', strict: 'ignore'}));
        JS
        Render.run(node, "-e", script, katex_dir, input: JSON.generate(tex: source, display: display))
      end

      def page(source, display:, color:, font_size:)
        css = File.join(katex_dir, "dist", "katex.min.css")
        <<~HTML
          <!doctype html><html><head><meta charset="utf-8">
          <link rel="stylesheet" href="file://#{css}">
          <style>
            html, body { margin: 0; background: transparent; }
            body { display: inline-block; padding: 8px 10px; color: #{color}; white-space: nowrap; }
            .katex { font-size: #{font_size}em; }
            .katex-display { margin: 0; }
          </style></head><body>#{html(source, display: display)}</body></html>
        HTML
      end

      def render(source, display:, theme:, scale:)
        raise Error, "KaTeX backend is not available: #{missing}" unless available?
        Dir.mktmpdir("rcas-katex") do |dir|
          file = File.join(dir, "formula.html")
          File.write(file, page(source, display: display, color: Render.text_color(theme), font_size: 1.4 * scale))
          out = File.join(dir, "formula.png")
          Render.run(chrome, "--headless=new", "--disable-gpu", "--no-sandbox", "--hide-scrollbars", "--no-first-run",
                     "--default-background-color=00000000", "--force-device-scale-factor=#{Render.device_scale}",
                     "--window-size=#{(3000 * scale).ceil},#{(1200 * scale).ceil}", "--screenshot=#{out}", "file://#{file}")
          raise Error, "Chrome produced no screenshot" unless File.file?(out)
          Render.trim(File.binread(out))
        end
      end
    end

    # A TeX distribution: latex + dvipng, or pdflatex + ImageMagick.
    module TeX
      module_function

      def name = :latex

      def latex_bin = @latex_bin ||= Render.which("latex")
      def dvipng = @dvipng ||= Render.which("dvipng")
      def pdflatex = @pdflatex ||= Render.which("pdflatex")
      def magick = @magick ||= Render.which("magick", "convert")

      def available? = (latex_bin && dvipng) || (pdflatex && magick) ? true : false

      def missing = "latex+dvipng or pdflatex+ImageMagick"

      def document(source, display:, color:)
        math = display ? "\\[#{source}\\]" : "$#{source}$"
        <<~TEX
          \\documentclass[preview,border=4pt,varwidth=true]{standalone}
          \\usepackage{amsmath,amssymb,xcolor}
          \\pagecolor{white}\\nopagecolor
          \\begin{document}
          \\color[HTML]{#{color.delete('#')}}
          #{math}
          \\end{document}
        TEX
      end

      def render(source, display:, theme:, scale:)
        raise Error, "LaTeX backend is not available: install #{missing}" unless available?
        dpi = (220 * scale * Render.device_scale / 2).round
        Dir.mktmpdir("rcas-tex") do |dir|
          File.write(File.join(dir, "f.tex"), document(source, display: display, color: Render.text_color(theme)))
          if latex_bin && dvipng
            compile(latex_bin, dir)
            Render.run(dvipng, "-q", "-D", dpi.to_s, "-T", "tight", "-bg", "Transparent", "-o", "f.png", "f.dvi", chdir: dir)
          else
            compile(pdflatex, dir)
            Render.run(magick, "-density", dpi.to_s, "-background", "none", "f.pdf", "-trim", "+repage", "f.png", chdir: dir)
          end
          Render.trim(File.binread(File.join(dir, "f.png")))
        end
      end

      def compile(bin, dir)
        _out, _err, status = Open3.capture3(bin, "-interaction=batchmode", "-halt-on-error", "f.tex", chdir: dir)
        return if status.success?
        log = File.exist?(File.join(dir, "f.log")) ? File.read(File.join(dir, "f.log")) : ""
        error = log.lines.find { |l| l.start_with?("!") }&.strip || "compilation failed"
        raise Error, "LaTeX: #{error}"
      end
    end
  end

  module Functions
    # show(expr) typesets any value inline; show(a, b) shows several.
    def show(*objects, **options)
      objects.each { |o| Render.show(o, **options) }
      nil
    end
  end
end

at_exit { RCAS::Render.cleanup! }
