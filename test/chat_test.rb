# frozen_string_literal: true

require_relative "test_helper"
require "rcas/chat"
require "stringio"
require "tmpdir"

# A stand-in for the SDK's tool runner: plays a script of assistant turns,
# runs rcas_eval calls through the real tool, and records messages the way
# the real runner does.
class FakeRunner
  FakeStream = Struct.new(:events, :message) do
    def each(&block) = events.each(&block)
    def accumulated_message = message
  end

  attr_reader :params

  def initialize(params, script)
    @params = params
    @script = script
  end

  def each_streaming
    tool = @params[:tools].first
    @script.each_with_index do |turn, i|
      content = []
      events = []
      if turn[:text]
        content << Anthropic::Models::Beta::BetaTextBlock.new(type: :text, text: turn[:text])
        events << Anthropic::Helpers::Streaming::TextEvent.new(type: :text, text: turn[:text], snapshot: turn[:text])
      end
      if turn[:tool]
        content << Anthropic::Models::Beta::BetaToolUseBlock.new(type: :tool_use, id: "tu#{i}", name: "rcas_eval", input: turn[:tool])
      end
      message = Anthropic::Models::Beta::BetaMessage.new(
        id: "msg#{i}", type: :message, role: :assistant, model: @params[:model], stop_sequence: nil,
        stop_reason: turn[:tool] ? :tool_use : (turn[:stop_reason] || :end_turn),
        usage: { input_tokens: 100, output_tokens: 10, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 },
        content: content
      )
      yield FakeStream.new(events, message)
      break unless turn[:tool]
      input = RCAS::Chat::EvalInput.new(**turn[:tool])
      begin
        result = tool.call(input)
        error = false
      rescue StandardError => e
        result = e.message
        error = true
      end
      @params[:messages] << { role: :assistant, content: content }
      @params[:messages] << { role: :user, content: [{ type: :tool_result, tool_use_id: "tu#{i}", content: result, is_error: error }] }
    end
  end
end

class ChatWorkspaceTest < Minitest::Test
  def setup = @ws = RCAS::Chat::Workspace.new

  def test_bare_identifiers_become_symbols_and_locals
    value, = @ws.eval("e = (x + 1) * (1 - x)")
    assert_equal "(x + 1)*(1 - x)", value.to_s
    assert_equal :x, @ws[:x]
    assert_equal %i[e x], @ws.locals.keys.sort
    assert_equal "1 - x**2", @ws.eval("e.expand").first.to_s
    assert_equal "1 - x**2", @ws.eval("_").first.to_s
  end

  def test_functions_sets_and_output_capture
    assert_equal "cos(y)", @ws.eval("sin(y).diff(y)").first.to_s
    assert_equal RCAS::ZZ[:x], @ws.eval("ZZ[x]").first
    value, out = @ws.eval("puts 'hi'; 42", capture: true)
    assert_equal 42, value
    assert_equal "hi\n", out
  end

  def test_unknown_functions_and_missing_methods
    assert_equal "foo(1)", @ws.eval("foo(1)").first.to_s, "an undefined name applied to an expression is an unknown function"
    assert_raises(NoMethodError) { @ws.eval('foo("a")') }
    assert @ws.undefined_calls?("what is x squared")
    refute @ws.undefined_calls?("sin(x).diff(x)")
  end

  def test_ruby_detection
    assert @ws.ruby?("x + 1")
    assert @ws.ruby?("factor x")
    refute @ws.ruby?("factor x**6 - 1 over the integers")
    refute @ws.ruby?("what is the derivative of sin(x)?")
    assert @ws.incomplete?("def f(a)")
    assert @ws.incomplete?("(x + ")
    assert @ws.incomplete?("[1, 2")
    refute @ws.incomplete?("factor x**6 - 1 over the integers")
    refute @ws.incomplete?("x + 1")
  end

  def test_completion
    @ws.eval("expr = x + 1")
    assert_includes @ws.complete("ex"), "expr"
    assert_includes @ws.complete("ex"), "exp"
    assert_includes @ws.complete("Z"), "ZZ"
  end
end

