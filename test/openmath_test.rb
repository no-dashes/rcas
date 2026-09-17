# frozen_string_literal: true

require_relative "test_helper"

class OpenMathTest < Minitest::Test
  # NB: never `include RCAS::Functions` in a test - its #diff overrides
  # Minitest::Assertions#diff and every failure message then raises.
  include RCAS::Constants

  OM = RCAS::OpenMath

  X = RCAS::Var.new(:x)
  K = RCAS::Var.new(:k)
  N = RCAS::Var.new(:n)

  def om(obj) = RCAS.openmath(obj)
  def back(source) = RCAS.from_openmath(source)

  # Encode, write, read, encode again: the OpenMath object must survive.
  def assert_round_trip(obj, message = nil)
    first = om(obj)
    again = om(back(first.to_xml))
    assert_equal first, again, message || "round trip of #{obj}"
  end

  # ---- the objects -------------------------------------------------------

  def test_objects_are_structural_and_frozen
    a = OM::Application.new(OM.sym("arith1", "plus"), OM::Int.new(1), OM::Variable.new("x"))
    b = OM::Application.new(OM.sym("arith1", "plus"), OM::Int.new(1), OM::Variable.new("x"))
    assert_equal a, b
    assert_equal a.hash, b.hash
    assert_equal 1, { a => 1 }[b], "equal objects are the same hash key"
    assert_predicate a, :frozen?
    refute_equal a, OM::Application.new(OM.sym("arith1", "times"), OM::Int.new(1), OM::Variable.new("x"))
  end

  def test_an_id_is_not_part_of_equality
    plain = OM::Int.new(2)
    tagged = plain.identified("t1")
    assert_equal "t1", tagged.id
    assert_equal plain, tagged, "two objects are equal when they say the same thing"
    assert_nil plain.id, "the original is untouched"
  end

  def test_printing_is_not_xml
    assert_equal "arith1.plus($x, 1)", om(X + 1).to_s
    assert_equal "arith1.plus", OM.sym("arith1", "plus").to_s
    assert_equal "fns1.lambda[$x -> $x]", OM::Bind.new(OM.sym("fns1", "lambda"), OM::BVar.new(OM::Variable.new("x")), OM::Variable.new("x")).to_s
  end

  def test_lift_refuses_what_it_cannot_carry
    assert_equal OM::Int.new(3), OM.lift(3)
    assert_equal OM::Variable.new("x"), OM.lift(:x)
    assert_raises(TypeError) { OM.lift(Object.new) }
  end

  # ---- the XML encoding ---------------------------------------------------

  def test_xml_encoding_of_a_small_object
    expected = '<OMOBJ xmlns="http://www.openmath.org/OpenMath" version="2.0">' \
               '<OMA><OMS cd="arith1" name="plus"/><OMV name="x"/><OMI>1</OMI></OMA></OMOBJ>'
    assert_equal expected, om(X + 1).to_xml
  end

  def test_xml_is_read_back_into_the_same_objects
    source = om(X + 1).to_xml
    assert_equal om(X + 1), OM::XML.decode(source)
  end

  def test_the_reader_accepts_what_other_systems_write
    source = <<~XML
      <?xml version="1.0"?>
      <!-- an object with a namespace prefix, comments and odd spacing -->
      <om:OMOBJ xmlns:om="http://www.openmath.org/OpenMath" version="2.0">
        <om:OMA>
          <om:OMS cd="arith1" name="plus" />
          <om:OMI> 17 </om:OMI>
          <om:OMV name="y"/>
        </om:OMA>
      </om:OMOBJ>
    XML
    assert_equal "17 + y", back(source).to_s
  end

  def test_the_reader_reports_what_it_cannot_read
    assert_raises(OM::ParseError) { OM::XML.decode("<OMOBJ><OMA></OMA></OMOBJ>") }
    assert_raises(OM::ParseError) { OM::XML.decode("<OMOBJ><OMV/></OMOBJ>") }
    assert_raises(OM::ParseError) { OM::XML.decode("<OMOBJ><OMFOO/></OMOBJ>") }
    assert_raises(OM::ParseError) { OM::XML.decode("<OMOBJ><OMI>1</OMI>") }
  end

  def test_escaping_and_entities
    text = OM::Text.new(%(a < b & "c"))
    assert_includes OM::XML.encode(text), "a &lt; b &amp; &quot;c&quot;"
    assert_equal text, OM::XML.decode(OM::XML.encode(text)).object
  end

  def test_integers_floats_and_bytes
    assert_equal 2**80, OM::XML.decode("<OMOBJ><OMI>#{2**80}</OMI></OMOBJ>").object.value
    assert_equal 31, OM::XML.decode('<OMOBJ><OMI>x1F</OMI></OMOBJ>').object.value
    assert_equal(-31, OM::XML.decode('<OMOBJ><OMI>-x1F</OMI></OMOBJ>').object.value)
    assert_in_delta 1.5, OM::XML.decode('<OMOBJ><OMF dec="1.5"/></OMOBJ>').object.value, 1e-12
    assert_in_delta 1.5, OM::XML.decode('<OMOBJ><OMF hex="3FF8000000000000"/></OMOBJ>').object.value, 1e-12
    assert_equal Float::INFINITY, OM::XML.decode('<OMOBJ><OMF dec="INF"/></OMOBJ>').object.value
    bytes = OM::Bytes.new("\x00\x01\xFF".b)
    assert_equal bytes, OM::XML.decode(OM::XML.encode(bytes)).object
  end

  def test_indentation_is_only_for_reading
    pretty = om(X + 1).to_xml(indent: 2)
    assert_includes pretty, "\n  <OMA>"
    assert_equal om(X + 1), OM::XML.decode(pretty), "the same object either way"
  end

  def test_references_are_resolved_into_a_tree
    source = <<~XML
      <OMOBJ version="2.0">
        <OMA><OMS cd="arith1" name="plus"/>
          <OMA id="shared"><OMS cd="arith1" name="times"/><OMV name="x"/><OMV name="y"/></OMA>
          <OMR href="#shared"/>
        </OMA>
      </OMOBJ>
    XML
    assert_equal "x*y + x*y", back(source).to_s
  end

  # ---- the phrasebook, expression by expression ---------------------------

  def test_arithmetic_and_the_shape_of_the_tree
    assert_equal "arith1.times(arith1.plus($x, 1), arith1.minus(1, $x))", om((X + 1) * (1 - X)).to_s
    assert_equal "(x + 1)*(1 - x)", back(om((X + 1) * (1 - X)).to_xml).to_s,
                 "construction never rewrites: the tree comes back as it was written"
    assert_equal "arith1.unary_minus($x)", om(-X).to_s
  end

  def test_an_n_ary_operator_folds_left_on_the_way_in
    source = '<OMOBJ><OMA><OMS cd="arith1" name="plus"/><OMV name="x"/><OMV name="y"/><OMV name="z"/></OMA></OMOBJ>'
    assert_equal "x + y + z", back(source).to_s
    assert_equal RCAS::Add.new(RCAS::Add.new(X, RCAS::Var.new(:y)), RCAS::Var.new(:z)), back(source)
  end

  def test_numbers
    assert_equal "nums1.rational(1, 2)", om(RCAS::Num.new(Rational(1, 2))).to_s
    assert_equal "3", om(3).to_s
    assert_equal "1.5", om(1.5).to_s
    assert_equal "nums1.i", om(RCAS::I).to_s
    assert_equal "complex1.complex_cartesian(1, 2)", om(RCAS::Num.new(Complex(1, 2))).to_s
    assert_equal Rational(1, 2), back(om(RCAS::Num.new(Rational(1, 2))).to_xml).value
    assert_equal Complex(1, 2), back(om(RCAS::Num.new(Complex(1, 2))).to_xml).value
  end

  def test_constants
    assert_equal "nums1.pi", om(PI).to_s
    assert_equal "nums1.infinity", om(RCAS::OO).to_s
    assert_equal PI, back('<OMOBJ><OMS cd="nums1" name="pi"/></OMOBJ>')
    assert_equal RCAS::E, back('<OMOBJ><OMS cd="nums1" name="e"/></OMOBJ>')
    assert_equal RCAS::I, back('<OMOBJ><OMS cd="nums1" name="i"/></OMOBJ>')
  end

  def test_functions_both_ways
    assert_equal "transc1.sin($x)", om(RCAS.sin(X)).to_s
    assert_equal "transc1.ln($x)", om(RCAS.log(X)).to_s
    assert_equal "integer1.factorial($n)", om(RCAS.factorial(N)).to_s
    assert_equal "combinat1.binomial($n, $k)", om(RCAS.binomial(N, K)).to_s
    assert_equal "rounding1.floor($x)", om(RCAS.floor(X)).to_s
    %w[sin cos tan exp].each do |name|
      assert_round_trip RCAS::Fn.new(name.to_sym, [X])
    end
  end

  def test_a_logarithm_to_a_base_becomes_a_quotient
    source = '<OMOBJ><OMA><OMS cd="transc1" name="log"/><OMI>2</OMI><OMV name="x"/></OMA></OMOBJ>'
    assert_equal "log(x)/log(2)", back(source).to_s
  end

  def test_a_root_becomes_a_power
    source = '<OMOBJ><OMA><OMS cd="arith1" name="root"/><OMV name="x"/><OMI>3</OMI></OMA></OMOBJ>'
    assert_equal "x**(1/3)", back(source).to_s
  end

  def test_the_names_rcas_has_and_openmath_has_not
    symbol = om(RCAS.gamma(X)).object.head
    assert_equal %w[rcas1 gamma], symbol.key
    assert_equal OM::RCAS_CDBASE, symbol.cdbase, "a private CD carries its cdbase"
    refute_predicate symbol, :official?
    assert_round_trip RCAS.gamma(X)
    assert_round_trip RCAS.erf(X) + RCAS.zeta(X) + RCAS.Si(X)
  end

  def test_the_formal_nodes
    assert_round_trip RCAS.hold { integrate(sin(x), x) }
    assert_round_trip RCAS.hold { integrate(x**2, x, 0, 1) }
    assert_round_trip RCAS.hold { sum(k**2, k, 1, n) }
    assert_round_trip RCAS::Product.new(K, K, RCAS::Num.new(1), N)
    assert_round_trip RCAS::Derivative.new(RCAS::Fn.new(:y, [X]), X, 2)
    assert_round_trip RCAS::Limit.new(RCAS.sin(X) / X, X, RCAS::Num.new(0))
    assert_equal "calculus1.int(fns1.lambda[$x -> transc1.sin($x)])", om(RCAS.hold { integrate(sin(x), x) }).to_s
    assert_equal "arith1.sum(interval1.integer_interval(1, $n), fns1.lambda[$k -> arith1.power($k, 2)])",
                 om(RCAS.hold { sum(k**2, k, 1, n) }).to_s
  end

  def test_a_decoded_integral_is_held_not_computed
    result = back(om(RCAS.hold { integrate(x**2, x, 0, 1) }).to_xml)
    assert_instance_of RCAS::Integral, result, "1 + 2 in OpenMath is not 3, and neither is an integral"
    assert_equal Rational(1, 3), result.doit.value, "and doit still answers it"
  end

  def test_relations_intervals_and_sets
    assert_equal "relation1.eq(arith1.power($x, 2), 4)", om(RCAS::Equation.new(X**2, 4)).to_s
    assert_equal "relation1.lt($x, 3)", om(X < 3).to_s
    assert_equal "x**2 = 4", back(om(RCAS::Equation.new(X**2, 4)).to_xml).to_s
    assert_equal "x < 3", back(om(X < 3).to_xml).to_s
    assert_equal "interval1.interval_co(0, 1)", om(RCAS::Interval.new(0, 1, right_open: true)).to_s
    assert_equal "[0, 1)", back(om(RCAS::Interval.new(0, 1, right_open: true)).to_xml).to_s
    assert_equal "setname1.Z", om(RCAS::ZZ).to_s
    assert_equal RCAS::QQ, back('<OMOBJ><OMS cd="setname1" name="Q"/></OMOBJ>')
  end

  def test_piecewise_carries_its_conditions
    f = RCAS.piecewise((X < 0) => -X, :else => X)
    assert_equal "piece1.piecewise(piece1.piece(arith1.unary_minus($x), relation1.lt($x, 0)), piece1.otherwise($x))", om(f).to_s
    assert_equal f, back(om(f).to_xml), "piece1.piece is (value, condition), that way round"
  end

  def test_matrices_vectors_and_lists
    m = RCAS.matrix([[1, 2], [3, 4]])
    assert_equal "linalg2.matrix(linalg2.matrixrow(1, 2), linalg2.matrixrow(3, 4))", om(m).to_s
    assert_equal m, back(om(m).to_xml)
    assert_equal RCAS.vector([1, 2, 3]), back(om(RCAS.vector([1, 2, 3])).to_xml)
    assert_equal [1, X, 2], back(om([1, X, 2]).to_xml)
  end

  def test_an_algebraic_number
    root = RCAS.solve(X**3 - X - 1, :x).first
    assert_instance_of RCAS::RootOf, root
    assert_equal root, back(om(root).to_xml)
  end

  # ---- nothing is lost in silence -----------------------------------------

  def test_an_unknown_symbol_survives_the_round_trip
    source = '<OMOBJ><OMA><OMS cd="arith3" name="frobnicate"/><OMV name="x"/><OMI>7</OMI></OMA></OMOBJ>'
    held = back(source)
    assert_equal "arith3.frobnicate(x, 7)", held.to_s, "a symbol with no row is a held unknown function"
    assert_equal OM::XML.decode(source), om(held), "and encodes back to the symbol it came from"
  end

  def test_an_unknown_function_is_an_omv_application
    assert_equal "$u(arith1.plus($n, 1))", om(RCAS::Fn.new(:u, [N + 1])).to_s
    assert_round_trip RCAS::Fn.new(:u, [N + 1])
  end

  def test_a_one_sided_limit_stays_as_it_came
    source = <<~XML
      <OMOBJ><OMA><OMS cd="limit1" name="limit"/><OMI>0</OMI>
        <OMS cd="limit1" name="above"/>
        <OMBIND><OMS cd="fns1" name="lambda"/><OMBVAR><OMV name="x"/></OMBVAR>
          <OMA><OMS cd="arith1" name="divide"/><OMI>1</OMI><OMV name="x"/></OMA></OMBIND>
      </OMA></OMOBJ>
    XML
    held = back(source)
    refute_instance_of RCAS::Limit, held, "rcas's Limit node has no direction, so this is not one"
    assert_equal OM::XML.decode(source), om(held), "it comes back exactly as it arrived"
  end

  def test_an_error_object_is_data
    source = '<OMOBJ><OME><OMS cd="error" name="unhandled_symbol"/><OMS cd="arith3" name="nope"/></OME></OMOBJ>'
    assert_equal OM::XML.decode(source), om(back(source))
  end

  def test_what_cannot_be_encoded_says_so
    assert_raises(OM::EncodeError) { RCAS.openmath(Object.new) }
    assert_raises(OM::ParseError) { back('<OMOBJ><OMSTR>hello</OMSTR></OMOBJ>') }
  end

  # ---- foreign content ----------------------------------------------------

  def test_foreign_content_is_carried_exactly_as_it_came
    source = <<~XML
      <OMOBJ version="2.0">
        <OMATTR>
          <OMATP><OMS cd="altenc" name="MathML_encoding"/>
            <OMFOREIGN encoding="application/mathml-presentation+xml"><mrow><mi>x</mi><mo>+</mo><mn>1</mn></mrow></OMFOREIGN>
          </OMATP>
          <OMA><OMS cd="arith1" name="plus"/><OMV name="x"/><OMI>1</OMI></OMA>
        </OMATTR>
      </OMOBJ>
    XML
    node = OM::XML.decode(source)
    foreign = node.object.pairs.first.value
    assert_instance_of OM::Foreign, foreign
    assert_equal "<mrow><mi>x</mi><mo>+</mo><mn>1</mn></mrow>", foreign.content, "markup and all, never parsed"
    assert_equal "application/mathml-presentation+xml", foreign.encoding
    assert_equal node, OM::XML.decode(OM::XML.encode(node)), "and it survives being written out again"
    assert_equal "x + 1", node.to_expression.to_s, "the attributes are dropped, the object is read"
  end

  def test_foreign_content_is_a_derived_object_and_goes_only_where_it_may
    foreign = OM::Foreign.new("<mi>x</mi>")
    refute_predicate foreign, :object?
    assert OM::Int.new(1).object?
    # legal: the value of an attribution and an argument of an error
    OM::Attribution.new([[OM.sym("altenc", "MathML_encoding"), foreign]], OM::Int.new(1))
    OM::Error.new(OM.sym("error", "unexpected_symbol"), foreign)
    # illegal everywhere else
    assert_raises(TypeError) { OM::Application.new(OM.sym("arith1", "plus"), foreign) }
    assert_raises(TypeError) { OM::Application.new(foreign, OM::Int.new(1)) }
    assert_raises(TypeError) { OM::Root.new(foreign) }
    assert_raises(TypeError) { OM::Bind.new(OM.sym("fns1", "lambda"), OM::Variable.new("x"), foreign) }
  end

  # ---- the table covers every node ----------------------------------------

  def test_every_expression_class_has_a_row
    classes = ObjectSpace.each_object(Class).select { |c| c < RCAS::Expression } - [RCAS::BinaryOp]
    missing = classes - OM::Phrasebook::ENCODE_CLASS.keys
    assert_empty missing, "every Expression class needs a row in the phrasebook (see Printer, LaTeX.print)"
  end

  def test_every_function_row_names_a_symbol_rcas_can_build
    OM::Phrasebook::ENCODE_FN.each do |name, (cd, symbol)|
      assert_kind_of String, cd
      assert_kind_of String, symbol
      assert_equal [cd, symbol], OM::Phrasebook::DECODE_APPLY.keys.find { |k| k == [cd, symbol] },
                   "#{name} encodes to #{cd}.#{symbol}, which must decode again"
    end
  end
end
