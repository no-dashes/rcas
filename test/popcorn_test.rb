# frozen_string_literal: true

require_relative "test_helper"

class PopcornTest < Minitest::Test
  # NB: never `include RCAS::Functions` in a test - its #diff overrides
  # Minitest::Assertions#diff and every failure message then raises.
  include RCAS::Constants

  OM = RCAS::OpenMath
  P = RCAS::OpenMath::Popcorn

  X = RCAS::Var.new(:x)
  K = RCAS::Var.new(:k)
  N = RCAS::Var.new(:n)

  def popcorn(obj) = RCAS.popcorn(obj)
  def back(text) = RCAS.from_popcorn(text)
  def parse(text) = P.parse(text).object

  # Write it, read it back, write it again.
  def assert_round_trip(text, message = nil)
    assert_equal text, P.render(P.parse(text)), message || "round trip of #{text}"
  end

  # ---- writing ------------------------------------------------------------

  def test_the_sugared_notation
    assert_equal "$x^2 + 1", popcorn(X**2 + 1)
    assert_equal "2*$x*(1 - $x)", popcorn(2 * X * (1 - X))
    assert_equal "-$x", popcorn(-X)
    assert_equal "sin($x)/cos($x)", popcorn(RCAS.sin(X)/RCAS.cos(X))
    assert_equal "$x < 3", popcorn(X < 3)
    assert_equal "$x^2 = 4", popcorn(RCAS::Equation.new(X**2, 4))
  end

  def test_to_s_is_the_same_notation_without_the_sugar
    om = RCAS.openmath(X**2 + 1)
    assert_equal "arith1.plus(arith1.power($x, 2), 1)", om.to_s
    assert_equal "$x^2 + 1", om.to_popcorn
    assert_equal om, P.parse(om.to_s), "the plain spelling is POPCORN too"
  end

  def test_the_notations_the_grammar_gives_their_own_syntax
    assert_equal "1//2", popcorn(RCAS::Num.new(Rational(1, 2))), "nums1.rational"
    assert_equal "3|4", popcorn(RCAS::Num.new(Complex(3, 4))), "complex1.complex_cartesian"
    assert_equal "i", popcorn(RCAS::I)
    assert_equal "interval_cc(0, 1)", popcorn(RCAS::Interval.new(0, 1)),
                 "a closed interval is interval1.interval_cc; .. is the plain interval1.interval"
    assert_equal "[1, $x, 2]", popcorn([1, X, 2]), "list1.list"
  end

  def test_bindings_and_the_formal_nodes
    assert_equal "int(lambda[$x -> sin($x)])", popcorn(RCAS.hold { integrate(sin(x), x) })
    assert_equal "defint(0 .. 1, lambda[$x -> $x^2])", popcorn(RCAS.hold { integrate(x**2, x, 0, 1) })
    assert_equal "sum(integer_interval(1, $n), lambda[$k -> $k^2])", popcorn(RCAS.hold { sum(k**2, k, 1, n) })
  end

  def test_brackets_appear_only_where_the_precedence_needs_them
    assert_equal "$x*($x + 1)", popcorn(X * (X + 1))
    assert_equal "$x*$x + 1", popcorn(X * X + 1)
    assert_equal "($x + 1)^2", popcorn((X + 1)**2)
    assert_equal "$x - ($x - 1)", popcorn(X - (X - 1)), "minus binds tighter than plus, which is what brackets this"
    assert_equal "-($x + 1)", popcorn(-(X + 1))
  end

  def test_a_private_symbol_is_never_shortened
    assert_equal "rcas1.gamma($z)", popcorn(RCAS.gamma(RCAS::Var.new(:z))),
                 "no one else would know what a bare gamma meant"
  end

  def test_an_unknown_function_is_a_variable_applied
    assert_equal "$u($n + 1)", popcorn(RCAS::Fn.new(:u, [N + 1]))
  end

  # ---- reading ------------------------------------------------------------

  def test_reading_gives_held_expressions
    assert_equal "x**2 + 1", back("$x^2 + 1").to_s
    assert_equal "1 + 2", back("1 + 2").to_s, "1 + 2 in OpenMath is not 3"
    assert_equal 3, back("1 + 2").simplify.value
    assert_equal "sin(x)/cos(x)", back("sin($x)/cos($x)").to_s
    assert_equal "integral(sin(t), t, 0, pi)", back("defint(0 .. pi, lambda[$t -> sin($t)])").to_s
  end

  def test_a_minus_in_front_of_a_literal_belongs_to_the_literal
    assert_equal OM::Int.new(-17), parse("-17")
    assert_equal OM::Double.new(-1.5), parse("-1.5")
    assert_equal OM::Application.new(OM.sym("arith1", "unary_minus"), OM::Variable.new("x")), parse("-$x")
  end

  def test_the_n_ary_operators_are_flattened_on_the_way_in
    assert_equal 3, parse("1 + 2 + 3").args.size, "arith1.plus takes them all"
    assert_equal 3, parse("$x*$y*$z").args.size
    assert_equal 2, parse("1 - 2 - 3").args.size, "minus stays binary"
  end

  def test_precedence
    assert_equal "1 + 2*3", P.render(P.parse("1 + 2*3"))
    assert_equal "(1 + 2)*3", P.render(P.parse("(1 + 2)*3"))
    assert_raises(OM::ParseError, "power does not chain in the grammar") { P.parse("$x^2^3") }
    assert_equal "($x^2)^3", P.render(P.parse("($x^2)^3"))
    assert_equal "$x + ($y - $z)", P.render(P.parse("$x + ($y - $z)"))
    assert_equal "$x - $y + $z", P.render(P.parse("$x - $y + $z"))
    assert_equal "$a and $b or $c", P.render(P.parse("$a and $b or $c"))
    assert_equal "$a = $b and $c", P.render(P.parse("$a = $b and $c"))
  end

  def test_the_operators_map_to_the_symbols_the_grammar_names
    assert_equal %w[relation2 approx], parse("1 ~ 2").head.key, "~ is relation2, not relation1"
    assert_equal %w[relation1 neq], parse("1 <> 2").head.key
    assert_equal %w[relation1 neq], parse("1 != 2").head.key
    assert_equal %w[nums1 rational], parse("1//2").head.key
    assert_equal %w[complex1 complex_cartesian], parse("1|2").head.key
    assert_equal %w[interval1 interval], parse("1 .. 2").head.key
    assert_equal %w[logic1 implies], parse("$a ==> $b").head.key
    assert_equal %w[logic1 equivalent], parse("$a <=> $b").head.key
    assert_equal %w[prog1 block], parse("$a; $b").head.key
    assert_equal %w[prog1 assign], parse("$a := $b").head.key
    assert_equal %w[prog1 if], parse("if $a then $b else $c endif").head.key
    assert_equal %w[prog1 while], parse("while $a do $b endwhile").head.key
    assert_equal %w[set1 set], parse("{1, 2}").head.key
    assert_equal %w[list1 list], parse("[1, 2]").head.key
  end

  def test_literals
    assert_equal 255, parse("0xFF").value
    assert_equal 2**80, parse((2**80).to_s).value
    assert_in_delta 1.5, parse("1.5").value, 1e-12
    assert_in_delta 1.5, parse("0f3FF8000000000000").value, 1e-12
    assert_in_delta 0.0001, parse("1.0e-4").value, 1e-12
    assert_equal "a\"b", parse('"a\\"b"').value
    assert_equal "hi", parse("%aGk=%").value
  end

  def test_symbols_variables_references_and_ids
    assert_equal OM::Variable.new("x"), parse("$x")
    assert_equal OM.sym("transc1", "sin"), parse("transc1.sin")
    assert_equal OM.sym("transc1", "sin"), parse("sin"), "a bare name is short for a symbol"
    assert_equal OM::Reference.new("#a"), parse("#a")
    assert_equal OM::Reference.new("http://example.org/x"), parse("##http://example.org/x##")
    assert_equal "thing", parse("1:thing").id
    assert_equal "1:thing", P.render(P.parse("1:thing"))
  end

  def test_attributions_and_errors
    attributed = parse('$x{altenc.LaTeX_encoding -> "x"}')
    assert_instance_of OM::Attribution, attributed
    assert_equal OM::Variable.new("x"), attributed.object
    assert_equal OM::Text.new("x"), attributed.pairs.first.value
    error = parse("aa.bb!($x, 1)")
    assert_instance_of OM::Error, error
    assert_equal 2, error.args.size
  end

  def test_foreign_content_survives
    node = parse('$x{altenc.MathML_encoding -> `<mi>x</mi>`}')
    assert_instance_of OM::Foreign, node.pairs.first.value
    assert_equal "<mi>x</mi>", node.pairs.first.value.content
  end

  def test_comments_and_whitespace_are_skipped
    assert_equal parse("1 + 2"), parse("1 /* a comment */ +\n  2")
  end

  def test_what_it_refuses
    assert_raises(OM::ParseError) { parse("$x +") }
    assert_raises(OM::ParseError) { parse("1 2") }
    assert_raises(OM::ParseError) { parse("nosuchsymbolanywhere") }
    assert_raises(OM::ParseError) { parse("$a::$b") }
    assert_raises(OM::ParseError) { parse("and") }
    assert_raises(OM::EncodeError) { P.render(OM::Double.new(Float::INFINITY)) }
  end

  # ---- both ways ----------------------------------------------------------

  def test_round_trips
    [
      "$x^2 + 1", "1 + 2*3", "-17", "-$x", "1//2", "3|4", "0 .. 1",
      "sin($x)/cos($x)", "lambda[$x -> $x^2]", "int(lambda[$x -> sin($x)])",
      "[1, 2, 3]", "{1, 2}", "$u($n + 1)", "$x < 3", "$a and $b",
      "rcas1.gamma($z)", "arith3.frobnicate($x, 7)", '"text"', "$x:one"
    ].each { |text| assert_round_trip text }
  end

  def test_the_three_encodings_agree
    [X**2 + 1, RCAS.sin(X)/X, RCAS::Equation.new(X**2, 4), RCAS.hold { sum(k**2, k, 1, n) }].each do |expression|
      om = RCAS.openmath(expression)
      assert_equal om, OM::XML.decode(om.to_xml), "XML"
      assert_equal om, P.parse(om.to_popcorn), "POPCORN"
      assert_equal om, P.parse(om.to_s), "POPCORN without the sugar"
    end
  end
end
