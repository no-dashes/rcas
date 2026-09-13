# frozen_string_literal: true

module RCAS
  module Chat
    # Everything that is printed: results in the chosen output mode, the
    # banner, Claude's streamed text and its tool calls.
    class UI
      # How results are displayed:
      #   :text  - plain rcas text only
      #   :tex   - typeset picture only (text when the value has no LaTeX form)
      #   :both  - text, then the picture
      #   :latex - text, then the LaTeX source
      MODES = %i[text tex both latex].freeze

      attr_reader :out, :mode

      def initialize(out: $stdout, mode: nil)
        @out = out
        @mode = mode || default_mode
      end

      def default_mode
        Render.inline?(@out) && Render.available? ? :both : :text
      end

      def mode=(value)
        value = value.to_sym
        raise Error, "output mode must be one of #{MODES.join(', ')}" unless MODES.include?(value)
        @mode = value
      end

      def tex? = %i[tex both].include?(@mode)

      def puts(text = "") = @out.puts(text)
      def print(text) = @out.print(text)
      def flush = @out.flush

      # ---- banner -------------------------------------------------------------

      def banner(model:, backend:, assistant:, session: nil)
        lines = [
          "#{Style.paint('✻', :magenta, :bold)} #{Style.bold("rcas #{RCAS::VERSION}")} #{Style.dim('- symbols are indeterminates; type Ruby or ask a question')}",
          "",
          "  #{Style.dim('model')}    #{assistant ? model : "disabled #{Style.dim("(set ANTHROPIC_API_KEY to enable Claude, #{model})")}"}",
          "  #{Style.dim('output')}   #{@mode}#{tex? ? Style.dim(" via #{backend}") : ''}",
          "  #{Style.dim('help')}     /help   #{Style.dim('quit')} /exit or Ctrl-D"
        ]
        lines << "  #{Style.dim('session')}  #{session}" if session
        lines << ""
        lines << "  #{Style.dim('try')}      (x + 1) * (1 - x)     e.expand     factor x**6 - 1 over the integers"
        box(lines)
      end

      def box(lines)
        width = [lines.map { |l| visible_width(l) }.max + 2, columns - 2].min
        width = 20 if width < 20
        puts Style.dim("╭#{'─' * width}╮")
        lines.each do |l|
          l = truncate(l, width - 2)
          pad = [width - visible_width(l) - 1, 0].max
          puts "#{Style.dim('│')} #{l}#{' ' * pad}#{Style.dim('│')}"
        end
        puts Style.dim("╰#{'─' * width}╯")
      end

      # Cut a (possibly coloured) line to +max+ visible characters.
      def truncate(line, max)
        return line if visible_width(line) <= max
        plain = Style.strip(line)
        "#{plain[0, [max - 1, 0].max]}…"
      end

      def visible_width(text) = Style.strip(text).size

      def columns
        require "io/console"
        width = @out.respond_to?(:winsize) && @out.tty? ? @out.winsize[1] : 0
        width = ENV.fetch("COLUMNS", "0").to_i if width.to_i <= 0
        width.to_i.positive? ? width.to_i : 100
      rescue StandardError
        100
      end

      # ---- results ------------------------------------------------------------

      def result(value)
        show_text = @mode != :tex || !typesettable?(value) || !Render.inline?(@out)
        if show_text
          lines = text_of(value).lines.map(&:chomp)
          puts "#{Style.dim('=>')} #{Style.green(lines.first.to_s)}"
          lines.drop(1).each { |l| puts "   #{Style.green(l)}" }
        end
        case @mode
        when :tex, :both then typeset(value)
        when :latex then puts "   #{Style.dim(LaTeX.of(value))}" if typesettable?(value)
        end
      end

      def text_of(value)
        value.respond_to?(:to_latex) && !value.is_a?(String) ? value.to_s : value.inspect
      end

      # Inline picture when possible; otherwise nothing (the text is there).
      def typeset(value, force: false)
        return unless typesettable?(value)
        return puts("   #{LaTeX.of(value)}") unless Render.inline?(@out) && Render.available?
        return unless force || tex?
        print "   "
        Render.show(value, io: @out)
      rescue Render::Error => e
        info("(typesetting failed: #{e.message.lines.first&.strip})")
      end

      def typesettable?(value)
        case value
        when Expression, Polynomial, Factorization, Domain, Vector, Matrix, VectorSpace, MatrixSpace, Symbol, Numeric then true
        when ->(v) { defined?(Equation) && v.is_a?(Equation) } then true
        when ->(v) { v.respond_to?(:to_latex) && !v.is_a?(String) } then true # inequalities, sets, field elements, ...
        when Array then !value.empty? && value.all? { |v| typesettable?(v) }
        when Hash then !value.empty? && value.values.all? { |v| v.is_a?(Domain) }
        else false
        end
      end

      def error(message) = puts(Style.red("  #{message}"))
      def info(message) = puts(Style.dim("  #{message}"))

      # A usage hint under an error: the first line in cyan, the rest dimmed.
      def hint(lines)
        return if lines.nil? || lines.empty?
        first, *rest = lines
        puts "  #{Style.cyan(first)}"
        rest.each { |l| puts "  #{Style.dim(l)}" }
      end

      # ---- waiting ------------------------------------------------------------

      def tty? = @out.respond_to?(:tty?) && @out.tty?

      # A horizontal rule across the terminal.
      def rule = Style.dim("─" * [columns, 200].min)

      # Animate +label+ on the current line while the block runs; the line is
      # cleared before anything else is printed. Returns the block's value.
      def busy(label)
        busy_start(label)
        yield
      ensure
        busy_stop
      end

      def busy_start(label)
        busy_stop
        return unless tty?
        @spinner = Spinner.new(@out, label).start
      end

      def busy_stop
        @spinner&.stop
        @spinner = nil
      end

      # Seconds a computation took, mentioned only when it was noticeable.
      def took(seconds)
        info("(#{seconds.round(1)}s)") if seconds >= 1.5
      end

      # A dimmed replay of earlier turns when a session is resumed.
      def history(transcript, limit: 12)
        entries = transcript.last(limit)
        info("… #{transcript.size - entries.size} earlier entries") if transcript.size > entries.size
        entries.each do |kind, a, b|
          case kind
          when :input then puts "#{Style.dim('❯')} #{Style.dim(a)}"
          when :result then puts "   #{Style.dim("=> #{a.lines.first&.chomp}#{a.lines.size > 1 ? ' …' : ''}")}"
          when :error then puts "   #{Style.dim(a.lines.first&.chomp)}"
          when :assistant then puts "#{Style.dim('⏺')} #{Style.dim(a.to_s.lines.first(3).join.chomp)}#{a.to_s.lines.size > 3 ? Style.dim(' …') : ''}"
          when :tool then puts "#{Style.dim('⏺')} #{Style.dim("rcas_eval(#{a.lines.first&.chomp})")}"
          when :shell then puts "#{Style.dim('!')} #{Style.dim(a)}"
          end
        end
        puts
      end

      # ---- assistant turn -----------------------------------------------------

      def assistant_start
        @in_text = false
      end

      def assistant_text(delta)
        busy_stop
        unless @in_text
          print "#{Style.paint('⏺', :white, :bold)} "
          @in_text = true
        end
        print delta.gsub("\n", "\n  ")
        flush
      end

      def assistant_end
        busy_stop
        puts if @in_text
        @in_text = false
      end

      def tool_call(name, code)
        busy_stop
        assistant_end
        first, *rest = code.lines.map(&:chomp)
        puts "#{Style.paint('⏺', :green, :bold)} #{Style.bold(name)}#{Style.dim('(')}#{Style.cyan(first)}#{rest.empty? ? Style.dim(')') : ''}"
        rest.each_with_index { |l, i| puts "  #{Style.cyan(l)}#{i == rest.size - 1 ? Style.dim(')') : ''}" }
      end

      def tool_result(text, error: false)
        busy_stop
        lines = text.to_s.lines.map(&:chomp)
        lines = lines.first(12) + ["… (#{lines.size - 12} more lines)"] if lines.size > 13
        lines.each_with_index do |l, i|
          prefix = i.zero? ? "  #{Style.dim('⎿')}  " : "     "
          puts "#{prefix}#{error ? Style.red(l) : Style.dim(l)}"
        end
      end
    end

    # A braille spinner with a label and, after a while, the elapsed time.
    # Runs in its own thread so CPU-bound work in the main thread still
    # lets it turn (Ruby switches threads every 100ms).
    class Spinner
      FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze

      def initialize(out, label, delay: 0.15, interval: 0.08)
        @out = out
        @label = label
        @delay = delay
        @interval = interval
        @shown = false
      end

      def start
        @started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @thread = Thread.new do
          sleep @delay
          i = 0
          loop do
            draw(FRAMES[i % FRAMES.size])
            i += 1
            sleep @interval
          end
        end
        @thread.report_on_exception = false
        self
      end

      def stop
        @thread&.kill
        @thread&.join(0.2)
        @thread = nil
        if @shown
          @out.print "\r\e[2K"
          @out.flush
          @shown = false
        end
        elapsed
      end

      def elapsed = @started ? Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started : 0.0

      private

      def draw(frame)
        secs = elapsed
        time = secs >= 2 ? Style.dim(" #{secs.round}s") : ""
        @out.print "\r\e[2K#{Style.magenta(frame)} #{Style.dim("#{@label}…")}#{time}"
        @out.flush
        @shown = true
      end
    end
  end
end