class ChatReplTest < Minitest::Test
  def setup
    RCAS.forget
    RCAS::Chat::Style.enabled = false
    RCAS::Render.inline = false
  end

  def teardown
    RCAS::Chat::Style.enabled = nil
    RCAS::Render.inline = nil
    RCAS.forget
  end

  def repl(input, script: nil, **options)
    out = StringIO.new
    factory =
      if script
        ->(ws, ui, model) { RCAS::Chat::Assistant.new(ws, ui, model: model, runner_factory: ->(params) { FakeRunner.new(params, script) }) }
      else
        ->(ws, ui, model) { RCAS::Chat::Assistant.new(ws, ui, model: model, client: nil, runner_factory: nil).tap { |a| a.define_singleton_method(:available?) { false } } }
      end
    r = RCAS::Chat::REPL.new(input: StringIO.new(input), output: out, assistant_factory: factory, persist: false, mode: :text, **options)
    r.run
    [r, out.string]
  end

  def test_ruby_results_and_commands
    _, out = repl(<<~IN)
      e = (x + 1) * (1 - x)
      e.expand
      /latex e.diff(x)
      /vars
      foo(1)
      /unknown
      !echo hello
      /output latex
      sqrt(x).diff(x)
    IN
    assert_includes out, "=> (x + 1)*(1 - x)"
    assert_includes out, "=> 1 - x**2"
    assert_includes out, "\n-2 x\n"
    assert_match(/^  e\s+\(x \+ 1\)\*\(1 - x\)$/, out)
    assert_includes out, "=> foo(1)"
    assert_includes out, "unknown command /unknown"
    assert_includes out, "hello"
    assert_includes out, "\\frac{1}{2 \\sqrt{x}}"
  end

  def test_multiline_ruby_and_matrices
    _, out = repl(<<~IN)
      def f(a)
        a + 1
      end
      f(x)
      matrix([[1, 2], [3, 4]]).inverse
    IN
    assert_includes out, "=> x + 1"
    assert_includes out, "=> [ -2    1]\n   [3/2 -1/2]"
  end

  def test_prose_without_claude_is_just_ruby
    _, out = repl("factor x**6 - 1 over the integers\n")
    assert_includes out, "SyntaxError", "the sentence is treated as the Ruby it is"
    refute_includes out, "ANTHROPIC_API_KEY"
    refute_includes out, "Claude"
  end

  def test_questions_go_to_claude_through_the_tool
    script = [
      { text: "Let me factor that.", tool: { code: "ZZ[x].(x**6 - 1).factor", show: true } },
      { text: "Done: four irreducible factors." }
    ]
    r, out = repl("factor x**6 - 1 over the integers\ne.expand\n", script: script)
    assert_includes out, "⏺ Let me factor that."
    assert_includes out, "⏺ rcas_eval(ZZ[x].(x**6 - 1).factor)"
    assert_includes out, "⎿  => (-1 + x)*(1 + x)*(1 + x + x**2)*(1 - x + x**2)"
    assert_includes out, "⏺ Done: four irreducible factors."
    messages = r.assistant.messages
    assert_equal %i[user assistant user assistant], messages.map { |m| m[:role] }
    assert_includes messages.first[:content], "factor x**6 - 1 over the integers"
    assert_equal :tool_result, messages[2][:content].first[:type]
    assert_equal 200, r.assistant.usage[:input]
    assert_includes r.assistant.cost, "requests: 2"
    kinds = r.transcript.map(&:first)
    assert_equal %i[input tool assistant input error], kinds, "the tool call is in the transcript; e is a bare symbol"
  end

  def test_prose_that_parses_as_ruby_is_still_a_question
    script = [{ text: "x squared is a monomial." }]
    _, out = repl("what is x squared\n", script: script)
    assert_includes out, "⏺ x squared is a monomial."
  end

  def test_tool_errors_are_reported_back
    script = [
      { text: "Trying.", tool: { code: "ZZ[x].(1 / x)" } },
      { text: "That is not a polynomial." }
    ]
    r, out = repl("? convert 1/x to a polynomial\n", script: script)
    assert_includes out, "RCAS::DomainError"
    assert r.assistant.messages[2][:content].first[:is_error]
  end

  def test_api_errors_leave_history_clean
    factory = lambda do |ws, ui, model|
      RCAS::Chat::Assistant.new(ws, ui, model: model, runner_factory: ->(_p) { raise Anthropic::Errors::APIConnectionError.new(url: URI("https://api.anthropic.com"), message: "down") })
    end
    out = StringIO.new
    r = RCAS::Chat::REPL.new(input: StringIO.new("? hello\n"), output: out, assistant_factory: factory, persist: false, mode: :text)
    r.run
    assert_includes out.string, "could not reach"
    assert_empty r.assistant.messages
  end

  def test_fallback_params_follow_the_model
    ws = RCAS::Chat::Workspace.new
    a = RCAS::Chat::Assistant.new(ws, RCAS::Chat::UI.new(out: StringIO.new, mode: :text), model: "claude-opus-5", fallbacks: true)
    assert_equal ["server-side-fallback-2026-06-01"], a.params[:betas]
    assert_equal [{ model: "claude-opus-4-8" }], a.params[:fallbacks]
    a.model = "claude-sonnet-5"
    refute a.params.key?(:fallbacks)
    a.model = "claude-opus-5"
    a.fallbacks = false
    refute a.params.key?(:betas)
  end

  def test_context_mentions_session_state
    ws = RCAS::Chat::Workspace.new
    ws.eval("e = x + 1; assume(x: ZZ)")
    a = RCAS::Chat::Assistant.new(ws, RCAS::Chat::UI.new(out: StringIO.new, mode: :text))
    assert_includes a.context, "variables: x"
    assert_includes a.context, "e = x + 1"
    assert_includes a.context, "x in ZZ"
  end
