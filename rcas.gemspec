# frozen_string_literal: true

require_relative "lib/rcas/version"

Gem::Specification.new do |spec|
  spec.name = "rcas"
  spec.version = RCAS::VERSION
  spec.authors = ["Peter Horn"]
  spec.summary = "A computer algebra system that lives inside Ruby"
  spec.description = <<~TEXT.tr("\n", " ").strip
    Symbols are indeterminates, the ordinary operators build expression
    trees, and irb is the REPL. Exact arithmetic first; calculus, solving,
    polynomial rings, finite fields, linear algebra, differential
    equations, summation and statistics, with honest unevaluated answers
    where there is no closed form.
  TEXT
  spec.homepage = "https://github.com/no-dashes/rcas"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"
  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "documentation_uri" => "#{spec.homepage}/blob/main/MANUAL.md",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*", "bin/*", "README.md", "MANUAL.md", "DESIGN.md", "LICENSE", "CITATION.cff", "package.json"]
  spec.bindir = "bin"
  spec.executables = %w[rcas rcas-chat rcas-app]
  spec.require_paths = ["lib"]

  # Everything else is the standard library. These two are bundled rather
  # than default gems from Ruby 3.4 on, so they are named here.
  spec.add_dependency "bigdecimal", ">= 3.1", "< 5"
  spec.add_dependency "irb", ">= 1.11", "< 2"
end
