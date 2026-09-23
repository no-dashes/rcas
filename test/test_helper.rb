# frozen_string_literal: true

require "minitest/autorun"
require "rcas"

# What the test files share about the Ruby they run under.
module TestSupport
  module_function

  # Ruby 3.4 changed Hash#inspect: {:a=>1, x=>2} became {a: 1, x => 2}.
  # Both sides of a comparison go through this, so the manual and the
  # tests hold under either Ruby and stay exact about everything else.
  def hash_style(text) = text.gsub(/:([[:word:]]+[?!]?)=>/) { "#{Regexp.last_match(1)}: " }.gsub(/\s*=>\s*/, " => ")

  # The chat's Claude integration needs the optional anthropic gem; the
  # tests that drive it through a scripted runner skip without it, since
  # the core promises to need nothing beyond the standard library.
  def anthropic? = Gem::Specification.find_all_by_name("anthropic").any?
end
