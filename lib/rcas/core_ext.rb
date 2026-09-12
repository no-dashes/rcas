# frozen_string_literal: true

# Symbols double as algebraic variables: `:x + 1` builds an expression.
class Symbol
  def +(other) = RCAS::Var.new(self) + other
  def -(other) = RCAS::Var.new(self) - other
  def *(other) = RCAS::Var.new(self) * other
  def /(other) = RCAS::Var.new(self) / other
  def **(other) = RCAS::Var.new(self)**other
  def -@ = -RCAS::Var.new(self)
  def +@ = RCAS::Var.new(self)

  # Lets Numeric operators accept a Symbol on the right: `1 - :x`.
  def coerce(other) = [RCAS::Expression.lift(other), RCAS::Var.new(self)]

  def to_expr = RCAS::Var.new(self)

  # `x.in(ZZ)` declares the variable's domain; `x.in?(ZZ)` and `x.domain` query it.
  def eq(other) = to_expr.eq(other)

  # :x < 2 builds an inequality; symbol-to-symbol comparison keeps Ruby's meaning.
  %i[< <= > >=].each do |op|
    original = instance_method(op)
    define_method(op) do |other|
      other.is_a?(Numeric) || other.is_a?(RCAS::Expression) ? RCAS::Inequality.new(to_expr, op, other) : original.bind_call(self, other)
    end
  end
  def in(domain) = to_expr.in(domain)
  def in?(domain) = to_expr.in?(domain)
  def domain = to_expr.domain
end

class Numeric
  def to_expr = RCAS::Num.new(self)
end