end

# Without the gem and a key the chat must not mention Claude anywhere.
class ChatWithoutClaudeTest < Minitest::Test
  def setup
    RCAS::Chat::Style.enabled = false
    RCAS::Render.inline = false
  end

  def teardown
    RCAS::Chat::Style.enabled = nil
    RCAS::Render.inline = nil
  end

  def run_repl(input, available:)
    out = StringIO.new
    factory = ->(ws, ui, model) { RCAS::Chat::Assistant.new(ws, ui, model: model).tap { |a| a.define_singleton_method(:available?) { available } } }
    RCAS::Chat::REPL.new(input: StringIO.new(input), output: out, assistant_factory: factory, persist: false, mode: :text).run
    out.string
  end

  def test_offline_shows_a_plain_cas
    out = run_repl("/help\n/model\n/settings\nwhat is )\n? hello\n", available: false)
    ["Claude", "ANTHROPIC", "/ask", "ask a question", "question for", "/fallbacks", "/cost", "/compact", "over the integers"].each do |word|
      refute_includes out, word, "offline output mentions #{word.inspect}"
    end
    refute_match(/model\s{2,}\S/, out, "no model line in banner or settings")
    assert_includes out, "unknown command /model"
    assert_includes out, "SyntaxError", "a non-Ruby line is an ordinary syntax error"
    assert_includes out, "e = (x + 1) * (1 - x)", "the banner suggests Ruby instead of a question"
    assert_includes out, "ZZ[x].(x**6 - 1).factor"
    assert_includes run_repl("/ask hello\n", available: false), "unknown command /ask"
  end

  def test_online_shows_the_assistant
    out = run_repl("/help\n", available: true)
    assert_includes out, "/ask TEXT"
    assert_includes out, "question for Claude"
    assert_match(/model\s{2,}claude/, out)
    assert_includes out, "over the integers"
  end
end

