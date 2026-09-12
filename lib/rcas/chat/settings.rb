# frozen_string_literal: true

require "json"
require "fileutils"

module RCAS
  module Chat
    # ~/.rcas (RCAS_HOME): settings.json, history, sessions/
    HOME = ENV.fetch("RCAS_HOME", File.join(Dir.home, ".rcas"))

    # Persistent defaults in ~/.rcas/settings.json. Precedence, lowest first:
    # this file, environment variables, command-line flags, /commands in a
    # session. `/settings save` writes the current values back.
    module Settings
      FILE = File.join(HOME, "settings.json")
      KEYS = %w[output backend scale theme wrap model fallbacks].freeze

      module_function

      def load(file = FILE)
        return {} unless File.file?(file)
        data = JSON.parse(File.read(file))
        raise Error, "settings must be a JSON object" unless data.is_a?(Hash)
        data.select { |k, _| KEYS.include?(k) }
      rescue JSON::ParserError, Error => e
        warn "rcas: ignoring #{file}: #{e.message}"
        {}
      end

      def save(settings, file = FILE)
        FileUtils.mkdir_p(File.dirname(file))
        File.write(file, JSON.pretty_generate(settings.select { |k, _| KEYS.include?(k) }) + "\n")
        file
      end

      def reset(file = FILE)
        File.delete(file) if File.file?(file)
      end

      # Apply the file's rendering defaults where no environment variable
      # overrides them. Output mode, model and fallbacks are consumed by the
      # REPL because they depend on the session.
      def apply(settings)
        Render.backend = settings["backend"].to_sym if settings["backend"] && !ENV["RCAS_TEX_BACKEND"]
        Render.scale = settings["scale"].to_f if settings["scale"] && !ENV["RCAS_TEX_SCALE"]
        Render.theme = settings["theme"].to_sym if settings["theme"] && !ENV["RCAS_TEX_THEME"]
        Render.wrap = settings["wrap"].to_i if settings["wrap"] && !ENV["RCAS_TEX_WRAP"]
        settings
      end

      # The values in force right now, in the file's format.
      def current(ui, assistant)
        {
          "output" => ui.mode.to_s,
          "backend" => (Render.available? ? Render.selected.name.to_s : nil),
          "scale" => Render.scale,
          "theme" => Render.theme.to_s,
          "wrap" => Render.wrap,
          "model" => assistant.model,
          "fallbacks" => assistant.fallbacks
        }.compact
      end
    end
  end
end
