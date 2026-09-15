# frozen_string_literal: true

module RCAS
  # The session, numbered line by line the way Mathematica numbers it: the
  # third line of the session is `In[3]`, its result `Out[3]`.
  #
  #   rcas[1]> (x + 1)*(x - 1)
  #   => (x + 1)*(x - 1)
  #   rcas[2]> expand(Out[1])
  #   => -1 + x**2
  #   rcas[3]> In[1]
  #   => (x + 1)*(x - 1)
  #
  # Both tables hand back what was there, *held*: `Out[n]` is the value as it
  # was computed, never computed again, and `In[n]` is the input as it was
  # typed, built with `hold` into an expression instead of being run (so
  # `In[1]` above is the product, not the expansion). A negative number
  # counts back: `Out[-1]` is the previous result, `In[-1]` the previous
  # input. The line being typed is not in the tables yet.
  #
  # Recording is always on; `RCAS.numbered` only decides whether the prompt
  # carries the number of the line to come (`rcas[3]> `). It is on by
  # default; `RCAS.numbered = false`, `RCAS_NUMBERED=0` or `/numbered off`
  # in rcas-chat gives the plain prompt back (which is what the transcripts
  # in the manual show).
  module Results
    # A table from line number to input or result. Hash except that a
    # negative key counts back from the last finished line and that the line
    # being read is not there yet.
    class Store < Hash
      alias erase clear # Hash#clear, without restarting the numbering

      def initialize(kind)
        @kind = kind
        super()
      end

      def [](key)
        n = number(key)
        n.nil? ? nil : super(n)
      end

      # The numbers of the finished lines, oldest first.
      def numbers = keys - [Results.pending]

      # The number a key stands for, or nil for one that is not there. A
      # held line hands over its numbers as Num nodes (`In[2]` inside
      # `In[7]`), so those count too.
      def number(key)
        key = key.value if key.is_a?(Num) && key.value.is_a?(Integer)
        return numbers[key] if key.is_a?(Integer) && key.negative?
        key == Results.pending ? nil : key
      end

      def to_s = text { |value| value.to_s }
      def inspect = text { |value| value.inspect }
      # irb prints with pp by default; keep the table one line per line.
      def pretty_print(q) = q.text(inspect)

      # Forgetting one table forgets the whole session and starts the
      # numbering over.
      def clear
        Results.clear
        self
      end

      private

      def text
        return "(no #{@kind} yet)" if numbers.empty?
        numbers.map { |i| "[#{i}] #{yield fetch(i)}" }.join("\n")
      end
    end

    # `In`: the inputs. The table prints the lines as they were typed;
    # `In[3]` builds the expression of the third line with `hold`.
    class Inputs < Store
      def initialize = super("inputs")
      def [](key) = (n = number(key)) && Results.held(n)
      def inspect = to_s # the lines as typed, not as Ruby strings
    end

    module_function

    def inputs = @inputs ||= Inputs.new
    def outputs = @outputs ||= Store.new("results")
    # The number of the line being read, or 0 before the first one.
    def index = @index || 0
    # The number the next input will get: what the prompt shows.
    def line = index + 1
    # The line that has been read but has no result yet, if any.
    def pending = @pending
    def last = outputs[-1]

    # Remember the source of one input line and give it the next number.
    # +context+ is the binding it was evaluated in, for In[n].
    def record_input(source, context = nil)
      @index = index + 1
      @pending = @index
      inputs[@index] = source.to_s.rstrip
      bindings[@index] = context if context
      @index
    end

    # Remember the result of the line being read and return its number. A
    # host that records results only (test/manual_test.rb) numbers them here.
    def record(value)
      @bare = value.equal?(outputs) || value.equal?(inputs) # a table prints itself, unprefixed
      @index = index + 1 if @pending.nil? && !@bare
      @pending = nil
      return index if @bare
      outputs[@index] = value
      @index
    end

    # The input of line +n+ held: the expression the line builds, not its
    # value. A line `hold` cannot keep (an assignment, a command, a string)
    # comes back as the text that was typed, and so does a line that reads
    # itself.
    def held(n)
      source = inputs.fetch(n, nil)
      return nil if source.nil?
      return source if holding.include?(n)
      holding << n
      begin
        Hold.source(source, bindings[n]) || source
      rescue StandardError, ScriptError
        source
      ensure
        holding.delete(n)
      end
    end

    def bindings = @bindings ||= {}
    def holding = @holding ||= []

    # Forget the session: both tables and the numbering.
    def clear
      inputs.erase
      outputs.erase
      bindings.clear
      restart
      self
    end

    # Numbering starts at one again.
    def restart
      @index = 0
      @pending = nil
      @bare = false
    end

    # On unless the environment or the session says otherwise.
    def numbered? = @numbered.nil? ? ENV["RCAS_NUMBERED"] != "0" : @numbered

    def numbered=(value)
      @numbered = value.nil? ? nil : !(value == false || value.to_s == "off" || value.to_s == "false")
    end

    # The prompt with the number of the input to come: "rcas> " becomes
    # "rcas[3]> ", "> " becomes "[3]> ".
    def prompt(plain)
      return plain if plain.nil? || !numbered? # no prompt without a terminal
      plain.sub(/([^\w\s]*\s*)\z/) { "[#{line}]#{::Regexp.last_match(1)}" }
    end

    # What goes in front of a result; nil for a table printing itself.
    def mark = @bare ? nil : "=>"

    def return_format(plain) = @bare ? "%s\n" : plain
  end

  # In[3] is the third input of the session, held: the expression that line
  # builds, not its value. `In` on its own prints the whole table.
  In = Results.inputs
  # Out[3] is the result of the session's third line, Out[-1] the previous
  # result. `Out` on its own prints the whole table.
  Out = Results.outputs

  # `include RCAS::Constants` brings them into scope with PI, E and I.
  Constants.const_set(:In, In)
  Constants.const_set(:Out, Out)

  class << self
    def numbered? = Results.numbered?
    def numbered=(value)
      Results.numbered = value
    end
    def inputs = Results.inputs
    def outputs = Results.outputs
  end
end
