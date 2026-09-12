# frozen_string_literal: true

require "json"
require "fileutils"
require "securerandom"
require "time"
require "date"

module RCAS
  module Chat
    # A saved session: the transcript, the conversation with Claude and the
    # settings, as JSON under ~/.rcas/sessions. Variables are not stored;
    # they are rebuilt by replaying the transcript's Ruby when resuming.
    class Session
      DIR = ENV.fetch("RCAS_SESSION_DIR", File.join(HOME, "sessions"))

      attr_reader :id, :created_at
      attr_accessor :title, :model, :mode, :transcript, :messages, :usage, :updated_at, :cwd

      def self.dir = DIR

      def self.path(id) = File.join(dir, "#{id}.json")

      def self.list
        return [] unless File.directory?(dir)
        Dir[File.join(dir, "*.json")].filter_map { |f| load(File.basename(f, ".json")) rescue nil }.sort_by { |s| [s.updated_at, s.id] }.reverse
      end

      def self.latest = list.first

      # By id, by name (exact, then unique prefix, case-insensitive), by a
      # unique id prefix, or by a 1-based index into the list.
      def self.find(ref, among: nil)
        return latest if ref.nil? || ref.to_s.empty?
        return load(ref) if among.nil? && File.file?(path(ref))
        sessions = among || list
        ref = ref.to_s.strip
        return sessions[ref.to_i - 1] if ref.match?(/\A\d{1,3}\z/) && ref.to_i.between?(1, sessions.size)
        exact = sessions.select { |s| s.id == ref || s.title&.casecmp?(ref) }
        return exact.first if exact.size == 1
        matches = sessions.select { |s| s.id.start_with?(ref) || s.title.to_s.downcase.start_with?(ref.downcase) }
        matches.size == 1 ? matches.first : nil
      end

      def self.load(id)
        data = JSON.parse(File.read(path(id)), symbolize_names: true)
        new(id: data[:id], created_at: Time.parse(data[:created_at])).tap do |s|
          s.updated_at = Time.parse(data[:updated_at])
          s.title = data[:title]
          s.model = data[:model]
          s.mode = data[:mode]&.to_sym
          s.cwd = data[:cwd]
          s.transcript = data[:transcript].to_a.map { |e| [e[0].to_sym, *e[1..]] }
          s.messages = data[:messages].to_a
          s.usage = (data[:usage] || {}).transform_keys(&:to_sym)
        end
      end

      def initialize(id: nil, created_at: Time.now)
        @id = id || "#{created_at.strftime('%Y%m%d-%H%M%S')}-#{SecureRandom.hex(2)}"
        @created_at = created_at
        @updated_at = created_at
        @transcript = []
        @messages = []
        @usage = {}
        @cwd = Dir.pwd
      end

      def path = self.class.path(id)

      def save
        @updated_at = Time.now
        @title ||= transcript.find { |k, _| k == :input }&.[](1)&.lines&.first&.strip&.[](0, 60)
        FileUtils.mkdir_p(self.class.dir)
        File.write(path, JSON.pretty_generate(to_h))
        self
      end

      def to_h
        {
          id: id, created_at: created_at.iso8601(6), updated_at: updated_at.iso8601(6), title: title,
          model: model, mode: mode, cwd: cwd, usage: usage,
          transcript: transcript,
          messages: JSON.parse(JSON.generate(messages))
        }
      end

      def delete
        File.delete(path) if File.file?(path)
      end

      def turns = transcript.count { |k, _| k == :input }

      # The first thing typed, as a one-line preview.
      def first_input
        transcript.find { |k, _| k == :input }&.[](1)&.lines&.first&.strip&.[](0, 80)
      end

      # The title, or the first input when the session was never named.
      def name = title.to_s.empty? ? (first_input || "(empty)") : title

      # "just now", "5m ago", "3h ago", "yesterday 14:02", "Sep 10 14:02"
      def relative_time(now = Time.now)
        age = now - updated_at
        return "just now" if age < 60
        return "#{(age / 60).floor}m ago" if age < 3600
        return "#{(age / 3600).floor}h ago" if age < 86_400 && updated_at.to_date == now.to_date
        return "yesterday #{updated_at.strftime('%H:%M')}" if updated_at.to_date == (now.to_date - 1)
        updated_at.strftime(updated_at.year == now.year ? "%b %d %H:%M" : "%Y-%m-%d")
      end

      def summary
        "#{id}  #{relative_time.ljust(15)}  #{turns.to_s.rjust(3)} inputs  #{name}"
      end

      # Bring a workspace back to the state the transcript left it in.
      def replay_into(workspace)
        transcript.each do |kind, text, _|
          case kind
          when :input
            next if text.start_with?("!", "?")
            if text.start_with?("/")
              case text
              when %r{\A/forget\b(.*)} then RCAS.forget(*Regexp.last_match(1).split.map(&:to_sym))
              when %r{\A/reset\b} then workspace = Workspace.new
              end
              next
            end
            workspace.replay(text)
          when :tool then workspace.replay(text)
          end
        end
        workspace
      end
    end
  end
end
