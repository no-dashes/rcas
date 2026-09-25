# frozen_string_literal: true

module RCAS
  # Warnings about input that Ruby evaluates before rcas sees it. The one
  # that matters is integer division: `x + 1/3` is `x + 0`, because Ruby
  # folds `1/3` to 0 first, and `2**(1/2)` is `2**0`. Nothing downstream
  # can tell, so the front ends read the line's syntax tree before running
  # it and say so at the moment it happens.
  #
  #   Lint.warnings("x + 1/3")  # => ["1/3 is Ruby's integer division and gives 0; write 1/3r for the fraction"]
  #
  # A division that comes out whole (`6/3`) is left alone, and so is the
  # inside of `hold { }` and `steps { }`, which keep the division as typed.
  # `RCAS.lint = false` (or `RCAS_LINT=0`) turns the warnings off.
  module Lint
    KEEPS_INPUT = %i[hold steps].freeze

    module_function

    def enabled? = @enabled.nil? ? ENV["RCAS_LINT"] != "0" : @enabled

    def enabled=(value)
      @enabled = value.nil? ? nil : !!value
    end

    # The messages for one line of input, [] when there is nothing to say
    # (or the line does not parse: Ruby reports that itself).
    def warnings(source)
      return [] unless enabled?
      tree = Hold.parse(source)
      found = []
      walk(tree, false, found)
      found.uniq
    rescue SyntaxError, ArgumentError
      []
    end

    # +exponent+: the node is (a parenthesized part of) the right operand
    # of `**`, as the 1/2 in `2**(1/2)` is.
    def walk(node, exponent, found)
      return unless node.is_a?(RubyVM::AbstractSyntaxTree::Node)
      return if node.type == :ITER && KEEPS_INPUT.include?(called(node.children[0]))
      message = integer_division(node, exponent) and found << message
      power = node.type == :OPCALL && node.children[1] == :**
      node.children.each_with_index do |child, i|
        walk(child, power ? i == 2 : exponent && %i[LIST BLOCK].include?(node.type), found)
      end
    end

    def integer_division(node, exponent)
      return nil unless node.type == :OPCALL && node.children[1] == :/
      a = integer(node.children[0])
      b = integer(node.children[2]&.children&.first)
      return nil if a.nil? || b.nil? || b.zero? || (a % b).zero?
      text = "#{a}/#{b} is Ruby's integer division and gives #{a / b}"
      text += ", so the exponent is #{a / b}" if exponent
      "#{text}; write #{a}/#{b}r for the fraction"
    end

    # Ruby 3.3 writes an integer literal as LIT, 3.4 and later as INTEGER.
    def integer(node)
      return nil unless node.is_a?(RubyVM::AbstractSyntaxTree::Node)
      return nil unless %i[LIT INTEGER].include?(node.type)
      value = node.children[0]
      value if value.is_a?(Integer)
    end

    def called(call)
      return nil unless call.is_a?(RubyVM::AbstractSyntaxTree::Node)
      call.children.find { |c| c.is_a?(Symbol) }
    end
  end

  def self.lint? = Lint.enabled?

  def self.lint=(value)
    Lint.enabled = value
  end
end
