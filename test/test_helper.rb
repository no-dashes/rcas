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

  # A singleton method of +object+ replaced by +impl+ for the length of the
  # block, and put back after. Aliasing the original away and defining a
  # new one printed Ruby's "method redefined" warnings twice per stub; the
  # method is removed before either definition instead. A stub that wants
  # the original asks for object.method(name) before calling this - a
  # Method object keeps working after its method is removed.
  def replacing(object, name, impl)
    singleton = object.singleton_class
    original = singleton.instance_method(name)
    singleton.send(:remove_method, name)
    singleton.define_method(name, impl)
    yield
  ensure
    if original
      singleton.send(:remove_method, name) if singleton.instance_methods(false).include?(name) || singleton.private_instance_methods(false).include?(name)
      singleton.define_method(name, original)
    end
  end
end
