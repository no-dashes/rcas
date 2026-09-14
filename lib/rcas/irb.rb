# frozen_string_literal: true

require "irb"

module RCAS
  # irb integration. `RCAS::IRB.setup` prepares the session in which it is
  # called (normally the top-level `main` object in bin/rcas):
  #
  # * bare, not-yet-defined identifiers become symbols and are assigned as
  #   local variables, so `x + 1` works like `:x + 1` and `x` is `:x` afterwards
  # * sin/cos/tan/exp/log/sqrt are available as plain functions
  # * a friendlier prompt
  module IRB
    IDENTIFIER = RCAS::IDENTIFIER

    module AutoSymbol
      def method_missing(name, *args, &block)
        return super unless block.nil? && name.match?(IDENTIFIER)
        return RCAS.unknown_function(name, args) || super unless args.empty?

        binding_for_session&.local_variable_set(name, name)
        name
      end

      # Deliberately false: Ruby's implicit conversions (to_ary, to_str, ...)
      # probe respond_to? first and must not be satisfied by a Symbol.
      def respond_to_missing?(_name, _include_private = false) = false

      private

      def binding_for_session
        ::IRB.CurrentContext&.workspace&.binding
      rescue StandardError
        nil
      end
    end

    def self.setup(main = TOPLEVEL_BINDING.receiver)
      RubyVM.keep_script_lines = true # lets hold { ... } read blocks typed into irb
      main.singleton_class.include(Functions)
      main.singleton_class.prepend(AutoSymbol)
      RCAS.undefine_kernel_printers(main)
      Object.include(Sets) unless Object.include?(Sets)
      Object.include(Constants) unless Object.include?(Constants)
      main
    end

    # irb resets its configuration inside IRB.setup, so ours is applied after.
    def self.configure(conf = ::IRB.conf)
      conf[:PROMPT][:RCAS] = {
        PROMPT_I: "rcas> ",
        PROMPT_S: "rcas%l ",
        PROMPT_C: "rcas* ",
        RETURN: "=> %s\n"
      }
      conf[:PROMPT_MODE] = :RCAS if STDIN.tty?
      conf[:ECHO_ON_ASSIGNMENT] = true # show whole matrices, not "[1 2]..."
      conf
    end

    def self.start(main = TOPLEVEL_BINDING.receiver)
      setup(main)
      ::IRB.setup(__FILE__)
      configure
      irb = ::IRB::Irb.new
      ::IRB.conf[:MAIN_CONTEXT] = irb.context
      irb.run(::IRB.conf)
    end
  end
end
