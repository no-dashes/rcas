# frozen_string_literal: true

require_relative "test_helper"

# Runs every `rcas>` transcript in MANUAL.md through a session that mimics
# bin/rcas (bare names become symbols) and checks the printed results.
class ManualTest < Minitest::Test
  MANUAL = File.expand_path("../MANUAL.md", __dir__)

  class Workspace
    include RCAS::Functions
    include RCAS::Sets
    include RCAS::Constants

    def method_missing(name, *args, &block)
      return super unless args.empty? && block.nil? && name.match?(/\A[a-z_][a-z0-9_]*\z/)
      name
    end

    def respond_to_missing?(*) = false
    def session_binding = binding
  end

  def transcripts
    blocks = []
    File.read(MANUAL).scan(/^```\n(.*?)^```/m) do |(body)|
      next unless body.include?("rcas> ")
      lines = body.lines.map(&:chomp)
      i = 0
      while i < lines.size
        if lines[i].start_with?("rcas> ")
          input = lines[i].delete_prefix("rcas> ")
          expected = []
          i += 1
          while i < lines.size && !lines[i].start_with?("rcas> ")
            expected << lines[i].sub(/\A=> /, "").sub(/\A   /, "")
            i += 1
          end
          blocks << [input, expected.join("\n")]
        else
          i += 1
        end
      end
    end
    blocks
  end

  def test_manual_examples
    RCAS.forget
    b = Workspace.new.session_binding
    failures = []
    transcripts.each do |input, expected|
      actual = begin
        b.eval(input).inspect
      rescue Exception => e # rubocop:disable Lint/RescueException
        "#{e.class}: #{e.message}"
      end
      next if actual == expected || expected.empty?
      failures << "rcas> #{input}\n  expected: #{expected}\n  actual:   #{actual}"
    end
    RCAS.forget
    assert failures.empty?, "#{failures.size} manual examples differ:\n#{failures.join("\n")}"
  end
end
