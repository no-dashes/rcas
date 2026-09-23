# frozen_string_literal: true

module RCAS
  module Chat
    # The tool Claude calls to run Ruby in the session. It subclasses the
    # anthropic gem's classes, so it is loaded after the gem and only with
    # it, by Chat.load_anthropic.
    class EvalInput < Anthropic::BaseModel
      required :code, String, doc: "Ruby code to evaluate in the user's rcas session. Variables persist between calls."
      optional :show, Anthropic::Boolean, doc: "Display the result typeset in the user's terminal. Use it for the final result(s) the user asked for."
    end

    # Runs Ruby in the workspace on Claude's behalf and echoes the call and
    # its result to the terminal, Claude-Code style.
    class EvalTool < Anthropic::BaseTool
      self.tool_name = "rcas_eval"
      description "Evaluate Ruby code in the live rcas session and return the printed output and the result (as text and LaTeX)."
      input_schema EvalInput

      MAX_RESULT = 6000

      attr_accessor :on_call

      def initialize(workspace, ui)
        @workspace = workspace
        @ui = ui
      end

      def call(input)
        code = input.code.to_s
        @ui.tool_call("rcas_eval", code)
        value, output = @ui.busy("computing") { @workspace.eval(code, capture: true) }
        shown = "#{output}=> #{@ui.text_of(value)}"
        @ui.tool_result(shown)
        @ui.typeset(value, force: true) if input.show
        on_call&.call(code, shown)
        @ui.busy_start("thinking")
        reply = shown
        reply += "\nLaTeX: #{LaTeX.of(value)}" if @ui.typesettable?(value)
        reply.size > MAX_RESULT ? "#{reply[0, MAX_RESULT]}\n… (truncated)" : reply
      rescue StandardError, ScriptError => e
        message = "#{e.class}: #{e.message.lines.first&.strip}"
        hint = Usage.hint(e)
        @ui.tool_result(message, error: true)
        @ui.hint(hint)
        message = ([message] + hint).join("\n") if hint
        on_call&.call(code, message)
        @ui.busy_start("thinking")
        raise StandardError, message
      end
    end
  end
end
