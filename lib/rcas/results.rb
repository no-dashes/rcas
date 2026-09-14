# frozen_string_literal: true

module RCAS
  # The results of a session, numbered: `_r[3]` is the third one, `_r[-1]`
  # the last, `_r` the whole table.
  #
  #   [1] 1 - x**2
  #   [2] 2*x
  #   rcas> _r[1] + _r[2]
  #   [3] 1 + 2*x - x**2
  #
  # irb's own `_` (the last value) keeps working. Recording is always on;
  # whether the prefix is `[3]` or `=>` is `RCAS.numbered`, off by default so
  # that the transcripts in the manual stay literal. `RCAS_NUMBERED=1` or
  # `/numbered on` in rcas-chat turns it on.
  module Results
    # A hash from the number to the value, where a negative number counts
    # back from the last result.
    class Store < Hash
      def [](key) = super(key.is_a?(Integer) && key.negative? ? keys.size + 1 + key : key)
      def to_s = empty? ? "(no results yet)" : map { |i, v| "[#{i}] #{v}" }.join("\n")
      def inspect = empty? ? "(no results yet)" : map { |i, v| "[#{i}] #{v.inspect}" }.join("\n")
      # irb prints with pp by default; keep the table one result per line.
      def pretty_print(q) = q.text(inspect)

      # Forgetting the results starts the numbering over.
      def clear
        super
        Results.restart
        self
      end
    end

    module_function

    def store = @store ||= Store.new
    def index = @index || 0
    def last = store[index]

    # Remember one result and return its number.
    def record(value)
      @bare = value.equal?(store) # the table prints itself, unprefixed
      return index if @bare
      @index = index + 1
      store[@index] = value
      @index
    end

    def clear = store.clear

    # Called by Store#clear: numbering starts at one again.
    def restart
      @index = 0
      @bare = false
    end

    def numbered? = @numbered.nil? ? ENV["RCAS_NUMBERED"] == "1" : @numbered

    def numbered=(value)
      @numbered = value.nil? ? nil : !(value == false || value.to_s == "off" || value.to_s == "false")
    end

    # What goes in front of a result; nil for the table printing itself.
    def prefix = numbered? ? "[#{index}]" : "=>"
    def mark = @bare ? nil : prefix

    def return_format(plain)
      return "%s\n" if @bare
      numbered? ? "[#{index}] %s\n" : plain
    end
  end

  class << self
    def numbered? = Results.numbered?
    def numbered=(value)
      Results.numbered = value
    end
    def results = Results.store
  end
end
