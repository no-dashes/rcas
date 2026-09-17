# frozen_string_literal: true

require "strscan"

module RCAS
  module OpenMath
    # The XML encoding of OpenMath objects [OM19, ch. 4]: one of the
    # encodings, not the objects themselves.
    #
    #   RCAS::OpenMath::XML.encode(om)          # => "<OMOBJ ...>"
    #   RCAS::OpenMath::XML.decode(string)      # => an OpenMath::Root
    #
    # The reader is written out here rather than taken from REXML, which is
    # a bundled gem rather than the standard library; the encoding is a
    # small, attribute-light subset of XML and needs no more than this.
    # Namespace prefixes are accepted and ignored (every element of the
    # encoding is in the OpenMath namespace).
    module XML
      NAMESPACE = "http://www.openmath.org/OpenMath"

      ESCAPES  = { "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", '"' => "&quot;", "'" => "&apos;" }.freeze
      ENTITIES = { "amp" => "&", "lt" => "<", "gt" => ">", "quot" => '"', "apos" => "'" }.freeze

      Element = Struct.new(:name, :attrs, :children, :text)

      module_function

      # +indent+: a number of spaces per level, or nil for a single line.
      # +namespace+: write the xmlns attribute on the outermost element.
      def encode(node, indent: nil, namespace: true, declaration: false)
        node = Root.new(node) unless node.is_a?(Root)
        out = +""
        out << %(<?xml version="1.0" encoding="UTF-8"?>\n) if declaration
        write(node, out, 0, indent, namespace)
        out
      end

      def write(node, out, depth, indent, namespace)
        pad = indent ? " " * (depth * indent) : ""
        nl  = indent ? "\n" : ""
        tag, attrs, text, children = parts(node)
        attrs = { "xmlns" => NAMESPACE }.merge(attrs) if namespace && depth.zero?
        attrs = attrs.merge("id" => node.id) if node.id
        open = "#{pad}<#{tag}#{attributes(attrs)}"

        if text.nil? && children.empty?
          out << open << "/>" << nl
        elsif children.empty?
          out << open << ">" << escape(text) << "</#{tag}>" << nl
        else
          out << open << ">" << nl
          children.each { |c| write(c, out, depth + 1, indent, false) }
          out << pad << "</#{tag}>" << nl
        end
        out
      end

      # tag, attributes, text content (nil for none), child nodes.
      def parts(node)
        case node
        when Root          then ["OMOBJ", { "version" => node.version }, nil, [node.object]]
        when Int           then ["OMI", {}, node.value.to_s, []]
        when Double        then ["OMF", { "dec" => float_text(node.value) }, nil, []]
        when Text          then ["OMSTR", {}, node.value, []]
        when Bytes         then ["OMB", {}, [node.value].pack("m0"), []]
        when Variable      then ["OMV", { "name" => node.name }, nil, []]
        when ContentSymbol then ["OMS", symbol_attributes(node), nil, []]
        when Application   then ["OMA", {}, nil, node.children]
        when BVar          then ["OMBVAR", {}, nil, node.vars]
        when Bind          then ["OMBIND", {}, nil, node.children]
        when Attribution   then ["OMATTR", {}, nil, [AttrList.new(node.pairs), node.object]]
        when AttrList      then ["OMATP", {}, nil, node.pairs.flat_map(&:children)]
        when Error         then ["OME", {}, nil, node.children]
        when Reference     then ["OMR", { "href" => node.href }, nil, []]
        else raise EncodeError, "no XML encoding for #{node.class}"
        end
      end

      # The OMATP element: a flat list of key/value pairs inside an OMATTR.
      # It is not an object of its own in the standard, so it is not one of
      # the thirteen classes - it exists only while encoding.
      class AttrList < Node
        attr_reader :pairs

        def initialize(pairs)
          @pairs = pairs
          freeze
        end

        def children = pairs
      end

      def symbol_attributes(node)
        attrs = {}
        attrs["cdbase"] = node.cdbase if node.cdbase
        attrs["cd"] = node.cd
        attrs["name"] = node.name
        attrs
      end

      def attributes(attrs)
        attrs.map { |k, v| %( #{k}="#{escape(v.to_s)}") }.join
      end

      def float_text(value)
        return "INF" if value == Float::INFINITY
        return "-INF" if value == -Float::INFINITY
        return "NaN" if value.nan?
        value.to_s
      end

      def escape(string) = string.to_s.gsub(/[&<>"']/) { |c| ESCAPES[c] }

      def unescape(string)
        string.to_s.gsub(/&(#x?\h+|\w+);/) do
          entity = Regexp.last_match(1)
          case entity
          when /\A#x(\h+)\z/ then Regexp.last_match(1).to_i(16).chr(Encoding::UTF_8)
          when /\A#(\d+)\z/  then Regexp.last_match(1).to_i.chr(Encoding::UTF_8)
          else ENTITIES.fetch(entity) { raise ParseError, "unknown entity &#{entity};" }
          end
        end
      end

      # ---- reading ----------------------------------------------------------

      def decode(source)
        scanner = StringScanner.new(source.to_s)
        element = read_element(scanner)
        raise ParseError, "no XML element found" unless element
        build(element)
      end

      def skip_junk(scanner)
        loop do
          scanner.skip(/\s+/)
          break unless scanner.scan(/<\?.*?\?>/m) || scanner.scan(/<!--.*?-->/m) || scanner.scan(/<!DOCTYPE[^>]*>/m)
        end
      end

      def read_element(scanner)
        skip_junk(scanner)
        return nil unless scanner.scan(/</)
        name = scanner.scan(%r{[^\s/>]+}) or raise ParseError, "expected an element name"
        attrs = read_attributes(scanner)
        return Element.new(local(name), attrs, [], "") if scanner.scan(%r{\s*/>})
        scanner.scan(/\s*>/) or raise ParseError, "unterminated <#{name}>"
        read_content(scanner, local(name), attrs)
      end

      def read_attributes(scanner)
        attrs = {}
        loop do
          scanner.skip(/\s+/)
          break if scanner.check(%r{/?>})
          key = scanner.scan(%r{[^\s=/>]+}) or raise ParseError, "expected an attribute name"
          scanner.skip(/\s*=\s*/) or raise ParseError, "expected = after #{key}"
          quote = scanner.scan(/["']/) or raise ParseError, "expected a quoted value for #{key}"
          value = scanner.scan(/[^#{Regexp.escape(quote)}]*/)
          scanner.skip(/#{Regexp.escape(quote)}/)
          attrs[local(key)] = unescape(value)
        end
        attrs
      end

      def read_content(scanner, name, attrs)
        children = []
        text = +""
        loop do
          raise ParseError, "unclosed <#{name}>" if scanner.eos?

          if scanner.check(%r{</})
            scanner.scan(%r{</[^>]*>}) or raise ParseError, "unterminated closing tag"
            break
          elsif scanner.check(/<!--/)
            scanner.scan(/<!--.*?-->/m)
          elsif scanner.check(/</)
            children << read_element(scanner)
          else
            text << unescape(scanner.scan(/[^<]+/))
          end
        end
        Element.new(name, attrs, children, text)
      end

      # Namespace prefixes carry no information here: every element of the
      # encoding lives in the OpenMath namespace.
      def local(name) = name.split(":").last

      def build(element)
        node = case element.name
               when "OMOBJ"  then Root.new(build(only_child(element)), version: element.attrs.fetch("version", OBJECT_VERSION))
               when "OMI"    then Int.new(integer_value(element.text))
               when "OMF"    then Double.new(float_value(element.attrs))
               when "OMSTR"  then Text.new(element.text)
               when "OMB"    then Bytes.new(element.text.unpack1("m") || "")
               when "OMV"    then Variable.new(attribute(element, "name"))
               when "OMS"    then ContentSymbol.new(attribute(element, "cd"), attribute(element, "name"), cdbase: element.attrs["cdbase"])
               when "OMA"    then build_application(element)
               when "OMBVAR" then BVar.new(element.children.map { |c| build(c) })
               when "OMBIND" then build_binding(element)
               when "OMATTR" then build_attribution(element)
               when "OME"    then build_error(element)
               when "OMR"    then Reference.new(attribute(element, "href"))
               else raise ParseError, "unknown OpenMath element <#{element.name}>"
               end
        id = element.attrs["id"] || element.attrs["xml:id"]
        id ? node.identified(id) : node
      end

      def build_application(element)
        children = element.children.map { |c| build(c) }
        raise ParseError, "<OMA> needs at least a head" if children.empty?
        Application.new(children.first, children[1..])
      end

      def build_binding(element)
        children = element.children
        unless children.size == 3 && children[1].name == "OMBVAR"
          raise ParseError, "<OMBIND> needs a binder, an <OMBVAR> and a body"
        end
        Bind.new(build(children[0]), build(children[1]), build(children[2]))
      end

      def build_attribution(element)
        pairs_element, object = element.children
        raise ParseError, "<OMATTR> needs an <OMATP> and an object" unless pairs_element&.name == "OMATP" && object
        flat = pairs_element.children.map { |c| build(c) }
        raise ParseError, "<OMATP> needs an even number of children" unless flat.size.even?
        Attribution.new(flat.each_slice(2).map { |k, v| AttrPair.new(k, v) }, build(object))
      end

      def build_error(element)
        children = element.children.map { |c| build(c) }
        raise ParseError, "<OME> needs a symbol" if children.empty?
        Error.new(children.first, children[1..])
      end

      def only_child(element)
        children = element.children
        raise ParseError, "<#{element.name}> needs exactly one child" unless children.size == 1
        children.first
      end

      def attribute(element, name)
        element.attrs[name] or raise ParseError, "<#{element.name}> needs a #{name} attribute"
      end

      # OMI is decimal, or hexadecimal written x1F / -x1F.
      def integer_value(text)
        stripped = text.to_s.strip
        case stripped
        when /\A(-?)x(\h+)\z/ then (Regexp.last_match(1) == "-" ? -1 : 1) * Regexp.last_match(2).to_i(16)
        when /\A-?\d+\z/      then stripped.to_i
        else raise ParseError, "not an integer: #{text.inspect}"
        end
      end

      def float_value(attrs)
        if (dec = attrs["dec"])
          case dec
          when "INF"  then Float::INFINITY
          when "-INF" then -Float::INFINITY
          when "NaN"  then Float::NAN
          else Float(dec)
          end
        elsif (hex = attrs["hex"])
          [hex].pack("H*").unpack1("G")
        else
          raise ParseError, "<OMF> needs a dec or hex attribute"
        end
      end
    end
  end
end
