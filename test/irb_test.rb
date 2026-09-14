# frozen_string_literal: true

require_relative "test_helper"
require "open3"

# Drives bin/rcas with piped input, so this covers the real irb integration.
class IrbTest < Minitest::Test
  BIN = File.expand_path("../bin/rcas", __dir__)

  # Returns the result lines irb printed. Without a tty irb echoes each
  # input line followed by its inspected value, with no "=> " prefix.
  def run_session(*lines)
    out, _err, status = Open3.capture3(BIN, stdin_data: lines.join("\n") + "\n")
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

  def test_functions_are_available_bare
    out = run_session("sin(y).diff(y)", "sqrt(4).simplify")
    assert_includes out, "cos(y)"
    assert_includes out, "2"
  end

  def test_unknown_functions_and_real_missing_methods
    out = run_session("foo(1)", "u(n + 1) + u(n)", 'foo("a")')
    assert_includes out, "foo(1)", "an undefined name applied to a number is an unknown function"
    assert_includes out, "u(n + 1) + u(n)"
    assert out.grep(/undefined method `foo'/).any?, "other argument kinds still raise: #{out.join("\n")}"
  end
end
