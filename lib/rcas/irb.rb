# frozen_string_literal: true

require "irb"
require_relative "chat/usage"

module RCAS
  # bin/rcas prints rcas's refusals as one line (RCAS::IRB::BRIEF); true
  # gives every error irb's full backtrace again.
  def self.backtrace? = @backtrace.nil? ? ENV["RCAS_BACKTRACE"] == "1" : @backtrace

  def self.backtrace=(value)
    @backtrace = value.nil? ? nil : !!value
  end

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
      rescue StandardError # user code: a NameError is an answer here
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

    # Every echoed result is remembered in RCAS::Results, so that `Out[3]`
    # can reach it later; irb formats and pages the value itself.
    module RecordResult
      def output_value(*args)
        RCAS::Results.record(@context.last_value)
        super
      end
    end

    # And every input line, so that `In[3]` can give it back held. irb's own
    # commands and empty input are not lines of the session and get no
    # number.
    module RecordInput
      def evaluate(statement, *args, **options)
        if statement.is_a?(::IRB::Statement::Expression)
          RCAS::Results.record_input(statement.code, workspace.binding)
          RCAS::Lint.warnings(statement.code).each { |message| warn "warning: #{message}" }
        end
        super
      end
    end

    # rcas's refusals and the errors of a call gone wrong are answers, and
    # for them irb's backtrace through its own internals is noise: they
    # print as one line, with the usage of the function when the arguments
    # were wrong. Everything else - a NoMethodError, a TypeError - is a bug
    # somewhere and keeps the whole backtrace. `RCAS.backtrace = true` (or
    # RCAS_BACKTRACE=1) shows it for every error.
    BRIEF = [
      RCAS::Unsupported, NotImplementedError, ArgumentError, RCAS::SeriesError,
      RCAS::Plot::Error, RCAS::Render::Error, RCAS::Docs::NotFound,
      RCAS::OpenMath::ParseError, RCAS::OpenMath::EncodeError
    ].freeze

    def self.brief?(exception) = !RCAS.backtrace? && BRIEF.any? { |kind| exception.is_a?(kind) }

    # The lines printed for a brief error.
    def self.brief(exception)
      first, *rest = exception.message.lines.map(&:rstrip)
      lines = ["#{exception.class}: #{first}", *rest]
      hint = RCAS::Chat::Usage.hint(exception, user_frame: "(irb)")
      lines.concat(hint.map { |line| "  #{line}" }) if hint
      lines
    end

    module BriefErrors
      def handle_exception(exc)
        return super unless RCAS::IRB.brief?(exc)
        puts RCAS::IRB.brief(exc)
      end
    end

    # With RCAS.numbered the prompt carries the number of the line to come
    # (`rcas[3]> `); the results keep irb's `=>`. The internals we lean on
    # here (Statement::Expression, Context#evaluate, Irb#handle_exception,
    # prompt_i, return_format) are those of the irb bundled with Ruby 3.3.
    def self.record_session(irb)
      ::IRB::Irb.prepend(RecordResult) unless ::IRB::Irb.include?(RecordResult)
      ::IRB::Context.prepend(RecordInput) unless ::IRB::Context.include?(RecordInput)
      ::IRB::Irb.prepend(BriefErrors) unless ::IRB::Irb.include?(BriefErrors)
      plain = irb.context.return_format
      irb.context.define_singleton_method(:return_format) { RCAS::Results.return_format(plain) }
      prompt = irb.context.prompt_i
      irb.context.define_singleton_method(:prompt_i) { RCAS::Results.prompt(prompt) }
    end

    def self.start(main = TOPLEVEL_BINDING.receiver)
      setup(main)
      ::IRB.setup(__FILE__)
      configure
      irb = ::IRB::Irb.new
      ::IRB.conf[:MAIN_CONTEXT] = irb.context
      record_session(irb)
      irb.run(::IRB.conf)
    end
  end
end