class ChatSessionTest < Minitest::Test
  def setup
    RCAS.forget
    RCAS::Chat::Style.enabled = false
    RCAS::Render.inline = false
    @dir = Dir.mktmpdir("rcas-sessions")
    @saved = RCAS::Chat::Session::DIR
    RCAS::Chat::Session.send(:remove_const, :DIR)
    RCAS::Chat::Session.const_set(:DIR, @dir)
  end

  def teardown
    RCAS::Chat::Session.send(:remove_const, :DIR)
    RCAS::Chat::Session.const_set(:DIR, @saved)
    FileUtils.rm_rf(@dir)
    RCAS::Chat::Style.enabled = nil
    RCAS::Render.inline = nil
    RCAS.forget
  end

  def offline = ->(ws, ui, model) { RCAS::Chat::Assistant.new(ws, ui, model: model).tap { |a| a.define_singleton_method(:available?) { false } } }

  def test_sessions_are_saved_and_resumed_by_replay
    out = StringIO.new
    r = RCAS::Chat::REPL.new(input: StringIO.new("e = (x + 1) * (1 - x)\nassume(t: RR)\ndef f(a)\n  a + 1\nend\n/title first\n"), output: out, assistant_factory: offline, mode: :text)
    r.run
    id = r.session.id
    assert File.file?(File.join(@dir, "#{id}.json"))
    saved = RCAS::Chat::Session.load(id)
    assert_equal "first", saved.title
    assert_equal :text, saved.mode
    assert_equal 4, saved.turns
    RCAS.forget

    out = StringIO.new
    r2 = RCAS::Chat::REPL.new(input: StringIO.new("e.expand\nf(2)\n/assumptions\n"), output: out, assistant_factory: offline, session: RCAS::Chat::Session.latest, mode: :text)
    r2.run
    assert_equal id, r2.session.id
    assert_includes out.string, "❯ e = (x + 1) * (1 - x)", "history is shown on resume"
    assert_includes out.string, "=> 1 - x**2"
    assert_includes out.string, "=> 3"
    assert_includes out.string, "t ∈ RR"
    assert_equal 7, RCAS::Chat::Session.load(id).turns
  end

  def test_list_find_and_switch
    r = RCAS::Chat::REPL.new(input: StringIO.new("a = 1\n"), output: StringIO.new, assistant_factory: offline, mode: :text)
    r.run
    first = r.session.id
    sleep 0.01
    out = StringIO.new
    r2 = RCAS::Chat::REPL.new(input: StringIO.new("b = 2\n/sessions\n/resume #{first}\n/vars\n"), output: out, assistant_factory: offline, mode: :text)
    r2.run
    assert_equal 2, RCAS::Chat::Session.list.size
    assert_includes out.string, first
    assert_includes out.string, "resumed a = 1 (#{first})"
    assert_match(/^  a\s+1$/, out.string)
    refute_match(/^  b\s+2$/, out.string, "the other session's variables are gone")
    assert_equal first, RCAS::Chat::Session.find(first[0..-2]).id, "unique prefix"
    assert_equal RCAS::Chat::Session.list.first.id, RCAS::Chat::Session.find("1").id, "list index"
  end

  def test_start_handles_continue_and_help
    out = StringIO.new
    assert_equal 0, RCAS::Chat.start(["--help"], input: StringIO.new, output: out)
    assert_includes out.string, "--resume"
    assert_equal 1, RCAS::Chat.start(["--continue"], input: StringIO.new, output: StringIO.new), "nothing to continue yet"
  end
end

