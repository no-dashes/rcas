# frozen_string_literal: true

module RCAS
  module Chat
    # Usage hints for errors raised inside rcas, taken from the source: the
    # `def` line of the method the user called and the comment block above
    # it (rcas documents every public function that way).
    #
    #   Usage.hint(error)   # => ["usage: sum(f, k = nil, from = nil, to = nil, **range)",
    #                       #     "sum(k**2, k, 1, n) or sum(k**2, k: 1..n); an endless range means infinity"]
    module Usage
      LIB = File.expand_path("../..", __dir__)
      USER_FRAME = "(rcas)"
      MAX_DOC_LINES = 4

      module_function

      # Lines to print under an error, or nil when there is nothing to say.
      # Only a plain ArgumentError counts: subclasses such as DomainError
      # describe the mathematics, not the call.
      def hint(error)
        return nil unless error.instance_of?(ArgumentError)
        frame = entry_frame(error) or return nil
        info = describe(frame.path, frame.lineno) or return nil
        lines = ["usage: #{info[:signature]}"]
        lines.concat(info[:doc].first(MAX_DOC_LINES))
        lines
      end

      # The outermost rcas frame that the user's code called directly.
      def entry_frame(error)
        locations = error.backtrace_locations or return nil
        before_user = locations.take_while { |l| l.path != USER_FRAME }
        return nil if before_user.size == locations.size
        before_user.reverse.find { |l| l.path.start_with?(LIB) }
      end

      # => { name:, signature:, doc: [...] } for the method whose body
      # contains +lineno+ of +path+.
      def describe(path, lineno)
        lines = File.readlines(path)
        i = lineno - 1
        i -= 1 while i >= 0 && !lines[i].match?(/^\s*def\s/)
        return nil if i.negative?
        m = lines[i].match(/def\s+(?:self\.)?(?<name>[A-Za-z_]\w*[?!=]?|[+\-*\/%<>=!\[\]~^&|]+@?)\s*(?:\((?<params>.*?)\))?/)
        return nil unless m
        doc = []
        j = i - 1
        while j >= 0 && lines[j].match?(/^\s*#/)
          doc.unshift(lines[j].sub(/^\s*#\s?/, "").rstrip)
          j -= 1
        end
        params = m[:params].to_s.strip
        signature = params.empty? ? m[:name] : "#{m[:name]}(#{params})"
        { name: m[:name], signature: signature, doc: doc }
      rescue SystemCallError, IOError
        nil
      end
    end
  end
end
