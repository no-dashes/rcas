# frozen_string_literal: true

require_relative "test_helper"

class DiscussionTest < Minitest::Test
  X = RCAS::Var.new(:x)
  T = RCAS::Var.new(:t)

  def discuss(f, var = :x) = RCAS.discuss(f, var)

  def test_the_whole_report_of_a_cubic
    expected = <<~REPORT.chomp
      f(x) = x**3 - 3*x
        domain       (-oo, oo)
        symmetry     odd: f(-x) = -f(x), symmetric about the origin
        zeros        -3**(1/2), 0, 3**(1/2)
        y intercept  f(0) = 0
        at infinity  f -> -oo as x -> -oo; f -> oo as x -> oo
        asymptotes   none
        extrema      maximum at (-1, 2); minimum at (1, -2)
        monotonic    increasing on (-oo, -1), decreasing on (-1, 1), increasing on (1, oo)
        inflections  (0, 0)
        curvature    concave on (-oo, 0), convex on (0, oo)
    REPORT
    assert_equal expected, discuss(X**3 - 3 * X).to_s
  end

  def test_the_answers_are_the_ones_the_single_functions_give
    f = X**4 - 2 * X**2 + 1
    report = discuss(f)
    assert_equal RCAS.extrema(f, :x).map(&:to_s), report.extrema.map(&:to_s)
    assert_equal RCAS.inflections(f, :x).map(&:to_s), report.inflections.map { |p, _| p.to_s }
    assert_equal RCAS.real_domain(f, :x), report.domain
    assert_equal RCAS.solve(f, :x).map(&:to_s).sort, report.zeros.map(&:to_s).sort
  end

  def test_the_indeterminate_is_inferred_and_can_be_another_one
    assert_equal "f(t) = t**2 - 1", discuss(T**2 - 1, :t).to_s.lines.first.chomp
    assert_equal "f(x) = x**2 - 1", discuss(X**2 - 1, nil).to_s.lines.first.chomp
    assert_raises(ArgumentError) { RCAS.discuss(X * RCAS::Var.new(:y)) }
  end

  def test_symmetry_and_the_intercept
    assert_equal :even, discuss(X**2 + 1).symmetry
    assert_equal :odd, discuss(X**3 + X).symmetry
    assert_equal :odd, discuss((X**2 + 1) / X).symmetry
    assert_equal :none, discuss(X**2 + X).symmetry
    assert_equal "1", discuss(X**2 + 1).intercept.to_s
    assert_nil discuss(1 / X).intercept, "0 is not in the domain"
  end

  def test_a_pole_and_an_oblique_asymptote
    report = discuss((X**2 + 1) / X)
    assert_equal "(-oo, 0) ∪ (0, oo)", report.domain.to_s
    assert_equal [["0", :pole]], report.gaps.map { |p, kind, _, _| [p.to_s, kind] }
    assert_equal ["0"], report.asymptotes[:vertical].map(&:to_s)
    assert_equal ["x"], report.asymptotes[:oblique].map(&:to_s)
    assert_empty report.zeros
    assert_equal ["increasing on (-oo, -1)", "decreasing on (-1, 0)", "decreasing on (0, 1)", "increasing on (1, oo)"],
                 report.monotonicity.map { |i, kind| "#{kind} on #{i}" }, "the pole cuts the chart in two"
  end

  def test_a_gap_that_cancels_away_is_still_a_gap
    report = discuss((X**2 - 1) / (X - 1))
    assert_equal "(-oo, 1) ∪ (1, oo)", report.domain.to_s
    assert_equal [["1", :removable]], report.gaps.map { |p, kind, _, _| [p.to_s, kind] }
    assert_empty report.asymptotes[:oblique], "the line through the hole is the graph itself, not an asymptote"
  end

  def test_only_the_ends_the_domain_reaches
    report = discuss(RCAS.log(X) / X)
    assert_equal "(0, oo)", report.domain.to_s
    assert_equal ["oo"], report.limits.map { |point, _| point.to_s }
    assert_equal "0", report.limits.first.last.to_s
    assert_equal ["e"], report.extrema.map { |p, _, _| p.to_s }
  end

  def test_a_product_solve_cannot_do_is_split_into_its_factors
    report = discuss(RCAS.exp(-X**2))
    assert_equal ["0"], report.extrema.map { |p, _, _| p.to_s }
    assert_equal :maximum, report.extrema.first.last
    assert_equal ["-2**(1/2)/2", "2**(1/2)/2"], report.inflections.map { |p, _| p.to_s }
    assert_equal ["y = 0"], report.asymptote_items.map { |item| RCAS::Discussion::Report.render(item) }
  end

  def test_a_periodic_function_is_discussed_over_one_period
    report = discuss(RCAS.sin(X))
    assert_equal "2*pi", report.period.to_s
    assert_equal ["0", "pi"], report.zeros.map(&:to_s)
    assert_equal [nil, nil], report.limits.map(&:last), "a periodic function has no limit at infinity"
    assert_equal ["increasing on (0, pi/2)", "decreasing on (pi/2, 3*pi/2)", "increasing on (3*pi/2, 2*pi)"],
                 report.monotonicity.map { |i, kind| "#{kind} on #{i}" }
    assert_includes report.to_s, "zeros        0, pi (+ k*2*pi, k an integer)"
    assert_nil discuss(X**2 + 1).period
    assert_equal "pi", discuss(RCAS.sin(2 * X)).period.to_s
    assert_equal "2*pi", discuss(RCAS.sin(2 * X) + RCAS.cos(X)).period.to_s, "the least common multiple of the parts"
    assert_equal "2*pi", discuss(RCAS.cos(X)**2).period.to_s, "a period, not always the smallest one"
  end

  def test_what_rcas_cannot_decide_says_so
    report = discuss(RCAS.exp(X) + X)
    assert_nil report.zeros, "the zeros of exp(x) + x are out of reach"
    assert_includes report.to_s, "zeros        not determined"
    assert_empty discuss(X**2 + 1).zeros, "none is a different answer"
    assert_includes discuss(X**2 + 1).to_s, "zeros        none"
  end

  def test_the_sign_chart_agrees_with_the_derivative
    [X**3 - 3 * X, X**4 - 2 * X**2 + 1, RCAS.exp(-X**2), (X**2 + 1) / X].each do |f|
      report = discuss(f)
      first = report.derivatives.first
      report.monotonicity.each do |interval, kind|
        point = sample(interval)
        value = RCAS::Analysis.numeric(first.subs(X => RCAS::Num.new(point)))
        assert_equal kind == :increasing, value.positive?, "#{f} is #{kind} on #{interval}, but f'(#{point}) = #{value}"
      end
    end
  end

  def test_a_function_rcas_cannot_differentiate_still_gets_a_report
    report = discuss(RCAS::Fn.new(:u, [X]) + X)
    assert_equal [nil, nil, nil], report.derivatives
    assert_nil report.extrema
    assert_nil report.curvature
    assert_equal "u(0)", report.intercept.to_s
    assert_includes RCAS.steps(RCAS::Fn.new(:u, [X]) + X, :x, :discuss).to_s, "rcas cannot differentiate this one"
  end

  def test_an_absolute_value_is_discussed_through_its_cases
    report = discuss(RCAS.abs(X) - 1)
    assert_equal ["-1", "1"], report.zeros.map(&:to_s)
    assert_equal [["0", "-1", :minimum]], report.extrema.map { |p, v, kind| [p.to_s, v.to_s, kind] }
    assert_equal ["decreasing on (-oo, 0)", "increasing on (0, oo)"], report.monotonicity.map { |i, kind| "#{kind} on #{i}" }
    assert_empty report.curvature, "a graph made of two straight pieces has no curvature"
  end

  def test_a_line_and_a_constant
    assert_equal "none", row(discuss(2 * X + 1), "curvature"), "a straight graph has no curvature"
    assert_equal "none", row(discuss(RCAS::Num.new(3)), "monotonic")
    assert_equal "3", discuss(RCAS::Num.new(3)).intercept.to_s
  end

  def test_the_report_typesets
    latex = RCAS::LaTeX.of(discuss(X**3 - 3 * X))
    assert_includes latex, "\\begin{aligned}"
    assert_includes latex, "\\text{domain} &: \\left(-\\infty, \\infty\\right)"
    assert_includes latex, "\\sqrt{3}"
  end

  # ---- the worked ritual -----------------------------------------------------

  def test_steps_narrate_the_ritual_and_end_in_the_report
    worked = RCAS.steps(X**3 - 3 * X, :x, :discuss)
    assert_equal "discuss(x**3 - 3*x, x)", worked.problem.to_s
    assert_equal discuss(X**3 - 3 * X).to_s, worked.result.to_s
    text = worked.to_s
    ["1. the domain", "2. symmetry", "3. the zeros", "4. at infinity", "5. the derivatives",
     "6. the extrema", "7. the monotonicity", "8. the inflections", "9. the curvature"].each do |headline|
      assert_includes text, headline
    end
    assert_includes text, "f(-x) = 3*x - x**3"
    assert_includes text, "f''(-1) = -6 < 0: a maximum at (-1, 2)"
    assert_includes text, "f'''(0) = 6, not 0: an inflection at (0, 0)"
    assert_includes text, "f' < 0 on (-1, 1): decreasing"
  end

  def test_steps_name_the_gaps_and_the_asymptotes
    text = RCAS.steps((X**2 + 1) / X, :x, :discuss).to_s
    assert_includes text, "x != 0"
    assert_includes text, "x = 0: f -> -oo from the left, f -> oo from the right"
    assert_includes text, "the graph runs away there: a pole"
    assert_includes text, "f - (x) -> 0, so y = x is an oblique asymptote"
  end

  def test_steps_say_what_is_out_of_reach
    text = RCAS.steps(RCAS.exp(X) + X, :x, :discuss).to_s
    assert_includes text, "rcas cannot solve f(x) = 0"
  end

  def test_steps_take_the_block_form_too
    held = RCAS.hold { RCAS.discuss(X**2 - 1) }
    assert_equal "discuss(x**2 - 1)", held.to_s, "hold keeps a discussion as a call"
    assert_equal discuss(X**2 - 1).to_s, held.doit.to_s, "and doit answers it"
    worked = RCAS.steps { RCAS.discuss(2 * X**2 - 4 * X - 2) }
    assert_equal "discuss(2*x**2 - 4*x - 2, x)", worked.problem.to_s
    assert_equal discuss(2 * X**2 - 4 * X - 2).to_s, worked.result.to_s
    assert_includes worked.to_s, "f''(1) = 4 > 0: a minimum at (1, -4)"
    assert_equal "discuss(t**2 - 1, t)", RCAS.steps { RCAS.discuss(T**2 - 1, T) }.problem.to_s
  end

  def test_steps_infer_the_indeterminate
    assert_equal "discuss(t**2 - 1, t)", RCAS.steps(T**2 - 1, :discuss).problem.to_s
  end

  # "not determined" must mean the library said so, not that any error at
  # all was swallowed on the way.
  def test_undecided_is_a_named_list_of_errors
    assert_includes RCAS::Discussion::UNDECIDED, ArgumentError
    assert_includes RCAS::Discussion::UNDECIDED, RCAS::DomainError
    refute_includes RCAS::Discussion::UNDECIDED, StandardError
    refute_includes RCAS::Discussion::UNDECIDED, NoMethodError
  end

  # tan(x) hides a cos in its denominator, so it used to have no gaps, no
  # asymptotes and the whole real line as its domain.
  def test_a_tangent_has_gaps_and_asymptotes
    x = RCAS::Var.new(:x)
    report = RCAS.discuss(RCAS.tan(x), x)
    assert_nil report.domain, "the complement of a family is not a RealSet, and saying so is honest"
    assert_equal "pi", report.period.to_s
    assert_equal ["{pi/2 + pi*k | k in ZZ}"], report.asymptotes[:vertical].map(&:to_s)
    # one period, [0, pi), as every other row (the fourth review: the zeros
    # of a periodic f were those of one period of the inner argument)
    assert_equal ["pi/2"], report.gaps.map { |point, _kind, _l, _r| point.to_s }
    assert_equal %i[pole], report.gaps.map { |_point, kind, _l, _r| kind }
  end

  private

  def row(report, label) = report.to_s.lines.find { |l| l.start_with?("  #{label}") }.split.drop(1).join(" ")

  def sample(interval)
    low = interval.low_value
    high = interval.high_value
    return 0.0 if low.infinite? && high.infinite?
    return high - 1.0 if low.infinite?
    return low + 1.0 if high.infinite?
    (low + high) / 2
  end

end
