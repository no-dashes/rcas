# frozen_string_literal: true

require_relative "openmath/objects"
require_relative "openmath/xml"
require_relative "openmath/phrasebook"
require_relative "openmath/popcorn"

module RCAS
  module OpenMath
    module_function

    # An OpenMath object from its XML encoding, or from an object already
    # parsed. Use #to_expression on the result for the rcas object.
    def parse(source)
      source.is_a?(Node) ? source : XML.decode(source)
    end

    # The rcas object a piece of OpenMath stands for, unevaluated: the
    # document says 1 + 2, and 1 + 2 is what comes back, not 3.
    def read(source) = parse(source).to_expression
  end

  class Expression
    # This expression as an OpenMath object; #to_xml writes the encoding.
    def to_openmath = OpenMath::Phrasebook.to_openmath(self)
  end

  class Equation
    def to_openmath = OpenMath::Phrasebook.to_openmath(self)
  end

  module Functions
    # openmath(x**2 + 1): the OpenMath object, whose to_xml is the XML
    # encoding. Equations, intervals, matrices and number sets travel too.
    def openmath(obj) = OpenMath::Phrasebook.to_openmath(obj)

    # from_openmath(xml): the rcas object an OpenMath document stands for,
    # held rather than evaluated - "1 + 2" comes back as 1 + 2.
    def from_openmath(source) = OpenMath.read(source)

    # popcorn(x**2 + 1): the OpenMath object in POPCORN, the notation meant
    # for people rather than machines - "$x^2 + 1".
    def popcorn(obj) = OpenMath::Phrasebook.to_openmath(obj).to_popcorn

    # from_popcorn("$x^2 + 1"): the rcas object that notation stands for,
    # held rather than evaluated.
    def from_popcorn(source) = OpenMath::Popcorn.parse(source).to_expression
  end
end
