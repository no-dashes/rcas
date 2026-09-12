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

  def test_functions_are_available_bare
    out = run_session("sin(y).diff(y)", "sqrt(4).simplify")
    assert_includes out, "cos(y)"
    assert_includes out, "2"
  end

  def test_real_missing_methods_still_raise
    out = run_session("foo(1)")
    assert out.grep(/undefined method `foo'/).any?, out.join("\n")
  end
end
