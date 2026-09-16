# frozen_string_literal: true

module RCAS
  module App
    # The window itself: a Chromium-family browser started with `--app=URL`,
    # which opens one frameless window with no tabs, no address bar and no
    # bookmarks - the browser engine, without the browser around it. The
    # same flag exists on macOS, Windows and Linux, so one launcher serves
    # all three.
    #
    # The engine is borrowed, not shipped. That is the whole difference in
    # size between this and an Electron application, which bundles its own
    # copy of Chromium; rcas already asks for one of these browsers for the
    # :katex rendering backend (see render.rb), so it is usually there.
    #
    # `--user-data-dir` gives the window its own profile under ~/.rcas, so
    # it is a separate process from the user's browsing, keeps its own
    # window size and position, and takes nothing from their session.
    module Window
      # Windows keeps its browsers in Program Files and in the user's
      # AppData, neither of which is on PATH.
      WINDOWS_CANDIDATES = [
        "chrome.exe", "msedge.exe",
        "C:/Program Files/Google/Chrome/Application/chrome.exe",
        "C:/Program Files (x86)/Google/Chrome/Application/chrome.exe",
        "C:/Program Files/Microsoft/Edge/Application/msedge.exe",
        "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
        "C:/Program Files/Chromium/Application/chrome.exe",
        "C:/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe"
      ].freeze

      module_function

      def windows? = RbConfig::CONFIG["host_os"].match?(/mswin|mingw|cygwin/)
      def macos? = RbConfig::CONFIG["host_os"].match?(/darwin/)

      # Every place a Chromium-family browser might be, this platform first.
      # RCAS_BROWSER, then RCAS_CHROME (which render.rb already reads), then
      # the usual names and the usual installation paths.
      def candidates
        local = windows? ? WINDOWS_CANDIDATES : []
        local += [ENV["LOCALAPPDATA"] && File.join(ENV["LOCALAPPDATA"], "Google/Chrome/Application/chrome.exe")].compact if windows?
        [ENV["RCAS_BROWSER"], *local, *Render::KaTeX::CHROME_CANDIDATES].compact
      end

      def browser = @browser ||= Render.which(*candidates)

      def available? = !browser.nil?

      # What to tell the user when there is none.
      def missing
        "no Chromium-family browser found. rcas-app borrows one to draw its " \
          "window; install Google Chrome, Chromium, Brave or Microsoft Edge, " \
          "or point RCAS_BROWSER at one."
      end

      # The profile directory of the window: its own, so that the app is a
      # separate process from the user's browsing.
      def profile = File.join(Chat::HOME, "app")

      def flags(url, size:, profile: Window.profile)
        [
          "--app=#{url}",
          "--user-data-dir=#{profile}",
          "--window-size=#{size.join(',')}",
          "--no-first-run",
          "--no-default-browser-check",
          "--disable-features=Translate,AutofillServerCommunication",
          # Linux window managers key the icon and the task-bar group off this.
          ("--class=rcas" unless windows? || macos?)
        ].compact
      end

      # Open the window and return the process id. The browser runs as a
      # child of this process for as long as the window is open, so the
      # caller can wait on it and quit when the user closes the window.
      def open(url, size: [1100, 780])
        raise App::Error, missing unless available?
        FileUtils.mkdir_p(profile)
        Process.spawn(browser, *flags(url, size: size), %i[out err] => File::NULL)
      end

      # Wait until the window is closed. Returns nil when the browser
      # detached itself instead (some builds hand the window to an already
      # running process of the same profile and exit at once).
      def wait(pid)
        _, status = Process.waitpid2(pid)
        status
      rescue Errno::ECHILD, Interrupt
        nil
      end
    end
  end
end
