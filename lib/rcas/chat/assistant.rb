# frozen_string_literal: true

module RCAS
  module Chat
    # The conversation with Claude. Streams replies, lets the SDK's tool
    # runner execute rcas_eval calls, and keeps the message history.
    class Assistant
      DEFAULT_MODEL = ENV.fetch("RCAS_MODEL", "claude-opus-5")
      FALLBACK_MODEL = "claude-opus-4-8"
      FALLBACK_BETA = "server-side-fallback-2026-06-01"

      # USD per million input / output tokens, for /cost.
      PRICES = {
        "claude-opus-5" => [5.0, 25.0], "claude-opus-4-8" => [5.0, 25.0], "claude-opus-4-7" => [5.0, 25.0],
        "claude-fable-5-1" => [10.0, 50.0], "claude-fable-5" => [10.0, 50.0],
        "claude-sonnet-5" => [2.0, 10.0], "claude-sonnet-4-6" => [3.0, 15.0], "claude-haiku-4-5" => [1.0, 5.0]
      }.freeze

      SYSTEM = <<~PROMPT
        You are the assistant inside rcas-chat, a terminal front end for rcas, a small computer algebra system written in Ruby. The user types Ruby directly or asks questions in plain language. You answer by computing with the rcas_eval tool, which evaluates Ruby in the user's live session: their variables and assumptions are visible to you and whatever you define persists.

        How to work:
        - Compute with rcas_eval rather than doing algebra by hand, and check claims by evaluating them.
        - The terminal typesets results you display with show: true. Use show: true for the final result(s) the user asked for, and do not retype those expressions in your reply.
        - Keep replies short: the result, then at most a sentence or two of explanation or a hint about what else the user could ask. No headings, no bullet lists unless the user asks for a comparison.
        - When a call fails, read the error, fix the code and retry. If rcas cannot do something, say so plainly and suggest the nearest thing it can do.
        - Write ordinary Ruby: ** is power, 1/2r is the rational one half, a bare lowercase name or :x is an indeterminate (a symbolic unknown). Use assume(x: ZZ) to declare domains when a computation needs them.

        rcas reference:
        - Expressions: Symbols are indeterminates; + - * / ** build trees exactly as written; nothing is rewritten until asked. e.simplify, e.expand, e.factor, e.diff(x [, n]), e.integrate(x), e.subs(x: y + 1) or e.subs(pattern => replacement), e.call(x: 3) (a number when fully bound), e.evalf(x: 1.5), e.variables, e.domain, e.to_poly([ring]), e.to_sexp, e.to_latex. Functions: sin cos tan atan sinh cosh exp log sqrt; log is the natural logarithm. Numbers stay exact (Integer/Rational).
        - Number sets: NN ZZ QQ RR CC (include?, ===, <, <=). Domains of variables: x.in(ZZ), assume(x: ZZ, y: RR), assumptions, forget; (x / 2).domain infers the smallest set.
        - Polynomial rings: ZZ[x], QQ[x, y], RR[t]; R.(expr) converts to an RCAS::Polynomial. f + g, f * g, f**n, f / g (exact), f.divmod(g), f % g (univariate), f.gcd(g), f.lcm(g), f.xgcd(g) => [g, s, t], f.degree([var]), f.coefficients (univariate), f.coeff(*exps), f.leading_coefficient, f.derivative([var]), f.integrate([var]), f.factor => RCAS::Factorization (unit, factors as [poly, multiplicity], expand, to_expr), f.irreducible?, f.squarefree_decomposition, f.roots (rational roots), f.resultant(g [, var]), f.discriminant([var]), f.coprime?(g), f.content, f.primitive_part, f.monic, f.to_expr, f.ring. Factorization is exact over ZZ and QQ only. (x**2 - y**2).factor works straight on expressions. R.fraction_field is Frac(R).
        - Vectors and matrices: V = QQ**3; v = V[1, 2, 3]; v + w, 2 * v, v / 2, v * w (dot), v.cross(w), v.norm. A = QQ**[2, 2]; a = A[[1, 2], [3, 4]]; also matrix([[1, 2], [3, 4]]), matrix(RR, rows), vector(1, 2), vector(QQ, 1, 2). a.det, a.trace, a.rank, a.inverse, a.transpose, a**n, a * b, a * v, a.charpoly(:l), a.solve([5, 6]), a.rref, a.kernel, a.identity?, a.symmetric?, a.adjugate, a.cofactor(i, j), A.identity, A.zero. Symbolic entries need declared variables (assume(t: RR)). Numeric matrices over ZZ/QQ are exact.
        - Display: obj.to_latex gives LaTeX; show(obj) typesets it in the terminal.
      PROMPT

      attr_accessor :model, :fallbacks, :on_tool_call
      attr_accessor :messages
      attr_reader :usage, :ui

      def initialize(workspace, ui, model: DEFAULT_MODEL, client: nil, fallbacks: ENV["RCAS_FALLBACKS"] != "0", runner_factory: nil)
        @workspace = workspace
        @ui = ui
        @model = model
        @client = client
        @fallbacks = fallbacks
        @runner_factory = runner_factory
        @messages = []
        @usage = Hash.new(0)
        # a scripted runner (the tests) needs the tool as much as real credentials do
        Chat.load_anthropic if runner_factory || self.class.credentials?
        return unless defined?(EvalTool)
        @tool = EvalTool.new(workspace, ui)
        @tool.on_call = ->(code, result) { @on_tool_call&.call(code, result) }
      end

      # Loads the gem on first use (Chat.load_anthropic): a session nobody
      # asks Claude in never loads it.
      def self.gem_available? = Chat.load_anthropic

      # Credentials are resolved by the SDK (ANTHROPIC_API_KEY, or a profile
      # from `ant auth login`); we only know for sure once a request is made.
      def available?
        return true if @runner_factory || @client
        self.class.configured?
      end

      # Gem installed and credentials present: only then does the chat mention
      # Claude at all. The credentials are asked first, so that without them
      # the gem is never loaded.
      def self.configured? = credentials? && gem_available?

      def self.credentials?
        !ENV["ANTHROPIC_API_KEY"].to_s.empty? || !ENV["ANTHROPIC_AUTH_TOKEN"].to_s.empty? ||
          File.directory?(File.join(Dir.home, ".config", "anthropic"))
      end

      def client = @client ||= Anthropic::Client.new

      def reset = @messages = []

      def params
        p = {
          model: model,
          max_tokens: 16_000,
          system_: [{ type: "text", text: SYSTEM, cache_control: { type: "ephemeral" } }],
          tools: [@tool],
          messages: @messages,
          max_iterations: 16
        }
        if fallbacks && model.start_with?("claude-opus-5", "claude-fable")
          p[:betas] = [FALLBACK_BETA]
          p[:fallbacks] = [{ model: FALLBACK_MODEL }]
        end
        p
      end

      # Ask Claude; streams the reply and runs any tool calls. Returns the
      # final reply text (also printed), or nil when interrupted.
      def ask(text, note: nil)
        raise Error, "the anthropic gem is not installed: gem install anthropic" unless self.class.gem_available?
        snapshot = @messages.dup
        prompt = text.dup
        prompt << "\n\n(This did not evaluate as Ruby: #{note})" if note
        prompt << context
        @messages << { role: :user, content: prompt }

        last = nil
        runner = @runner_factory ? @runner_factory.call(params) : client.beta.messages.tool_runner(params)
        @ui.assistant_start
        @ui.busy_start("thinking")
        runner.each_streaming do |stream|
          stream.each { |event| handle_event(event) }
          last = stream.accumulated_message
          record_usage(last)
        end
        @ui.assistant_end
        history = runner.params[:messages].to_a
        history += [{ role: :assistant, content: last.content }] if last && history.last&.[](:role) != :assistant
        @messages = history
        note_stop_reason(last) if last
        last ? last.content.select { |b| b.type == :text }.map(&:text).join : ""
      rescue Interrupt
        @ui.assistant_end
        @ui.info("(interrupted)")
        @messages = snapshot
        nil
      rescue StandardError => e
        @ui.assistant_end
        @messages = snapshot
        raise Error, describe(e)
      end

      def handle_event(event)
        @ui.assistant_text(event.text) if event.type == :text
      end

      def note_stop_reason(message)
        case message.stop_reason
        when :refusal
          details = message.respond_to?(:stop_details) && message.stop_details ? " (#{message.stop_details.category})" : ""
          @ui.info("Claude declined to answer this#{details}.")
        when :max_tokens
          @ui.info("(reply cut off at the token limit)")
        end
      end

      def record_usage(message)
        u = message.usage
        return unless u
        @usage[:input] += u.input_tokens.to_i
        @usage[:output] += u.output_tokens.to_i
        @usage[:cache_read] += u.cache_read_input_tokens.to_i if u.respond_to?(:cache_read_input_tokens)
        @usage[:cache_write] += u.cache_creation_input_tokens.to_i if u.respond_to?(:cache_creation_input_tokens)
        @usage[:requests] += 1
      end

      def cost
        input, output = PRICES[model] || PRICES.find { |k, _| model.start_with?(k) }&.last
        lines = ["requests: #{@usage[:requests]}   input tokens: #{@usage[:input]} (cache read #{@usage[:cache_read]}, cache write #{@usage[:cache_write]})   output tokens: #{@usage[:output]}"]
        if input
          usd = (@usage[:input] * input + @usage[:output] * output) / 1_000_000.0
          lines << format("approx. list price for %s: $%.4f (cache reads are billed lower)", model, usd)
        end
        lines.join("\n")
      end

      # What the session currently holds, appended to each question.
      def context
        locals = @workspace.locals.reject { |_, v| v.is_a?(Symbol) }.map { |k, v| "#{k} = #{clip(v.to_s.gsub("\n", ' '))}" }
        symbols = @workspace.locals.select { |k, v| v.is_a?(Symbol) && v == k }.keys
        assumptions = RCAS.assumptions.values.flatten.map(&:to_s)
        parts = []
        parts << "variables: #{symbols.join(', ')}" unless symbols.empty?
        parts << "locals: #{locals.join('; ')}" unless locals.empty?
        parts << "assumptions: #{assumptions.join(', ')}" unless assumptions.empty?
        parts.empty? ? "" : "\n\n[session #{parts.join(' | ')}]"
      end

      def clip(text, max = 120) = text.size > max ? "#{text[0, max]}…" : text

      def describe(error)
        return "#{error.class}: #{error.message}" unless defined?(Anthropic::Errors)
        case error
        when Anthropic::Errors::AuthenticationError
          "no valid Anthropic credentials. Set ANTHROPIC_API_KEY (or run `ant auth login`) and try again."
        when Anthropic::Errors::RateLimitError
          "rate limited by the API; wait a moment and try again."
        when Anthropic::Errors::APIStatusError
          "API error #{error.status} (#{error.type}): #{error.message.lines.first&.strip}"
        when Anthropic::Errors::APIConnectionError
          "could not reach the Anthropic API: #{error.message.lines.first&.strip}"
        else
          "#{error.class}: #{error.message.lines.first&.strip}"
        end
      end
    end
  end
end
