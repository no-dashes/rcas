# frozen_string_literal: true

require "reline"
require "time"

module RCAS
  module Chat
    # The read-eval-print loop: reads input, decides whether it is a
    # command, a shell line, Ruby or a question, and keeps the session saved.
    class REPL
      HISTORY_FILE = File.join(HOME, "history")
      OLD_HISTORY_FILE = File.join(Dir.home, ".rcas_history")
      PROMPT = "❯ "
      CONTINUE = "  "

      COMMANDS = {
        "/help [NAME]" => "these commands, or what one function, set or class does",
        "/output [text|tex|both|latex]" => "how results are shown: ASCII, typeset picture, both, or text + LaTeX source",
        "/backend [katex|latex]" => "typesetting backend (KaTeX + Chrome, or a TeX installation)",
        "/scale N" => "zoom factor for typeset output (1 = natural size)",
        "/theme [dark|light]" => "colour of typeset output for your terminal background",
        "/plotstyle [text|image]" => "how plots are shown: braille art or a picture",
        "/unicode [on|off]" => "print ℤ, π and ∞ instead of ZZ, pi and oo",
        "/numbered [on|off]" => "number the results ([3] instead of =>); _r[3] reaches them either way",
        "/latex EXPR" => "print the LaTeX source of a Ruby expression",
        "/show EXPR" => "typeset a Ruby expression regardless of the output mode",
        "/png EXPR FILE" => "write the typeset expression to a PNG file",
        "/ask TEXT" => "ask Claude (also: start the line with ? )",
        "/vars" => "list the session's variables",
        "/assumptions" => "list declared variable domains",
        "/forget [x ...]" => "drop variable domains",
        "/model [ID]" => "show or switch the Claude model",
        "/fallbacks [on|off]" => "server-side fallback to #{Assistant::FALLBACK_MODEL} when Claude refuses",
        "/cost" => "token usage of this session",
        "/compact" => "forget the conversation with Claude, keep the variables",
        "/sessions" => "list saved sessions",
        "/resume [NAME|ID|N]" => "pick a saved session from a list, or switch to one by name",
        "/rename NAME" => "name this session (also /title)",
        "/reset" => "start a fresh session (variables and conversation)",
        "/save [FILE]" => "save a Markdown transcript",
        "/settings [save|reset]" => "show the defaults in ~/.rcas/settings.json, save the current ones, or delete the file",
        "/clear" => "clear the screen",
        "/exit" => "leave (also Ctrl-D)",
        "!CMD" => "run a shell command"
      }.freeze

      # Listed and accepted only when Claude is configured.
      ASSISTANT_COMMANDS = %w[/ask /model /fallbacks /cost /compact].freeze

      attr_reader :workspace, :ui, :assistant, :session

      # +assistant_factory+ builds the Assistant for a workspace and UI; tests
      # pass one that talks to a fake API.
      def initialize(input: $stdin, output: $stdout, model: Assistant::DEFAULT_MODEL, mode: nil, assistant_factory: nil, session: nil, persist: true)
        @input = input
        @ui = UI.new(out: output, mode: mode)
        @assistant_factory = assistant_factory || ->(ws, ui, m = model) { Assistant.new(ws, ui, model: m) }
        @persist = persist
        @running = true
        fresh_session(model)
        resume(session) if session
      end

      def fresh_session(model = @assistant&.model)
        @workspace = Workspace.new
        @assistant = @assistant_factory.call(@workspace, @ui, model)
        @assistant.on_tool_call = ->(code, result) { @session.transcript << [:tool, code, result] }
        @session = Session.new
      end

      def transcript = @session.transcript
      attr_reader :assistant

      def run
        @ui.banner(model: @assistant.model, backend: Render.available? ? Render.selected.name : :none,
                   assistant: @assistant.available?, session: (@session.id if @persist))
        @ui.puts
        @ui.history(transcript) unless transcript.empty?
        setup_reline if interactive?
        while @running && (line = read_input)
          handle(line)
        end
        save_history if interactive?
        @ui.puts if interactive?
        Render.cleanup!
      end

      def interactive? = @input.respond_to?(:tty?) && @input.tty?

      # One complete input, continuing over lines while the Ruby is unfinished.
      def read_input
        buffer = +""
        prompt = PROMPT
        loop do
          line = read_line(prompt)
          return nil if line.nil? && buffer.empty?
          return buffer if line.nil?
          buffer << line << "\n"
          text = buffer.strip
          return text if text.empty? || text.start_with?("/", "!", "?") || !@workspace.incomplete?(text)
          prompt = CONTINUE
        end
      rescue Interrupt
        @ui.puts
        @ui.info("(to leave, type /exit or press Ctrl-D)")
        ""
      end

      # Interactive input sits between two rules. The one above stays in the
      # scrollback as the turn separator; the one below is drawn, the cursor
      # moved back up onto the prompt line, and it is erased once Enter is hit.
      def read_line(prompt)
        if interactive?
          rule = @ui.rule
          @ui.puts rule if prompt == PROMPT
          @ui.print "\n#{rule}\e[1A\r"
          @ui.flush
          line = Reline.readline(Style.paint(prompt, :bold), true)
          @ui.print "\e[2K\r"
          @ui.flush
          line
        else
          line = @input.gets
          return nil if line.nil?
          @ui.puts "#{prompt}#{line.chomp}" if ENV["RCAS_ECHO"]
          line.chomp
        end
      end

      def handle(line)
        text = line.strip
        return if text.empty?
        transcript << [:input, text]
        case text
        when %r{\A/} then command(text)
        when /\A!/   then shell(text[1..])
        when /\A\?\s*/ then @assistant.available? ? ask(text.sub(/\A\?\s*/, "")) : route(text)
        else route(text)
        end
      rescue Interrupt
        @ui.puts
        @ui.info("(interrupted)")
      ensure
        persist
      end

      # Ruby when it parses and runs; otherwise a question for Claude, or,
      # without Claude, Ruby's own syntax error.
      def route(text)
        return ask(text) if !@workspace.ruby?(text) && @assistant.available?
        # "what is x squared" parses as what(is(x(squared))); since an unknown
        # name applied to arguments is a symbolic function, route a sentence
        # that calls undefined names to Claude before evaluating it.
        return ask(text) if prose?(text) && @assistant.available? && @workspace.undefined_calls?(text)
        evaluate(text)
      rescue NameError, NoMethodError, TypeError, ArgumentError => e
        if prose?(text) && @assistant.available?
          ask(text, note: "#{e.class}: #{e.message.lines.first&.strip}")
        else
          report(e)
        end
      rescue StandardError, ScriptError, SystemStackError => e
        report(e)
      end

      def evaluate(code)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        value, = @ui.busy("computing") { @workspace.eval(code) }
        @ui.result(value)
        @ui.took(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
        transcript << [:result, @ui.text_of(value), (LaTeX.of(value) if @ui.typesettable?(value))]
        value
      end

      def report(error)
        @ui.error("#{error.class}: #{error.message.lines.first&.strip}")
        @ui.hint(Usage.hint(error))
        transcript << [:error, "#{error.class}: #{error.message.lines.first&.strip}"]
      end

      # Several words, most of them plain lowercase words: a sentence, not code.
      def prose?(text)
        words = text.split
        return false if words.size < 3
        plain = words.count { |w| w.match?(/\A[A-Za-z][a-z']*[?.,!:]?\z/) }
        plain >= [2, words.size / 2].max
      end

      def ask(question, note: nil)
        return unless @assistant.available?
        reply = @assistant.ask(question, note: note)
        transcript << [:assistant, reply] if reply
      rescue Error => e
        @ui.error(e.message)
      end

      def shell(command)
        return @ui.error("usage: !command") if command.strip.empty?
        out = IO.popen(command, err: %i[child out], &:read)
        @ui.print(out)
        @ui.puts unless out.end_with?("\n") || out.empty?
        transcript << [:shell, command, out]
      rescue StandardError => e
        @ui.error(e.message)
      end

      # ---- sessions -----------------------------------------------------------

      def persist
        return unless @persist
        @session.model = @assistant.model
        @session.mode = @ui.mode
        @session.messages = @assistant.messages
        @session.usage = @assistant.usage.to_h
        @session.save
      rescue StandardError => e
        @ui.info("(could not save session: #{e.message})")
      end

      # Load +ref+ (a Session, an id, a prefix or a list index) into this REPL.
      def resume(ref)
        session = ref.is_a?(Session) ? ref : Session.find(ref)
        raise Error, "no saved session #{ref.inspect}; see /sessions" unless session
        fallbacks = @assistant.fallbacks
        RCAS.forget
        fresh_session(session.model || @assistant.model)
        @workspace = session.replay_into(@workspace)
        @assistant = @assistant_factory.call(@workspace, @ui, session.model || @assistant.model)
        @assistant.fallbacks = fallbacks
        @assistant.on_tool_call = ->(code, result) { @session.transcript << [:tool, code, result] }
        @assistant.messages = symbolize(session.messages)
        session.usage.each { |k, v| @assistant.usage[k.to_sym] = v }
        @ui.mode = session.mode if session.mode && UI::MODES.include?(session.mode)
        @session = session
        session
      end

      def symbolize(obj)
        case obj
        when Hash then obj.to_h { |k, v| [k.to_sym, k.to_s == "role" ? v.to_sym : symbolize(v)] }
        when Array then obj.map { |v| symbolize(v) }
        else obj
        end
      end

      # ---- slash commands -----------------------------------------------------

      def command(text)
        name, arg = text.split(/\s+/, 2)
        arg = arg.to_s.strip
        case name
        when "/help" then help(arg)
        when "/settings" then settings_command(arg)
        when "/output", "/tex" then output(arg)
        when "/backend" then backend(arg)
        when "/scale"
          return @ui.error("usage: /scale N") unless arg.match?(/\A\d+(\.\d+)?\z/)
          Render.scale = arg.to_f
          @ui.info("scale #{Render.scale}")
        when "/theme"
          return @ui.error("usage: /theme dark|light") unless %w[dark light].include?(arg)
          Render.theme = arg
          @ui.info("theme #{arg}")
        when "/plotstyle" then plotstyle(arg)
        when "/unicode" then unicode(arg)
        when "/numbered" then numbered(arg)
        when "/latex" then @ui.puts(LaTeX.of(@workspace.eval(arg).first))
        when "/show"
          value, = @workspace.eval(arg)
          value.is_a?(Plot) ? @ui.plot_picture(value, force: true) : @ui.typeset(value, force: true)
        when "/png"
          code, file = arg.split(/\s+(?=\S+\z)/, 2)
          return @ui.error("usage: /png EXPR FILE.png") if file.nil?
          value, = @workspace.eval(code)
          value.is_a?(Plot) ? value.to_png(File.expand_path(file)) : Render.png(value, File.expand_path(file))
          @ui.info("wrote #{file}")
        when "/ask" then @assistant.available? ? ask(arg) : @ui.error("unknown command /ask; try /help")
        when "/vars"
          locals = @workspace.locals
          return @ui.info("no variables yet") if locals.empty?
          width = locals.keys.map(&:size).max
          locals.each { |k, v| @ui.puts "  #{Style.cyan(k.to_s.ljust(width))}  #{@ui.text_of(v).gsub("\n", "\n#{' ' * (width + 4)}")}" }
        when "/assumptions"
          a = RCAS.assumptions
          a.empty? ? @ui.info("no assumptions") : a.each { |k, v| @ui.puts(v.is_a?(Inequality) ? "  #{v}" : "  #{k} ∈ #{v}") }
        when "/forget"
          RCAS.forget(*arg.split.map(&:to_sym))
          @ui.info("forgot #{arg.empty? ? 'all assumptions' : arg}")
        when "/model", "/fallbacks", "/cost", "/compact" then assistant_command(name, arg)
        when "/sessions" then sessions
        when "/resume" then resume_command(arg)
        when "/rename", "/title"
          return @ui.error("usage: /rename NAME") if arg.empty?
          @session.title = arg
          @ui.info("session named #{arg.inspect}; /resume #{arg} or rcas-chat --resume #{arg.inspect} brings it back")
        when "/reset"
          fallbacks = @assistant.fallbacks
          RCAS.forget
          fresh_session
          @assistant.fallbacks = fallbacks
          @ui.info("fresh session #{@session.id}")
        when "/save" then save(arg)
        when "/clear" then @ui.print("\e[2J\e[H")
        when "/exit", "/quit", "/q" then @running = false
        else @ui.error("unknown command #{name}; try /help")
        end
      rescue Error, Render::Error => e
        @ui.error(e.message)
      rescue StandardError, ScriptError => e
        report(e)
      end

      # /help lists the commands; /help factor explains one name.
      def help(arg = "")
        return help_for(arg.strip) unless arg.strip.empty?
        commands = COMMANDS.reject { |k, _| !@assistant.available? && ASSISTANT_COMMANDS.include?(k.split.first) }
        width = commands.keys.map(&:size).max
        commands.each { |k, v| @ui.puts "  #{Style.cyan(k.ljust(width))}  #{v}" }
        @ui.puts
        tail = @assistant.available? ? " or, if it is not Ruby, a question for Claude" : ""
        @ui.info("Anything else is Ruby (x + 1, e.expand, ZZ[x].(x**2 - 1).factor)#{tail}.")
        @ui.info("/help factor, /help ZZ, /help Matrix explain one name.")
      end

      # One command, or one function, set or class (from the source, see Docs).
      def help_for(name)
        if name.start_with?("/")
          entry = COMMANDS.find { |k, _| k.split(/[\s\[]/).first == name }
          return @ui.error("unknown command #{name}; try /help") if entry.nil?
          return @ui.puts("  #{Style.cyan(entry[0])}  #{entry[1]}")
        end
        doc = Docs.doc(name)
        @ui.puts("  #{Style.cyan(doc.signature)}")
        doc.lines.each { |l| @ui.puts("    #{l}") }
        @ui.info("also: #{doc.also}") if doc.also
        doc.background&.each do |label, text| # the label is coloured, the prose is not
          wrapped = RCAS::Documentation.wrap("  #{label}: ", text)
          head = "  #{label}:"
          @ui.puts("  #{Style.cyan("#{label}:")}#{wrapped.first[head.size..]}")
          wrapped.drop(1).each { |line| @ui.puts(line) }
        end
        doc.sources&.each_with_index do |source, i|
          wrapped = RCAS::Documentation.wrap(i.zero? ? "  sources: " : "           ", source)
          @ui.puts(i.zero? ? "  #{Style.cyan('sources:')}#{wrapped.first[10..]}" : wrapped.first)
          wrapped.drop(1).each { |line| @ui.puts(line) }
        end
        doc.reading&.each_with_index do |link, i|
          @ui.puts(i.zero? ? "  #{Style.cyan('read:')} #{link}" : "        #{link}")
        end
        @ui.info("manual: #{doc.sections.join('; ')}") unless doc.sections.empty?
      rescue Docs::NotFound => e
        @ui.error(e.message)
      end

      def assistant_command(name, arg)
        return @ui.error("unknown command #{name}; try /help") unless @assistant.available?
        case name
        when "/model"
          @assistant.model = arg unless arg.empty?
          @ui.info("model: #{@assistant.model}")
        when "/fallbacks"
          @assistant.fallbacks = (arg == "on") unless arg.empty?
          @ui.info("fallbacks: #{@assistant.fallbacks ? "on (#{Assistant::FALLBACK_MODEL} on refusal)" : 'off'}")
        when "/cost" then @ui.puts(@assistant.cost.lines.map { |l| "  #{l}" }.join)
        when "/compact"
          @assistant.reset
          @ui.info("conversation cleared; variables kept")
        end
      end

      def plotstyle(arg)
        return @ui.error("usage: /plotstyle #{Plot::STYLES.join('|')}") unless arg.empty? || Plot::STYLES.include?(arg.to_sym)
        Plot.style = arg unless arg.empty?
        note = Plot.image? && !Plot.pictures?(@ui.io) ? " (no inline pictures here, so plots stay text)" : ""
        @ui.info("plotstyle #{Plot.style}#{note}")
      end

      def unicode(arg)
        return @ui.error("usage: /unicode on|off") unless arg.empty? || %w[on off].include?(arg)
        RCAS.unicode = (arg == "on") unless arg.empty?
        @ui.info("unicode #{RCAS.unicode? ? 'on' : 'off'}")
      end

      def numbered(arg)
        return @ui.error("usage: /numbered on|off") unless arg.empty? || %w[on off].include?(arg)
        RCAS.numbered = (arg == "on") unless arg.empty?
        @ui.info("numbered #{RCAS.numbered? ? 'on' : 'off'} (results are kept in _r either way)")
      end

      def output(arg)
        case arg
        when "" then nil
        when "on" then @ui.mode = :both
        when "off" then @ui.mode = :text
        else @ui.mode = arg
        end
        if @ui.tex? && !Render.inline?(@ui.out)
          @ui.info("output #{@ui.mode}: inline pictures need iTerm2, so results stay text here; try /output latex")
        elsif @ui.tex? && !Render.available?
          @ui.info("output #{@ui.mode}: no typesetting backend found (npm install for KaTeX, or install LaTeX + dvipng)")
        else
          @ui.info("output #{@ui.mode}#{@ui.tex? ? " (#{Render.selected.name}, scale #{Render.scale}, theme #{Render.theme})" : ''}")
        end
      end

      def settings_command(arg)
        case arg
        when "save"
          file = Settings.save(Settings.current(@ui, @assistant))
          @ui.info("saved #{file}")
        when "reset"
          Settings.reset
          @ui.info("removed #{Settings::FILE}; built-in defaults apply from the next start")
        when ""
          stored = Settings.load
          @ui.puts "  #{Style.dim(Settings::FILE)}#{stored.empty? ? Style.dim(' (none)') : ''}"
          Settings.current(@ui, @assistant).each do |k, v|
            mark = stored.key?(k) && stored[k].to_s != v.to_s ? Style.dim(" (file: #{stored[k]})") : ""
            @ui.puts "  #{Style.cyan(k.ljust(10))} #{v}#{mark}"
          end
        else @ui.error("usage: /settings [save|reset]")
        end
      end

      def backend(arg)
        unless arg.empty?
          return @ui.error("usage: /backend katex|latex") unless %w[katex latex].include?(arg)
          Render.backend = arg.to_sym
          Render.reset!
          Render.selected
        end
        available = Render.available_backends.map(&:name)
        @ui.info("backend #{Render.available? ? Render.selected.name : 'none'} (available: #{available.empty? ? 'none' : available.join(', ')})")
      end

      # /resume: a picker over the other sessions, or a direct switch.
      def resume_command(arg)
        persist
        others = Session.list.reject { |s| s.id == @session.id }
        target =
          if arg.empty?
            return @ui.info("no other saved sessions") if others.empty?
            Picker.new(others, input: @input, output: @ui.out).run or return @ui.info("(kept the current session)")
          else
            Session.find(arg, among: others) or return @ui.error("no unique session matches #{arg.inspect}; see /sessions")
          end
        resume(target)
        @ui.info("resumed #{@session.name} (#{@session.id})")
        @ui.history(transcript)
      end

      def sessions
        list = Session.list
        return @ui.info("no saved sessions") if list.empty?
        list.first(20).each_with_index do |s, i|
          marker = s.id == @session.id ? Style.green("*") : " "
          @ui.puts "  #{marker} #{Style.dim((i + 1).to_s.rjust(2))}  #{s.summary}"
        end
        @ui.info("/resume opens a picker; /resume NAME, N or ID switches directly; /rename names this one")
      end

      def save(file)
        file = "rcas-#{Time.now.strftime('%Y%m%d-%H%M%S')}.md" if file.empty?
        File.write(File.expand_path(file), markdown)
        @ui.info("saved #{file}")
      end

      def markdown
        out = ["# rcas session #{@session.id}", ""]
        transcript.each do |kind, a, b|
          case kind
          when :input then out << "```ruby" << a << "```"
          when :result
            out << "=> `#{a.lines.first&.chomp}`#{a.lines.size > 1 ? "\n```\n#{a}\n```" : ''}"
            out << "" << "$$#{b}$$" if b
          when :error then out << "Error: #{a}"
          when :assistant then out << "" << a
          when :tool then out << "```ruby" << "# rcas_eval" << a << "```" << "```" << b.to_s << "```"
          when :shell then out << "```" << "$ #{a}" << b.to_s.chomp << "```"
          end
          out << ""
        end
        out.join("\n")
      end

      # ---- line editing -------------------------------------------------------

      def setup_reline
        Reline.completion_append_character = ""
        Reline.completion_proc = lambda do |word|
          if word.start_with?("/")
            COMMANDS.keys.map { |k| k.split.first }.select { |c| c.start_with?(word) }
          else
            @workspace.complete(word)
          end
        end
        load_history
      end

      def load_history
        if !File.file?(HISTORY_FILE) && File.file?(OLD_HISTORY_FILE)
          FileUtils.mkdir_p(File.dirname(HISTORY_FILE))
          File.rename(OLD_HISTORY_FILE, HISTORY_FILE)
        end
        return unless File.file?(HISTORY_FILE)
        File.readlines(HISTORY_FILE, chomp: true).last(1000).each { |l| Reline::HISTORY << l unless l.empty? }
      rescue StandardError
        nil
      end

      def save_history
        FileUtils.mkdir_p(File.dirname(HISTORY_FILE))
        File.write(HISTORY_FILE, Reline::HISTORY.to_a.last(1000).join("\n") + "\n")
      rescue StandardError
        nil
      end
    end

    # Entry point for bin/rcas-chat.
    def self.start(argv = ARGV, input: $stdin, output: $stdout)
      settings = Settings.apply(Settings.load)
      options = {
        mode: settings["output"]&.to_sym,
        model: ENV["RCAS_MODEL"] || settings["model"] || Assistant::DEFAULT_MODEL,
        session: nil, pick: false,
        fallbacks: (ENV.key?("RCAS_FALLBACKS") ? ENV["RCAS_FALLBACKS"] != "0" : settings.fetch("fallbacks", nil))
      }
      until argv.empty?
        case (arg = argv.shift)
        when "--no-tex", "--text" then options[:mode] = :text
        when "--tex" then options[:mode] = :both
        when /\A--output=(\w+)\z/ then options[:mode] = Regexp.last_match(1).to_sym
        when /\A--backend=(katex|latex)\z/ then Render.backend = Regexp.last_match(1).to_sym
        when "--model" then options[:model] = argv.shift
        when /\A--model=(.+)\z/ then options[:model] = Regexp.last_match(1)
        when "-c", "--continue" then options[:session] = Session.latest || (warn "no saved session to continue"; return 1)
        when "-r", "--resume"
          ref = argv.first && !argv.first.start_with?("-") ? argv.shift : nil
          if ref
            options[:session] = Session.find(ref) || (warn "no saved session #{ref}"; return 1)
          else
            options[:pick] = true
          end
        when "--no-color" then Style.enabled = false
        when "-h", "--help"
          claude = Assistant.configured?
          output.puts <<~USAGE
            usage: rcas-chat [options]
              -c, --continue          continue the most recent session
              -r, --resume [NAME|ID]  resume a session by name or id (pick from a list without an argument)
            #{claude ? "  --model ID              Claude model (default #{Assistant::DEFAULT_MODEL}, or RCAS_MODEL)\n" : ''}  --output=MODE           text | tex | both | latex   (--tex, --no-tex for both / text)
              --backend=katex|latex   typesetting backend (or RCAS_TEX_BACKEND)
              --no-color
            #{claude ? 'Ruby is evaluated; anything else is a question for Claude.' : 'Ruby is evaluated and the results are typeset.'}
          USAGE
          return 0
        else
          warn "unknown option #{arg}; try --help"
          return 1
        end
      end
      if options[:pick]
        options[:session] = pick_session(input, output) or return 0
      end
      repl = REPL.new(input: input, output: output, model: options[:model], mode: options[:mode], session: options[:session])
      repl.assistant.fallbacks = options[:fallbacks] unless options[:fallbacks].nil?
      repl.run
      0
    end

    def self.pick_session(input, output)
      list = Session.list
      if list.empty?
        output.puts "no saved sessions"
        return nil
      end
      Picker.new(list, input: input, output: output).run || (output.puts "no session chosen"; nil)
    end
  end
end
