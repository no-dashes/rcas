# frozen_string_literal: true

module RCAS
  # What one name does, read from the source itself.
  #
  #   doc(:factor)      # the top-level function, its comment and where the manual covers it
  #   doc(:simplify)    # a function that is also a method on expressions
  #   doc("ZZ")         # a value: the integers
  #   doc(:Matrix)      # a class, with its public methods
  #
  # rcas documents every public function with a comment above its `def`
  # (see CLAUDE.md), so the help is the source and cannot drift from it.
  # `bin/rcas-chat` shows the same text as `/help NAME`.
  Documentation = Struct.new(:name, :kind, :signature, :lines, :also, :sections, :background, :sources, :reading) do
    WIDTH = 74

    def to_s
      out = [signature]
      out.concat(lines.map { |l| "  #{l}" })
      out << "  also: #{also}" if also
      background&.each { |label, text| out.concat(Documentation.wrap("  #{label}: ", text)) }
      sources&.each_with_index { |source, i| out.concat(Documentation.wrap(i.zero? ? "  sources: " : "           ", source)) }
      reading&.each_with_index { |link, i| out << "#{i.zero? ? '  read: ' : '        '}#{link}" }
      out << "  manual: #{sections.join('; ')}" unless sections.nil? || sections.empty?
      out.join("\n")
    end

    # +label+ on the first line, the rest indented under it.
    def self.wrap(label, text)
      indent = " " * label.size
      lines = [label.rstrip.empty? ? label.dup : label.rstrip] # a blank label is an indent
      text.split(/\s+/).each do |word|
        lines << indent.dup if lines.last.size + word.size + 1 > WIDTH
        lines[-1] = "#{lines.last}#{lines.last.end_with?(' ') ? '' : ' '}#{word}"
      end
      lines
    end

    def inspect = to_s
    def pretty_print(printer) = printer.text(to_s)
  end

  module Docs
    MANUAL = File.expand_path("../../MANUAL.md", __dir__)
    MAX_METHODS = 16
    MAX_SECTIONS = 3

    class NotFound < StandardError; end

    module_function

    # => Documentation; raises NotFound with near misses.
    def doc(name)
      key = name.is_a?(Symbol) || name.is_a?(String) ? name.to_s : name.to_s
      key = key.sub(/\A[A-Z]+::/, "").delete_prefix("RCAS::")
      found = function(key) || namespaced(key) || expression_method(key) || structure_method(key) || constant(key)
      raise NotFound, "nothing known about #{key}#{suggestion(key)}" if found.nil?
      found
    end

    # Near misses, compared on the part after the namespace, so that
    # `chebyshev` finds Poly.chebyshev_t.
    def suggestion(key)
      target = bare(key)
      near = names.select { |n| bare(n).start_with?(target[0, 2].to_s) || levenshtein(bare(n), target) <= 2 }
                  .sort_by { |n| levenshtein(bare(n), target) }
      near.empty? ? "" : "; did you mean #{near.first(4).join(', ')}?"
    end

    def bare(name) = name.split(".").last.to_s

    # Modules with functions of their own, addressed through their name:
    # `Poly.legendre` is the polynomial, the bare `legendre` the symbol.
    NAMESPACES = %w[Poly].freeze

    # The structures and how one is written down, for a method that belongs
    # to a ring or a space rather than to an expression: ZZ[x].random.
    STRUCTURES = { "PolynomialRing" => "ZZ[x]", "FractionField" => "Frac(ZZ[x])", "MatrixSpace" => "(ZZ**[2, 2])",
                   "VectorSpace" => "(ZZ**3)", "NumberSet" => "ZZ", "FiniteField" => "GF(9)",
                   "AlgebraicField" => "QQ.adjoin(sqrt(2))" }.freeze

    # Every name doc knows about.
    def names
      functions = Functions.instance_methods(false).map(&:to_s)
      methods = Expression.public_instance_methods(false).map(&:to_s)
      constants = RCAS.constants.map(&:to_s)
      (functions + methods + constants + namespaced_names + structure_names).uniq.sort
    end

    def structure_names
      STRUCTURES.keys.flat_map { |name| structure_methods(name).map(&:to_s) }
    end

    def structure_methods(name)
      RCAS.const_get(name).public_instance_methods(false) - Object.instance_methods
    end

    def namespaced_names
      NAMESPACES.flat_map do |prefix|
        RCAS.const_get(prefix).public_instance_methods(false).map { |name| "#{prefix}.#{name}" }
      end
    end

    def levenshtein(a, b)
      rows = Array.new(a.size + 1) { |i| [i] + Array.new(b.size, 0) }
      (0..b.size).each { |j| rows[0][j] = j }
      (1..a.size).each do |i|
        (1..b.size).each do |j|
          cost = a[i - 1] == b[j - 1] ? 0 : 1
          rows[i][j] = [rows[i - 1][j] + 1, rows[i][j - 1] + 1, rows[i - 1][j - 1] + cost].min
        end
      end
      rows[a.size][b.size]
    end

    # ---- the three kinds -------------------------------------------------------

    def function(key)
      name = key.to_sym
      return nil unless Functions.method_defined?(name) || Functions.private_method_defined?(name)
      info = from_source(Functions.instance_method(name), name)
      also = []
      also << "e.#{name}" if Expression.method_defined?(name) && !%i[in in?].include?(name)
      also << "f.#{name} on polynomials" if Polynomial.method_defined?(name) && !Expression.method_defined?(name)
      Documentation.new(key, :function, info[:signature], info[:lines], also.empty? ? nil : also.join(", "), sections(key), Background[key], sources_for(key), Background.reading(key))
    end

    # Poly.legendre, or the bare chebyshev_t when no top-level function has
    # that name. The documentation is keyed by the qualified name, so that
    # Poly.legendre and the Legendre symbol can have a background each.
    def namespaced(key)
      prefix, name = key.sub("::", ".").split(".", 2)
      prefix, name = [nil, prefix] if name.nil?
      prefixes = prefix ? NAMESPACES & [prefix] : NAMESPACES
      found = prefixes.find { |p| RCAS.const_get(p).public_method_defined?(name.to_sym) }
      return nil if found.nil?
      qualified = "#{found}.#{name}"
      info = from_source(RCAS.const_get(found).instance_method(name.to_sym), name.to_sym)
      Documentation.new(qualified, :function, "#{found}.#{info[:signature]}", info[:lines], nil,
                        sections(qualified), Background[qualified], sources_for(qualified), Background.reading(qualified))
    end

    def expression_method(key)
      name = key.to_sym
      return nil unless Expression.method_defined?(name)
      info = from_source(Expression.instance_method(name), name)
      Documentation.new(key, :method, "e.#{info[:signature]}", info[:lines], "a method on expressions", sections(key), Background[key], sources_for(key), Background.reading(key))
    end

    # A method of a ring, a field or a space, shown the way one is written:
    # ZZ[x].random. The other structures that answer it are named beside it.
    def structure_method(key)
      name = key.to_sym
      homes = STRUCTURES.keys.select { |c| structure_methods(c).include?(name) }
      return nil if homes.empty?
      info = from_source(RCAS.const_get(homes.first).instance_method(name), name)
      also = homes.drop(1).map { |c| "#{STRUCTURES[c]}.#{name}" }
      Documentation.new(key, :method, "#{STRUCTURES[homes.first]}.#{info[:signature]}", info[:lines],
                        also.empty? ? nil : also.join(", "), sections(key), Background[key], sources_for(key), Background.reading(key))
    end

    def constant(key)
      return nil unless key.match?(/\A[[:upper:]][[:alnum:]_]*\z/) && RCAS.const_defined?(key)
      value = RCAS.const_get(key)
      location = Object.const_source_location("RCAS::#{key}")
      lines = location && location.first ? comment_above(location.first, location.last) : []
      if value.is_a?(Module)
        methods = (value.public_instance_methods(false) - Object.instance_methods).map(&:to_s).grep(/\A[a-z]/).sort
        lines = [""] + lines unless lines.empty?
        lines = lines.reject(&:empty?)
        lines << "methods: #{methods.first(MAX_METHODS).join(', ')}#{methods.size > MAX_METHODS ? ', ...' : ''}" unless methods.empty?
        Documentation.new(key, :class, "#{value} (#{value.is_a?(Class) ? 'class' : 'module'})", lines, nil, sections(key), Background[key], sources_for(key), Background.reading(key))
      else
        if lines.empty? # a bare constant: say what its class is for
          where = Object.const_source_location(value.class.name.to_s)
          lines = where && where.first ? comment_above(where.first, where.last).first(2) : []
        end
        lines = ["#{value} (#{value.class.name.to_s.sub('RCAS::', '')})"] + lines
        Documentation.new(key, :value, key, lines, nil, sections(key), Background[key], sources_for(key), Background.reading(key))
      end
    end

    # ---- reading the source ----------------------------------------------------

    # The `def` line and the comment block above it. Several defs may share
    # one comment (degree, ldegree, lcoeff), so walk up past them.
    def from_source(method, name)
      file, line = method.source_location
      return { signature: "#{name}(...)", lines: [] } if file.nil?
      lines = File.readlines(file)
      i = line - 1
      i -= 1 while i.positive? && !lines[i].match?(/^\s*def\s/)
      match = i.positive? ? lines[i].match(/def\s+(?:self\.)?(?<name>[A-Za-z_]\w*[?!=]?)\s*(?:\((?<params>.*?)\))?/) : nil
      if match && match[:name] == name.to_s
        signature = match[:params].to_s.strip.empty? ? name.to_s : "#{name}(#{match[:params].strip})"
        { signature: signature, lines: comment_above(file, i + 1, lines) }
      else # define_method (sin, cos, ...) or an alias
        { signature: parameter_signature(method, name), lines: nearest_comment(lines, line - 1) }
      end
    rescue SystemCallError, IOError
      { signature: parameter_signature(method, name), lines: [] }
    end

    # The comment block ending just above +line+, skipping other def lines.
    def comment_above(file, line, lines = nil)
      lines ||= File.readlines(file)
      j = line - 2
      j -= 1 while j >= 0 && lines[j].match?(/^\s*(def\s|alias\s|\z)/) && !lines[j].match?(/^\s*#/)
      out = []
      while j >= 0 && lines[j].match?(/^\s*#/)
        out.unshift(lines[j].sub(/^\s*#\s?/, "").rstrip)
        j -= 1
      end
      out.shift while out.first&.empty?
      out.pop while out.last&.empty?
      out
    rescue SystemCallError, IOError
      []
    end

    # The comment block closest above +from+, at most eight lines up.
    def nearest_comment(lines, from)
      j = from
      j -= 1 while j.positive? && !lines[j].match?(/^\s*#/) && from - j < 8
      return [] unless lines[j].to_s.match?(/^\s*#/)
      out = []
      while j >= 0 && lines[j].match?(/^\s*#/)
        out.unshift(lines[j].sub(/^\s*#\s?/, "").rstrip)
        j -= 1
      end
      out
    end

    def parameter_signature(method, name)
      parts = method.parameters.map do |kind, parameter|
        case kind
        when :req then parameter.to_s
        when :opt then "#{parameter} = ..."
        when :rest then "*#{parameter}"
        when :keyreq then "#{parameter}:"
        when :key then "#{parameter}: ..."
        when :keyrest then "**#{parameter}"
        when :block then "&#{parameter}"
        end
      end.compact
      parts.empty? ? name.to_s : "#{name}(#{parts.join(', ')})"
    end

    # ---- sources ----------------------------------------------------------------

    # "[Knu98] D. E. Knuth, The Art of Computer Programming, ..." for every
    # source the background of this name cites, in the order they appear.
    def sources_for(key)
      entry = Background[key] or return []
      cited = entry.values.join(" ").scan(/\[([A-Za-z]+\d+[a-z]?)(?:,[^\]]*)?\]/).flatten.uniq
      cited.filter_map { |k| bibliography[k] && "[#{k}] #{bibliography[k]}" }
    end

    # { "Knu98" => "D. E. Knuth, ..." } from section 4 of the manual, so the
    # citation lives in one place only.
    def bibliography
      return @bibliography if defined?(@bibliography)
      @bibliography = {}
      return @bibliography unless File.file?(MANUAL)
      current = nil
      File.foreach(MANUAL) do |line|
        if (m = line.match(/\A- \[([A-Za-z]+\d+[a-z]?)\]\s+(.*)$/))
          current = m[1]
          @bibliography[current] = m[2].strip
        elsif current && line.match?(/\A  \S/)
          @bibliography[current] = "#{@bibliography[current]} #{line.strip}"
        else
          current = nil
        end
      end
      @bibliography = @bibliography.transform_values { |v| v.delete("*").sub(/\.\z/, "") }
    rescue SystemCallError, IOError
      @bibliography = {}
    end

    # ---- the manual ------------------------------------------------------------

    # Headings of the manual sections that mention this name.
    def sections(key)
      return [] unless File.file?(MANUAL)
      pattern = /(?<![A-Za-z_])#{Regexp.escape(key)}(?![A-Za-z_])/
      found = count_mentions(pattern)
      found = count_mentions(/(?<![A-Za-z_])#{Regexp.escape(key)}(?![A-Za-z_])/i) if found.empty? && key.match?(/\A[[:upper:]]/)
      found.first(MAX_SECTIONS)
    rescue SystemCallError, IOError
      []
    end

    # Headings ordered by how often they mention the name (the loose pattern
    # catches classes, which the prose writes in lower case).
    # The appendices and the tables of part 2 to 5 are not sections to read:
    # they are tracked by their own heading level, so their subsections go too.
    SKIP = /\A[0-9]+\. (Reference|Files|Sources|License)|\AAppendix/

    def count_mentions(pattern)
      part = nil
      heading = nil
      counts = Hash.new(0)
      File.foreach(MANUAL) do |line|
        if line.start_with?("## ")
          part = line.sub(/\A#+\s*/, "").strip
          heading = part
          next
        elsif line.start_with?("###")
          heading = line.sub(/\A#+\s*/, "").strip
          next
        end
        next unless heading && line.match?(pattern)
        next if part.to_s.match?(SKIP) || heading.match?(SKIP)
        counts[heading] += line.scan(pattern).size
      end
      counts.sort_by { |_, n| -n }.map(&:first)
    end
  end
end
