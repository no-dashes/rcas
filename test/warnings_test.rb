# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"

# The suite printed some 1190 warnings (24 Sept 2026); each kind that came
# from rcas was a small error of its own, and each has a test here.
class WarningsTest < Minitest::Test
  LIB = File.expand_path("../lib", __dir__)

  # the library, the chat and the window load under -w without a word: a
  # method defined twice (Chat::REPL#assistant), an unused variable
  # (Solve.float_roots), and a dependency of the anthropic gem that warns
  # about a variable of its own
  def test_every_part_loads_without_warnings
    _, err, status = Open3.capture3(RbConfig.ruby, "-w", "-I", LIB, "-e", 'require "rcas"; require "rcas/chat"; require "rcas/app"')
    assert status.success?, err
    assert_empty err
  end

  # C(n, k) past 2**1024 is no Float; converting it warned "Integer out of
  # Float range" 1141 times in one run, before the logarithms took over
  def test_a_large_binomial_coefficient_is_not_converted_to_a_float
    value = nil
    # C(3000, 1500) is about 10**901, and 1500 is inside the exact branch
    assert_output(nil, "") { value = RCAS::Distributions.binomial_pmf(3000, 1500, 0.5) }
    expected = Math.exp(Math.lgamma(3001).first - 2 * Math.lgamma(1501).first + 3000 * Math.log(0.5))
    assert_in_delta expected, value, expected * 1e-9
  end

  # reading a line to inspect it is not running it: `x + 1` on its own is
  # "possibly useless use of + in void context" to the parser
  def test_parsing_session_input_is_quiet
    verbose = $VERBOSE
    $VERBOSE = true
    assert_output(nil, "") do
      RCAS::Hold.parse("x + 1")
      RCAS::Hold.parse("f = x**2")
      RCAS::Hold.source("y * 2")
      RCAS.hold { :x + 1 }
    end
  ensure
    $VERBOSE = verbose
  end

  # a line that does not parse gives its SyntaxError and nothing on stderr
  # besides: `? hello` printed "invalid character syntax; use ?\s" first
  def test_a_chat_line_that_does_not_parse_is_only_a_syntax_error
    require "rcas/chat"
    workspace = RCAS::Chat::Workspace.new
    error = nil
    assert_output(nil, "") do
      error = assert_raises(SyntaxError) { workspace.eval("? hello") }
    end
    assert_match(/\(rcas\):1/, error.message)
    assert_equal RCAS::Num.new(2), workspace.eval("1 + 1r").first.then { |v| RCAS::Num.new(v) }
  end
end
