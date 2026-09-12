# frozen_string_literal: true

require "io/console"
require "stringio"

module RCAS
  module Chat
    # An interactive list of saved sessions, in the style of Claude Code's
    # /resume: arrow keys move, typing filters, Enter picks, Esc cancels.
    # Without a terminal it degrades to a numbered list read from stdin.
    class Picker
      UP    = ["\e[A", "\eOA", "\x10"].freeze # up arrow, Ctrl-P
      DOWN  = ["\e[B", "\eOB", "\x0E"].freeze # down arrow, Ctrl-N
      ENTER = ["\r", "\n"].freeze
      QUIT  = ["\e", "\x03", "\x04"].freeze   # Esc, Ctrl-C, Ctrl-D
      BACK  = ["\x7F", "\b"].freeze

      attr_reader :sessions

      def initialize(sessions, input: $stdin, output: $stdout, title: "Resume a session")
        @sessions = sessions
        @input = input
        @output = output
        @title = title
        @query = +""
        @selected = 0
        @drawn = 0
      end

      # => the chosen Session, or nil
      def run
        return nil if @sessions.empty?
        return fallback unless tty?
        @output.print "\e[?25l"
        @input.raw(intr: false) do
          loop do
            draw
            case (key = read_key)
            when *QUIT then return nil
            when *ENTER then return matches[@selected]
            when *UP then @selected -= 1
            when *DOWN then @selected += 1
            when *BACK then @query.chop!
            else @query << key if key && key.match?(/\A[[:print:]]\z/)
            end
            @selected = @selected.clamp(0, [matches.size - 1, 0].max)
          end
        end
      ensure
        clear
        @output.print "\e[?25h"
        @output.flush
      end

      def matches
        return @sessions if @query.empty?
        q = @query.downcase
        @sessions.select { |s| [s.title, s.first_input, s.id].compact.any? { |t| t.downcase.include?(q) } }
      end

      # ---- drawing ----------------------------------------------------------

      def draw
        list = matches
        visible = visible_rows
        first = [[@selected - visible + 1, 0].max, [list.size - visible, 0].max].min
        lines = [Style.bold(@title) + Style.dim("  ↑/↓ move · Enter select · Esc cancel · type to filter")]
        lines << ""
        if list.empty?
          lines << Style.dim("  no session matches #{@query.inspect}")
        else
          list[first, visible].each_with_index do |session, i|
            index = first + i
            lines.concat(row(session, index, index == @selected))
          end
          lines << Style.dim("  … #{list.size - first - visible} more") if first + visible < list.size
        end
        lines << ""
        lines << (@query.empty? ? Style.dim("  filter: type to search") : "  #{Style.dim('filter:')} #{@query}▌")
        redraw(lines)
      end

      def row(session, index, selected)
        pointer = selected ? Style.cyan("❯") : " "
        head = "#{pointer} #{Style.dim((index + 1).to_s.rjust(2) + '.')} #{session.relative_time.ljust(15)} #{"#{session.turns} inputs".ljust(11)} #{Style.bold(session.name)}"
        head = Style.paint(Style.strip(head), :cyan) if selected
        preview = session.first_input
        lines = [head]
        lines << "     #{Style.dim(preview)}" if preview && preview != session.title
        lines
      end

      def redraw(lines)
        width = columns - 1
        @output.print "\e[#{@drawn}A" if @drawn.positive?
        # The terminal is in raw mode while the picker runs, so a bare newline
        # would not return to column 0: start each row with \r and end it with \r\n.
        lines.each { |l| @output.print "\r\e[2K#{truncate(l, width)}\r\n" }
        # The list may have shrunk: blank any rows left from the last frame.
        (@drawn - lines.size).clamp(0, 100).times { @output.print "\r\e[2K\r\n" }
        extra = [@drawn - lines.size, 0].max
        @output.print "\e[#{extra}A" if extra.positive?
        @drawn = lines.size
        @output.flush
      end

      def clear
        return unless @drawn.positive?
        @output.print "\r\e[#{@drawn}A\e[J"
        @drawn = 0
      end

      def truncate(line, width)
        return line if Style.strip(line).size <= width
        "#{Style.strip(line)[0, [width - 1, 0].max]}…"
      end

      def visible_rows
        rows = @output.respond_to?(:winsize) ? @output.winsize[0] : 24
        ((rows - 6) / 2).clamp(3, 10)
      rescue StandardError
        6
      end

      def columns
        cols = @output.respond_to?(:winsize) ? @output.winsize[1] : 0
        cols.positive? ? cols : 100
      rescue StandardError
        100
      end

      # ---- input ------------------------------------------------------------

      def tty? = [@input, @output].all? { |io| io.respond_to?(:tty?) && io.tty? } && @input.respond_to?(:raw)

      # One key: a character, or a whole escape sequence (Esc, then "[" or
      # "O", then the final letter). A lone Esc is one that nothing follows.
      def read_key
        key = @input.getc
        return key if key.nil? || key != "\e" || !pending_input?
        second = @input.getc or return key
        key += second
        key += @input.getc.to_s if ["[", "O"].include?(second)
        key
      end

      def pending_input?
        return !@input.eof? if @input.is_a?(StringIO)
        IO.select([@input], nil, nil, 0.05) ? true : false
      end

      # Numbered list on a plain stream.
      def fallback
        @output.puts @title
        @sessions.first(20).each_with_index { |s, i| @output.puts "  #{(i + 1).to_s.rjust(2)}  #{s.summary}" }
        @output.print "Resume which? [1] "
        @output.flush
        answer = @input.gets.to_s.strip
        answer = "1" if answer.empty?
        Session.find(answer, among: @sessions)
      end
    end
  end
end
