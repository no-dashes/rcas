# frozen_string_literal: true

module RCAS
  module Chat
    # ANSI colours, off when not writing to a terminal or NO_COLOR is set.
    module Style
      CODES = { bold: 1, dim: 2, italic: 3, red: 31, green: 32, yellow: 33, blue: 34, magenta: 35, cyan: 36, white: 37 }.freeze

      class << self
        attr_writer :enabled

        def enabled?
          return @enabled unless @enabled.nil?
          $stdout.respond_to?(:tty?) && $stdout.tty? && ENV["NO_COLOR"].nil? && ENV["TERM"] != "dumb"
        end

        def paint(text, *styles)
          return text.to_s if styles.empty? || !enabled?
          "\e[#{styles.map { |s| CODES.fetch(s) }.join(';')}m#{text}\e[0m"
        end

        def strip(text) = text.to_s.gsub(/\e\[[\d;]*m/, "")

        CODES.each_key do |name|
          define_method(name) { |text| paint(text, name) }
        end
      end
    end
  end
end
