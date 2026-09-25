# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"

# Drives bin/rcas with piped input, so this covers the real irb integration.
class IrbTest < Minitest::Test
  BIN = File.expand_path("../bin/rcas", __dir__)

  # Returns the result lines irb printed. Without a tty irb echoes each
  # input line followed by its inspected value, with no "=> " prefix.
  def run_session(*lines, env: {})
    # The interpreter and the script as separate arguments: Open3 hands a
    # lone string to the shell, which splits a project path on its spaces.
    out, _err, status = Open3.capture3(env, RbConfig.ruby, BIN, stdin_data: lines.join("\n") + "\n")
    assert status.success?, out
    out.lines.map(&:chomp)
  end

  def test_bare_identifiers_become_symbols_and_locals
    out = run_session("e = (x + 1) * (1 - x)", "x", "e.expand", "local_variables.sort")
    assert_includes out, "(x + 1)*(1 - x)"
    assert_includes out, ":x"
    assert_includes out, "1 - x**2"
    assert_includes out, "[:_, :e, :x]"
  end

  def test_kernel_printers_double_as_indeterminates
    out = run_session("p**2 + 1", "pp + 1", "x = p", "Kernel.p(42)", "p(42)")
    assert_includes out, "p**2 + 1"
    assert_includes out, "pp + 1"
    assert_includes out, ":p"
    assert_includes out, "42", "Kernel.p still prints"
    assert out.none? { |l| l.include?("undefined method") }, out.join("\n")
    assert_includes out, "p(42)", "p(42) is the unknown function p applied to 42, not a printer"
  end

  def test_unicode_names_and_constants
    out = run_session("α**2 + β₁", "sin(π/6)", "sum(1/n**2, n: 1..∞)", "hold { α + π }", "x = ∞")
    assert_includes out, "α**2 + β₁"
    assert_includes out, "1/2"
    assert_includes out, "pi**2/6"
    assert_includes out, "α + pi"
    assert_includes out, "oo"
  end

  def test_the_session_is_kept_in_the_tables
    out = run_session("x**2 - 1", "factor(Out[1])", "Out[-1].expand", "integrate(sin(y), y)", "In[-1]", "Out", "In")
    assert_includes out, "(-1 + x)*(1 + x)", "Out[1] is the result of the first line"
    assert_includes out, "-1 + x**2", "Out[-1] is the previous one"
    assert_includes out, "integral(sin(y), y)", "In[-1] is the previous line held, not its value"
    assert_includes out, "[1] x**2 - 1", "the table prints itself, one line per line"
    assert_includes out, "[3] -1 + x**2"
    assert_includes out, "[2] factor(Out[1])", "In prints the lines as they were typed"
  end

  # The number goes in the prompt, and irb prints no prompt without a tty,
  # so what is left to see here is that the results keep their own format,
  # numbered (the default) or not.
  def test_the_numbers_leave_the_results_alone
    %w[1 0].each do |numbered|
      out = run_session("x + 1", "Out[1] * 2", env: { "RCAS_NUMBERED" => numbered })
      assert_includes out, "x + 1"
      assert_includes out, "(x + 1)*2"
      assert out.none? { |l| l.start_with?("[1]") }, out.join("\n")
    end
  end

  def test_functions_are_available_bare
    out = run_session("sin(y).diff(y)", "sqrt(4).simplify")
    assert_includes out, "cos(y)"
    assert_includes out, "2"
  end

  def test_unknown_functions_and_real_missing_methods
    out = run_session("foo(1)", "u(n + 1) + u(n)", 'foo("a")')
    assert_includes out, "foo(1)", "an undefined name applied to a number is an unknown function"
    assert_includes out, "u(n + 1) + u(n)"
    assert out.grep(/undefined method [`']foo'/).any?, "other argument kinds still raise: #{out.join("\n")}"
  end
  def test_refusals_print_one_line_with_the_usage
    out, err, status = Open3.capture3(RbConfig.ruby, BIN, stdin_data: "solve(sin(x) - x**x, x)\nintegrate()\n")
    assert status.success?, out + err
    assert_includes out, "RCAS::Unsupported: can't solve sin(x) - x**x = 0 for x; nsolve(sin(x) - x**x, x: a..b) finds a root numerically"
    assert_includes out, "ArgumentError: wrong number of arguments (given 0, expected 1..4)"
    assert out.lines.any? { |l| l.start_with?("  usage: integrate(") }, out
    refute_match(/solve\.rb:\d+/, out, "no backtrace for a refusal")
  end

  def test_bugs_and_the_flag_keep_the_backtrace
    out, = Open3.capture3(RbConfig.ruby, BIN, stdin_data: "foo.bar\n")
    assert_match(/NoMethodError/, out)
    assert_match(/from /, out, "a NoMethodError is a bug and keeps its trace")
    out, = Open3.capture3({ "RCAS_BACKTRACE" => "1" }, RbConfig.ruby, BIN, stdin_data: "solve(sin(x) - x**x, x)\n")
    assert_match(/solve\.rb:\d+/, out, "RCAS_BACKTRACE=1 shows where a refusal came from")
  end

  def test_integer_division_is_warned
    out, err, = Open3.capture3(RbConfig.ruby, BIN, stdin_data: "x + 1/3\nhold { 1/2 }\n")
    assert_includes out, "x + 0"
    assert_equal ["warning: 1/3 is 0: Ruby divides two Integers as integers, rounding down; write 1/3r for the fraction"],
                 err.lines.map(&:chomp).grep(/^warning/)
  end
end