class ChatSpinnerTest < Minitest::Test
  # A StringIO that claims to be a terminal, so the spinner draws.
  class FakeTTY < StringIO
    def tty? = true
  end

  def setup = RCAS::Chat::Style.enabled = false
  def teardown = RCAS::Chat::Style.enabled = nil

  def test_spinner_draws_after_a_delay_and_clears_on_stop
    out = FakeTTY.new
    spinner = RCAS::Chat::Spinner.new(out, "computing", delay: 0.0, interval: 0.01).start
    sleep 0.1
    elapsed = spinner.stop
    assert_match(/\r\e\[2K[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏] computing…/, out.string)
    assert out.string.end_with?("\r\e[2K"), "the line is cleared when the spinner stops"
    assert elapsed > 0.05
  end

  def test_quick_work_never_shows_a_spinner
    out = FakeTTY.new
    RCAS::Chat::Spinner.new(out, "computing", delay: 1.0).start.stop
    assert_equal "", out.string
  end

  def test_ui_busy_is_a_no_op_without_a_terminal
    out = StringIO.new
    ui = RCAS::Chat::UI.new(out: out, mode: :text)
    assert_equal 7, ui.busy("computing") { 7 }
    ui.busy_start("thinking")
    ui.assistant_text("hi")
    assert_equal "⏺ hi", out.string
  end

  def test_ui_busy_with_a_terminal_clears_before_output
    out = FakeTTY.new
    ui = RCAS::Chat::UI.new(out: out, mode: :text)
    ui.busy("computing") { sleep 0.3 }
    ui.info("done")
    assert_match(/computing…/, out.string)
    assert_match(/\r\e\[2K  done\n\z/, out.string)
    ui.busy_start("thinking")
    sleep 0.3
    ui.tool_call("rcas_eval", "1 + 1")
    assert_match(/thinking….*\r\e\[2K⏺ rcas_eval\(1 \+ 1\)/m, out.string)
  end

  def test_took_is_only_mentioned_for_slow_results
    out = StringIO.new
    ui = RCAS::Chat::UI.new(out: out, mode: :text)
    ui.took(0.4)
    assert_equal "", out.string
    ui.took(3.26)
    assert_equal "  (3.3s)\n", out.string
  end
end

class ChatUsageTest < Minitest::Test
  def setup
    @ws = RCAS::Chat::Workspace.new
    RCAS::Chat::Style.enabled = false
    RCAS::Render.inline = false
  end

  def teardown
    RCAS::Chat::Style.enabled = nil
    RCAS::Render.inline = nil
  end

  def error_from(code)
    @ws.eval(code)
    flunk "expected #{code} to raise"
  rescue StandardError => e
    e
  end

  def test_hint_for_a_function_called_wrongly
    hint = RCAS::Chat::Usage.hint(error_from("sum(x)"))
    assert_equal "usage: sum(f, k = nil, from = nil, to = nil, **range)", hint.first
    assert hint.any? { |l| l.include?("sum(k**2, k, 1, n)") }, hint.inspect
  end

  def test_hint_for_a_method_that_raises_itself
    hint = RCAS::Chat::Usage.hint(error_from("(x + 1).diff(1)"))
    assert_equal "usage: diff(var, n = 1)", hint.first
    assert_includes hint[1], "Derivative with respect to"
  end

  def test_no_hint_for_domain_errors_or_plain_ruby
    assert_nil RCAS::Chat::Usage.hint(error_from("ZZ[x].(x - 1) / (2*x - 2)"))
    assert_nil RCAS::Chat::Usage.hint(error_from("[1, 2].first(1, 2)"))
    assert_nil RCAS::Chat::Usage.hint(error_from(%q{foo("a")}))
  end

  def test_repl_prints_the_hint
    out = StringIO.new
    factory = ->(ws, ui, model) { RCAS::Chat::Assistant.new(ws, ui, model: model).tap { |a| a.define_singleton_method(:available?) { false } } }
    RCAS::Chat::REPL.new(input: StringIO.new("sum(x)\n"), output: out, assistant_factory: factory, persist: false, mode: :text).run
    assert_includes out.string, "ArgumentError: sum: which variable?"
    assert_includes out.string, "  usage: sum(f, k = nil, from = nil, to = nil, **range)\n"
    assert_includes out.string, "sum(k**2, k, 1, n)"
  end
end

class ChatPickerTest < Minitest::Test
  # A StringIO that behaves enough like a terminal for the picker: raw mode
  # is a no-op, keys come from the buffer.
  class FakeTTY < StringIO
    def tty? = true
    def raw(**) = yield(self)
    def winsize = [24, 80]
  end

  def setup
    RCAS::Chat::Style.enabled = false
    RCAS::Render.inline = false
    @dir = Dir.mktmpdir("rcas-sessions")
    @saved = RCAS::Chat::Session::DIR
    RCAS::Chat::Session.send(:remove_const, :DIR)
    RCAS::Chat::Session.const_set(:DIR, @dir)
    @a = session("quadratic forms", "e = (x + 1) * (1 - x)", "e.expand")
    sleep 0.01
    @b = session(nil, "factor x**6 - 1 over the integers")
    sleep 0.01
    @c = session("ode practice", "dsolve(D(y, x) - y, y, x)")
  end

  def teardown
    RCAS::Chat::Session.send(:remove_const, :DIR)
    RCAS::Chat::Session.const_set(:DIR, @saved)
    FileUtils.rm_rf(@dir)
    RCAS::Chat::Style.enabled = nil
    RCAS::Render.inline = nil
  end

  def session(title, *inputs)
    s = RCAS::Chat::Session.new
    inputs.each { |i| s.transcript << [:input, i] }
    s.title = title
    s.save
  end

  def test_find_by_name_id_prefix_and_index
    assert_equal @a.id, RCAS::Chat::Session.find("quadratic forms").id
    assert_equal @a.id, RCAS::Chat::Session.find("Quad").id, "case-insensitive prefix"
    assert_equal @c.id, RCAS::Chat::Session.find(@c.id[0..-2]).id
    assert_equal @c.id, RCAS::Chat::Session.find("1").id, "newest first"
    assert_nil RCAS::Chat::Session.find("nonesuch")
    assert_equal "factor x**6 - 1 over the integers", @b.name, "unnamed sessions go by their first input"
    assert_equal "just now", @b.relative_time
    tomorrow_noon = (@b.updated_at + 86_400).then { |t| Time.new(t.year, t.month, t.day, 12, 0, 0) }
    assert_equal "yesterday 09:30", @b.relative_time(tomorrow_noon).sub(/\d\d:\d\d/, "09:30")
  end

  def test_picker_moves_and_selects
    list = RCAS::Chat::Session.list
    out = FakeTTY.new
    chosen = RCAS::Chat::Picker.new(list, input: FakeTTY.new("\e[B\r"), output: out).run
    assert_equal list[1].id, chosen.id
    assert_includes out.string, "Resume a session"
    assert_includes out.string, "❯  2."
    assert out.string.end_with?("\e[J\e[?25h"), "the picker clears itself"
  end

  def test_picker_filters_and_cancels
    list = RCAS::Chat::Session.list
    chosen = RCAS::Chat::Picker.new(list, input: FakeTTY.new("ode\r"), output: FakeTTY.new).run
    assert_equal @c.id, chosen.id
    chosen = RCAS::Chat::Picker.new(list, input: FakeTTY.new("quad\x7F\x7F\x7F\x7Fquadr\r"), output: FakeTTY.new).run
    assert_equal @a.id, chosen.id
    assert_nil RCAS::Chat::Picker.new(list, input: FakeTTY.new("\e[B\e"), output: FakeTTY.new).run
    assert_nil RCAS::Chat::Picker.new(list, input: FakeTTY.new("zzz\r"), output: FakeTTY.new).run, "nothing matches, Enter picks nothing"
  end

  def test_picker_falls_back_to_a_numbered_list_without_a_terminal
    list = RCAS::Chat::Session.list
    out = StringIO.new
    chosen = RCAS::Chat::Picker.new(list, input: StringIO.new("3\n"), output: out).run
    assert_equal list[2].id, chosen.id
    assert_includes out.string, "Resume which?"
    chosen = RCAS::Chat::Picker.new(list, input: StringIO.new("ode practice\n"), output: StringIO.new).run
    assert_equal @c.id, chosen.id
  end

  def test_rename_and_resume_by_name_in_the_repl
    offline = ->(ws, ui, model) { RCAS::Chat::Assistant.new(ws, ui, model: model).tap { |a| a.define_singleton_method(:available?) { false } } }
    out = StringIO.new
    r = RCAS::Chat::REPL.new(input: StringIO.new("z = 5\n/rename fives\n/resume quadratic forms\n/vars\n/resume fives\n/vars\n/resume nonesuch\n"), output: out, assistant_factory: offline, mode: :text)
    r.run
    assert_includes out.string, 'session named "fives"'
    assert_includes out.string, "resumed quadratic forms"
    assert_match(/^  e\s+\(x \+ 1\)\*\(1 - x\)$/, out.string)
    assert_includes out.string, "resumed fives"
    assert_match(/^  z\s+5$/, out.string)
    assert_includes out.string, 'no unique session matches "nonesuch"'
    assert_equal "fives", RCAS::Chat::Session.find("fives").title
  end
end
