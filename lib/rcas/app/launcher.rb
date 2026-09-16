# frozen_string_literal: true

require "fileutils"
require "rbconfig"

module RCAS
  module App
    # The desktop entries that make rcas-app look like an installed
    # application: an icon in the Dock, in the Start menu or in the
    # activities overview, that starts the program without a terminal.
    #
    #   bin/rcas-app --install     # put them where the desktop looks
    #   bin/rcas-app --uninstall   # take them away again
    #
    # Each platform wants a different thing and each is a few lines of
    # text, so all three are written here rather than shipped as files:
    #
    # * macOS: an application bundle, rcas.app in ~/Applications, whose
    #   executable is a shell script that runs bin/rcas-app. `sips` and
    #   `iconutil` (both part of macOS) turn the logo into the .icns the
    #   Dock wants; without them the bundle simply has the default icon.
    # * Linux: a .desktop entry [FDO14] in ~/.local/share/applications.
    #   StartupWMClass matches the --class=rcas the window is opened with,
    #   so the running window is grouped under this icon and not under the
    #   browser's.
    # * Windows: a shortcut in the Start menu, written by the one piece of
    #   Windows scripting that is always installed (WScript.Shell through
    #   PowerShell); if that fails, a .cmd file in the same place, which
    #   works as well and only looks plainer.
    module Launcher
      IDENTIFIER = "org.rcas.app"

      module_function

      def macos? = Window.macos?
      def windows? = Window.windows?

      # Where the entry goes, per platform.
      def destination
        if macos?
          File.join(Dir.home, "Applications", "rcas.app")
        elsif windows?
          File.join(start_menu, "rcas.lnk")
        else
          File.join(ENV.fetch("XDG_DATA_HOME", File.join(Dir.home, ".local", "share")), "applications", "rcas.desktop")
        end
      end

      def start_menu
        base = ENV["APPDATA"] || File.join(Dir.home, "AppData", "Roaming")
        File.join(base, "Microsoft", "Windows", "Start Menu", "Programs")
      end

      # The command the entry runs: this Ruby, this checkout.
      def command = [RbConfig.ruby, File.join(App.root, "bin", "rcas-app")]

      def install
        path = destination
        FileUtils.mkdir_p(File.dirname(path))
        if macos? then install_bundle(path)
        elsif windows? then install_shortcut(path)
        else install_desktop_entry(path)
        end
        path
      end

      def uninstall
        path = destination
        return nil unless File.exist?(path)
        FileUtils.rm_rf(path)
        alternative = windows? ? path.sub(/\.lnk\z/, ".cmd") : nil
        FileUtils.rm_f(alternative) if alternative
        path
      end

      # ---- macOS ---------------------------------------------------------------

      def install_bundle(bundle)
        FileUtils.rm_rf(bundle)
        FileUtils.mkdir_p(File.join(bundle, "Contents", "MacOS"))
        FileUtils.mkdir_p(File.join(bundle, "Contents", "Resources"))
        File.write(File.join(bundle, "Contents", "Info.plist"), plist)
        runner = File.join(bundle, "Contents", "MacOS", "rcas")
        ruby, script = command
        File.write(runner, "#!/bin/sh\nexec #{quote(ruby)} #{quote(script)} \"$@\"\n")
        File.chmod(0o755, runner)
        icns(File.join(bundle, "Contents", "Resources", "rcas.icns"))
        bundle
      end

      def plist
        <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
          <plist version="1.0">
          <dict>
            <key>CFBundleName</key><string>rcas</string>
            <key>CFBundleDisplayName</key><string>rcas</string>
            <key>CFBundleExecutable</key><string>rcas</string>
            <key>CFBundleIdentifier</key><string>#{IDENTIFIER}</string>
            <key>CFBundleIconFile</key><string>rcas</string>
            <key>CFBundlePackageType</key><string>APPL</string>
            <key>CFBundleShortVersionString</key><string>#{RCAS::VERSION}</string>
            <key>CFBundleVersion</key><string>#{RCAS::VERSION}</string>
            <key>NSHighResolutionCapable</key><true/>
            <key>LSMinimumSystemVersion</key><string>10.13</string>
          </dict>
          </plist>
        XML
      end

      # The logo as an .icns, if macOS's own tools are there to convert it.
      def icns(path)
        logo = App.logo
        sips = Render.which("sips")
        iconutil = Render.which("iconutil")
        return nil unless logo && sips && iconutil
        Dir.mktmpdir("rcas-icon") do |dir|
          iconset = File.join(dir, "rcas.iconset")
          FileUtils.mkdir_p(iconset)
          # Two things iconutil is strict about: the files must really be
          # PNG (sips goes by -s format, not by the name it is given) and
          # each must be exactly square, which -Z and --padToHeightWidth do
          # together without squashing a logo that is wider than it is tall.
          [16, 32, 128, 256, 512].each do |size|
            { "" => size, "@2x" => size * 2 }.each do |suffix, pixels|
              Render.run(sips, "-s", "format", "png", "-Z", pixels.to_s,
                         "--padToHeightWidth", pixels.to_s, pixels.to_s, "--padColor", "FFFFFF",
                         logo, "--out", File.join(iconset, "icon_#{size}x#{size}#{suffix}.png"))
            end
          end
          Render.run(iconutil, "-c", "icns", iconset, "-o", path)
        end
        path
      rescue Render::Error, SystemCallError
        nil # an application without an icon still runs
      end

      # ---- Linux ---------------------------------------------------------------

      def install_desktop_entry(path)
        File.write(path, desktop_entry)
        File.chmod(0o644, path)
        path
      end

      def desktop_entry
        ruby, script = command
        <<~ENTRY
          [Desktop Entry]
          Type=Application
          Version=1.0
          Name=rcas
          GenericName=Computer Algebra System
          Comment=Exact mathematics: algebra, calculus, plots
          Exec=#{quote(ruby)} #{quote(script)}
          Icon=#{App.logo || 'accessories-calculator'}
          Terminal=false
          Categories=Education;Science;Math;
          Keywords=algebra;calculus;mathematics;cas;
          StartupWMClass=rcas
        ENTRY
      end

      # ---- Windows -------------------------------------------------------------

      def install_shortcut(path)
        ruby, script = command
        powershell = Render.which("powershell.exe", "powershell", "pwsh.exe", "pwsh")
        if powershell
          begin
            Render.run(powershell, "-NoProfile", "-NonInteractive", "-Command", shortcut_script(path, ruby, script))
            return path if File.exist?(path)
          rescue Render::Error
            nil # fall through to the .cmd
          end
        end
        batch = path.sub(/\.lnk\z/, ".cmd")
        File.write(batch, "@echo off\r\nstart \"rcas\" /b #{quote(ruby)} #{quote(script)} %*\r\n")
        batch
      end

      def shortcut_script(path, ruby, script)
        # rubyw runs without a console window; plain ruby is the fallback.
        runner = ruby.sub(/ruby\.exe\z/i, "rubyw.exe")
        runner = ruby unless File.exist?(runner)
        <<~PS.gsub("\n", "; ")
          $s = (New-Object -ComObject WScript.Shell).CreateShortcut('#{path}')
          $s.TargetPath = '#{runner}'
          $s.Arguments = '"#{script}"'
          $s.WorkingDirectory = '#{App.root}'
          $s.IconLocation = '#{App.logo}'
          $s.Description = 'rcas - computer algebra'
          $s.Save()
        PS
      end

      # ---- helpers -------------------------------------------------------------

      def quote(word) = word.to_s.match?(/\A[\w.\/:\\-]+\z/) ? word.to_s : %("#{word}")
    end
  end
end
