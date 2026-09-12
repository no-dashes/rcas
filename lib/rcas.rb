# frozen_string_literal: true

# RCAS - a tiny symbolic algebra system that lives inside plain Ruby.
#
#   require "rcas"
#   e = (:x + 1) * (1 - :x)   # => (x + 1)*(1 - x)
#   e.expand                  # => 1 - x**2
#   e.diff(:x)                # => -2*x
#   e.call(x: 3)              # => -8
module RCAS
  VERSION = "0.1.0"
end

require_relative "rcas/expression"
require_relative "rcas/printer"
require_relative "rcas/simplify"
require_relative "rcas/expand"
require_relative "rcas/differentiate"
require_relative "rcas/functions"
require_relative "rcas/domains"
require_relative "rcas/scalar"
require_relative "rcas/polynomial"
require_relative "rcas/gcd"
require_relative "rcas/factor"
require_relative "rcas/integrate"
require_relative "rcas/constants"
require_relative "rcas/fraction"
require_relative "rcas/solve"
require_relative "rcas/ode"
require_relative "rcas/series"
require_relative "rcas/summation"
require_relative "rcas/combinatorics"
require_relative "rcas/inequalities"
require_relative "rcas/trig"
require_relative "rcas/algebraic"
require_relative "rcas/finite_field"
require_relative "rcas/hold"
require_relative "rcas/vector"
require_relative "rcas/matrix"
require_relative "rcas/core_ext"
require_relative "rcas/latex"
require_relative "rcas/render"
