# frozen_string_literal: true

require "stringio"

module RCAS
  module App
    # The session behind the window: one Chat::Workspace, the numbering of
    # RCAS::Results, and every answer turned into a plain Hash the page can
    # render. Nothing here prints; the window is the only output device.
    #
    # A cell is what one input line produces:
    #
    #   { n:, input:, kind:, text:, latex:, svg:, stdout:, hint:, seconds: }
    #
    # +kind+ is "result", "error", "info", "help", "vars" or "clear"; the
    # rest of the keys are filled in as far as the value allows. +latex+ is
    # there when the value can be typeset (the page renders it with KaTeX),
    # +svg+ when the value is a plot.
    class Worksheet
      # The output modes of rcas-chat, in a window: "text" is the rcas text
      # form, "typeset" the typeset form alone, "both" the two of them,
      # "latex" the text plus its LaTeX source. Chat::UI owns the list and
      # the older spelling "tex" of :typeset.
      MODES = Chat::UI::MODES
      DEFAULT_MODE = :typeset

      COMMANDS = {
        "/help [NAME]" => "these commands, or what one function, set or class does",
        "/output [text|typeset|both|latex]" => "how results are shown: text, typeset, both, or text + LaTeX source",
        "/theme [dark|light|auto]" => "colour scheme of the window",
        "/unicode [on|off]" => "print ℤ, π and ∞ instead of ZZ, pi and oo",
        "/numbered [on|off]" => "number the lines of the session (In[3] and Out[3] reach them either way)",
        "/latex EXPR" => "the LaTeX source of a Ruby expression",
        "/vars" => "the session's variables",
        "/assumptions" => "declared variable domains",
        "/forget [x ...]" => "drop variable domains",
        "/save [FILE]" => "save a Markdown transcript of the session",
        "/reset" => "start again: variables, assumptions and numbering",
        "/clear" => "clear the worksheet, keep the variables",
        "/exit" => "close the window"
      }.freeze

      attr_reader :mode, :transcript

      def self.mode_for(name) = Chat::UI.mode_for(name)

      def initialize(mode: nil, theme: nil)
        @lock = Mutex.new
        @mode = self.class.mode_for(mode) || DEFAULT_MODE
        @theme = (theme || "auto").to_s
        reset!
        # Chat::UI owns the rules for "what is the text of a value" and
        # "can this be typeset"; borrow them rather than write them twice.
        @format = Chat::UI.new(out: StringIO.new, mode: :text)
      end

      def reset!
        @workspace = Chat::Workspace.new
        @transcript = []
        Results.clear
        RCAS.forget
      end

      # One line from the window. +theme+ is the colour scheme the window
      # has resolved for itself, which is the only way this side can know
      # what "auto" came to (Render.theme reads a *terminal* background).
      def submit(source, theme: nil)
        source = source.to_s.strip
        return info("") if source.empty?
        @window_theme = theme if %w[dark light].include?(theme.to_s)
        @lock.synchronize do
          cell = source.start_with?("/") ? command(source) : evaluate(source)
          @transcript << cell if cell[:n] # commands are answered, not kept
          cell
        end
      end

      def complete(prefix) = @lock.synchronize { @workspace.complete(prefix.to_s) }

      # The cells so far, so that a window which is reloaded comes back with
      # the session it had (the values themselves never left Ruby).
      def cells = @lock.synchronize { @transcript.dup }

      # Does this line only look finished? The page sends Enter as a
      # submission, so an open block or string has to ask for another line.
      def incomplete?(source)
        source = source.to_s
        return false if source.strip.empty? || source.strip.start_with?("/")
        @workspace.incomplete?(source)
      end

      # What the page needs to draw itself after a reload or a /command.
      def state
        {
          version: RCAS::VERSION,
          mode: @mode.to_s,
          modes: MODES.map(&:to_s),
          theme: @theme,
          unicode: RCAS.unicode?,
          numbered: RCAS.numbered?,
          line: Results.line,
          katex: App.katex_dir ? true : false,
          commands: COMMANDS
        }
      end

      private

      # ---- evaluation ---------------------------------------------------------

      def evaluate(source)
        Results.record_input(source, @workspace.binding) # In[3] gives the line back held
        n = Results.index
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        value, printed = @workspace.eval(source, capture: true)
        seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        Results.record(value) # Out[3] reaches the result of the session's third line
        result(n, source, value, printed, seconds)
      rescue StandardError, ScriptError, SystemStackError => e
        error(n, source, e)
      end

      def result(n, source, value, printed, seconds)
        cell = {
          n: n, input: source, kind: "result", seconds: seconds.round(4),
          text: @format.text_of(value), stdout: presence(printed)
        }
        cell[:latex] = LaTeX.of(value) if @format.typesettable?(value)
        cell[:svg] = value.to_svg(theme: svg_theme) if value.is_a?(Plot)
        cell
      rescue StandardError => e
        # A value whose text or LaTeX form raises must not lose the result.
        { n: n, input: source, kind: "result", text: value.inspect, stdout: presence(printed),
          note: "#{e.class}: #{e.message.lines.first&.strip}" }
      end

      def error(n, source, exception)
        {
          n: n, input: source, kind: "error",
          text: "#{exception.class}: #{exception.message.lines.first&.strip}",
          hint: Chat::Usage.hint(exception)
        }
      end

      # ---- commands -----------------------------------------------------------

      def command(line)
        name, argument = line.split(" ", 2)
        argument = argument.to_s.strip
        case name
        when "/help" then help(argument)
        when "/output" then output(argument)
        when "/theme" then theme(argument)
        when "/unicode" then toggle("/unicode", argument) { |on| RCAS.unicode = on unless on.nil? }
        when "/numbered" then toggle("/numbered", argument) { |on| RCAS.numbered = on unless on.nil? }
        when "/latex" then latex_of(argument)
        when "/vars" then vars
        when "/assumptions" then assumptions
        when "/forget" then forget(argument)
        when "/save" then save(argument)
        when "/reset"
          reset!
          info("a fresh session: no variables, no assumptions, numbering from 1", kind: "clear")
        when "/clear"
          @transcript.clear
          info("", kind: "clear")
        when "/exit" then info("", kind: "exit")
        else info("unknown command #{name}; try /help", kind: "error")
        end
      end

      def help(argument)
        return { kind: "help", commands: COMMANDS } if argument.empty?
        return help_command(argument) if argument.start_with?("/")
        doc = Docs.doc(argument)
        {
          kind: "doc", name: argument, signature: doc.signature, lines: doc.lines, also: doc.also,
          background: doc.background&.map { |label, text| { label: label, text: text } },
          sources: doc.sources, reading: doc.reading, sections: doc.sections
        }
      rescue Docs::NotFound => e
        info(e.message, kind: "error")
      end

      def help_command(name)
        entry = COMMANDS.find { |k, _| k.split(/[\s\[]/).first == name }
        return info("unknown command #{name}; try /help", kind: "error") if entry.nil?
        { kind: "help", commands: { entry[0] => entry[1] } }
      end

      def output(argument)
        return info("output #{@mode}") if argument.empty?
        value = self.class.mode_for(argument)
        return info("usage: /output #{MODES.join('|')}", kind: "error") if value.nil?
        @mode = value
        info("output #{@mode}", state: true)
      end

      def theme(argument)
        return info("theme #{@theme}") if argument.empty?
        return info("usage: /theme dark|light|auto", kind: "error") unless %w[dark light auto].include?(argument)
        @theme = argument
        info("theme #{@theme}", state: true)
      end

      def toggle(name, argument)
        return info("usage: #{name} on|off", kind: "error") unless argument.empty? || %w[on off].include?(argument)
        yield(argument.empty? ? nil : argument == "on")
        info("#{name.delete_prefix('/')} #{argument.empty? ? current_toggle(name) : argument}", state: true)
      end

      def current_toggle(name) = (name == "/unicode" ? RCAS.unicode? : RCAS.numbered?) ? "on" : "off"

      def latex_of(argument)
        return info("usage: /latex EXPR", kind: "error") if argument.empty?
        value, = @workspace.eval(argument)
        { kind: "info", text: LaTeX.of(value) }
      rescue StandardError, ScriptError => e
        info("#{e.class}: #{e.message.lines.first&.strip}", kind: "error")
      end

      def vars
        locals = @workspace.locals
        return info("no variables yet") if locals.empty?
        rows = locals.map do |name, value|
          row = { name: name.to_s, text: @format.text_of(value) }
          row[:latex] = LaTeX.of(value) if @format.typesettable?(value)
          row
        end
        { kind: "vars", title: "variables", rows: rows }
      end

      def assumptions
        declared = RCAS.assumptions
        return info("no assumptions") if declared.empty?
        rows = declared.flat_map { |name, value| Array(value).map { |v| [name, v] } }.map do |name, value|
          text = RCAS.unicode? ? value.to_s.sub(" in ", " ∈ ") : value.to_s
          { name: name.to_s, text: text, latex: (LaTeX.of(value) if @format.typesettable?(value)) }
        end
        { kind: "vars", title: "assumptions", rows: rows }
      end

      def forget(argument)
        RCAS.forget(*argument.split.map(&:to_sym))
        info("forgot #{argument.empty? ? 'all assumptions' : argument}")
      end

      # A Markdown transcript, the same shape the chat's /save writes.
      def save(argument)
        file = argument.empty? ? File.join(Dir.pwd, "rcas-#{Time.now.strftime('%Y%m%d-%H%M%S')}.md") : File.expand_path(argument)
        File.write(file, markdown)
        info("saved #{file}")
      rescue SystemCallError => e
        info("could not save: #{e.message}", kind: "error")
      end

      def markdown
        out = +"# rcas #{RCAS::VERSION} - #{Time.now.strftime('%Y-%m-%d %H:%M')}\n"
        @transcript.each do |cell|
          next unless cell[:input]
          out << "\n```\n#{cell[:input]}\n"
          out << cell[:stdout] if cell[:stdout]
          out << (cell[:kind] == "error" ? cell[:text].to_s : "=> #{cell[:text]}") << "\n```\n"
          out << "\n$$#{cell[:latex]}$$\n" if cell[:latex]
        end
        out
      end

      # ---- helpers ------------------------------------------------------------

      def info(text, kind: "info", state: false)
        cell = { kind: kind, text: text }
        cell[:state] = self.state if state
        cell
      end

      def presence(text) = text.to_s.empty? ? nil : text

      # "auto" leaves the choice to the window, which reports what it
      # resolved; Render.theme is the last resort and reads a terminal.
      def svg_theme = @theme == "auto" ? (@window_theme || Render.theme) : @theme
    end
  end
end
