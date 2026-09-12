# frozen_string_literal: true

require "stringio"

module RCAS
  module Chat
    # The object and binding that user code and tool code run in. Bare
    # identifiers that are not yet defined become symbols (and locals), as
    # in bin/rcas; Functions (sin, sqrt, assume, matrix, show, ...) and the
    # number sets are in scope.
    class Workspace
      IDENTIFIER = /\A[a-z_][a-z0-9_]*\z/

      module AutoSymbol
        def method_missing(name, *args, &block)
          return super unless args.empty? && block.nil? && name.match?(IDENTIFIER)
          __rcas_workspace__.binding.local_variable_set(name, name)
          name
        end

        # Deliberately false so Ruby's implicit conversions are unaffected.
        def respond_to_missing?(_name, _include_private = false) = false
      end

      attr_reader :binding, :main

      def initialize
        Object.include(Sets) unless Object.include?(Sets)
        @main = Object.new
        workspace = self
        @main.singleton_class.include(Functions)
        @main.singleton_class.prepend(AutoSymbol)
        @main.define_singleton_method(:__rcas_workspace__) { workspace }
        @main.define_singleton_method(:to_s) { "rcas" }
        @main.define_singleton_method(:inspect) { "rcas" }
        # A method body has a fresh local scope, so the binding starts empty.
        @main.singleton_class.class_eval("def __rcas_binding__ = binding")
        @binding = @main.__rcas_binding__
      end

      # Evaluate +code+; returns [value, captured_stdout]. With capture:
      # false output goes straight to $stdout and the second value is "".
      def eval(code, capture: false)
        output = +""
        value =
          if capture
            previous = $stdout
            $stdout = StringIO.new(output)
            begin
              @binding.eval(code, "(rcas)", 1)
            ensure
              $stdout = previous
            end
          else
            @binding.eval(code, "(rcas)", 1)
          end
        @binding.local_variable_set(:_, value)
        [value, output]
      end

      # Run code for its side effects only (used when restoring a session).
      def replay(code)
        eval(code, capture: true)
      rescue StandardError, ScriptError, SystemStackError
        nil
      end

      def locals
        @binding.local_variables.reject { |v| v == :_ }.to_h { |v| [v, @binding.local_variable_get(v)] }
      end

      def [](name) = @binding.local_variable_get(name)

      # Does +code+ parse as Ruby?
      def ruby?(code)
        RubyVM::AbstractSyntaxTree.parse(code)
        true
      rescue SyntaxError
        false
      end

      # Is +code+ Ruby that merely stops early (open block, string, paren)?
      def incomplete?(code)
        RubyVM::AbstractSyntaxTree.parse(code)
        false
      rescue SyntaxError => e
        e.message.match?(/unexpected end-of-input|unexpected end of input|unexpected end-of-file|unterminated .* meets end of file|embedded document meets end of file/i)
      end

      # Tab-completion candidates.
      def complete(prefix)
        names = locals.keys.map(&:to_s) + Functions.instance_methods(false).map(&:to_s) + Sets::ALL.map(&:to_s)
        names += %w[simplify expand factor diff integrate subs call evalf to_latex show to_poly variables domain]
        names.uniq.select { |n| n.start_with?(prefix) }.sort
      end
    end
  end
end
