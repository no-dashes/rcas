# frozen_string_literal: true

require "test_helper"
require "rcas/app"
require "net/http"
require "tmpdir"
require "open3"

# The window front end: the session behind it (App::Worksheet), the little
# HTTP server that carries it (App::Server), the browser the window is
# drawn in (App::Window) and the desktop entries (App::Launcher).
class AppWorksheetTest < Minitest::Test
  def setup
    RCAS.forget
    RCAS::Results.clear
    @sheet = RCAS::App::Worksheet.new(theme: "dark")
  end

  def teardown
    RCAS.forget
    RCAS::Results.clear
    RCAS.unicode = nil
    RCAS.numbered = nil
  end

  def test_a_result_carries_text_and_latex
    cell = @sheet.submit("(x + 1) * (1 - x)")
    assert_equal "result", cell[:kind]
    assert_equal 1, cell[:n]
    assert_equal "(x + 1)*(1 - x)", cell[:text]
    assert_equal "\\left(x + 1\\right) \\left(1 - x\\right)", cell[:latex]
    assert_nil cell[:svg]
  end

  def test_the_lines_are_numbered_and_reach_each_other
    assert_equal 1, @sheet.submit("(x + 1) * (x - 1)")[:n]
    assert_equal 2, @sheet.submit("expand(Out[-1])")[:n]
    assert_equal "-1 + x**2", RCAS::Out[2].to_s
    # In[1] is the line as it was typed, held: the product, not its expansion.
    assert_equal "(x + 1)*(x - 1)", @sheet.submit("In[1]")[:text]
  end

  def test_variables_persist_between_lines
    @sheet.submit("e = (x + 1) * (1 - x)")
    assert_equal "1 - x**2", @sheet.submit("e.expand")[:text]
  end

  def test_an_error_becomes_a_cell_with_a_hint
    cell = @sheet.submit("integrate()")
    assert_equal "error", cell[:kind]
    assert_match(/ArgumentError/, cell[:text])
    assert_match(/usage: integrate/, cell[:hint].first)
  end

  def test_an_error_does_not_end_the_session
    @sheet.submit("1/0")
    assert_equal "2", @sheet.submit("1 + 1")[:text]
  end

  def test_a_plot_comes_with_svg_and_its_text
    cell = @sheet.submit("plot(sin(x), x: -PI..PI)")
    assert_match(/\A<svg/, cell[:svg])
    assert_includes cell[:svg], "</svg>"
    refute_empty cell[:text] # the braille art, for /output text
  end

  def test_output_printed_by_the_line_is_captured
    cell = @sheet.submit("puts 'hello'; 42")
    assert_equal "hello\n", cell[:stdout]
    assert_equal "42", cell[:text]
  end

  def test_an_unfinished_line_asks_for_another
    assert @sheet.incomplete?("def f(x)")
    refute @sheet.incomplete?("f(x)")
    refute @sheet.incomplete?("/help") # a command is never Ruby
  end

  def test_completion_offers_the_functions_and_the_variables
    @sheet.submit("radius = 2")
    assert_includes @sheet.complete("integ"), "integrate"
    assert_includes @sheet.complete("rad"), "radius"
    assert_empty @sheet.complete("zzzz")
  end

  def test_commands_are_answered_but_not_numbered
    assert_equal "help", @sheet.submit("/help")[:kind]
    assert_equal 1, @sheet.submit("1 + 1")[:n] # the command took no number
  end

  def test_help_for_a_name_carries_the_documentation
    cell = @sheet.submit("/help factor")
    assert_equal "doc", cell[:kind]
    assert_equal "factor(obj, extension: nil, recombination: nil)", cell[:signature]
    refute_empty cell[:lines]
    assert(cell[:background].any? { |entry| entry[:label] == :maths })
    assert(cell[:reading].any? { |link| link.start_with?("https://") })
  end

  def test_help_for_an_unknown_name_is_an_error_not_an_exception
    assert_equal "error", @sheet.submit("/help nosuchthing")[:kind]
  end

  def test_vars_and_assumptions
    assert_equal "no variables yet", @sheet.submit("/vars")[:text]
    @sheet.submit("u = x**2")
    row = @sheet.submit("/vars")[:rows].find { |r| r[:name] == "u" }
    assert_equal "x**2", row[:text]
    assert_equal "x^{2}", row[:latex]

    assert_equal "no assumptions", @sheet.submit("/assumptions")[:text]
    @sheet.submit("assume(n: ZZ)")
    assert_equal "n in ZZ", @sheet.submit("/assumptions")[:rows].first[:text]
    @sheet.submit("/forget")
    assert_equal "no assumptions", @sheet.submit("/assumptions")[:text]
  end

  def test_the_window_typesets_by_default
    assert_equal "typeset", @sheet.state[:mode]
    assert_equal "output typeset", @sheet.submit("/output")[:text]
    assert_equal %w[text typeset both latex], @sheet.state[:modes]
  end

  def test_output_mode_is_checked_and_reported
    cell = @sheet.submit("/output both")
    assert_equal "output both", cell[:text]
    assert_equal "both", cell[:state][:mode] # the page is told at once
    assert_equal "output typeset", @sheet.submit("/output typeset")[:text]
    assert_equal "typeset", @sheet.state[:mode]
    # "tex" was this mode's name before, and a settings.json may still say it.
    @sheet.submit("/output both")
    assert_equal "output typeset", @sheet.submit("/output tex")[:text]
    assert_equal "typeset", @sheet.state[:mode]
    assert_equal "error", @sheet.submit("/output sideways")[:kind]
    assert_equal "typeset", @sheet.state[:mode] # the bad one changed nothing
  end

  def test_the_mode_from_the_settings_file_is_honoured
    assert_equal "both", RCAS::App::Worksheet.new(mode: "both").state[:mode]
    assert_equal "typeset", RCAS::App::Worksheet.new(mode: "tex").state[:mode] # the old spelling
    assert_equal "typeset", RCAS::App::Worksheet.new(mode: nil).state[:mode]
    assert_equal "typeset", RCAS::App::Worksheet.new(mode: "nonsense").state[:mode]
  end

  def test_unknown_command
    cell = @sheet.submit("/nonsense")
    assert_equal "error", cell[:kind]
    assert_match(/unknown command/, cell[:text])
  end

  def test_unicode_and_numbered_reach_the_library
    @sheet.submit("/unicode on")
    assert_predicate RCAS, :unicode?
    assert_equal "\u2124", @sheet.submit("ZZ")[:text]
    @sheet.submit("/unicode off")
    refute_predicate RCAS, :unicode?
    assert_equal "ZZ", @sheet.submit("ZZ")[:text]

    @sheet.submit("/numbered off")
    refute_predicate RCAS, :numbered?
    refute @sheet.state[:numbered]
  end

  def test_latex_of_an_expression
    assert_equal "x^{2}", @sheet.submit("/latex x**2")[:text]
    assert_equal "error", @sheet.submit("/latex")[:kind]
  end

  def test_the_worksheet_can_be_replayed_after_a_reload
    @sheet.submit("1 + 1")
    @sheet.submit("/help")
    @sheet.submit("2 + 2")
    assert_equal %w[1+1 2+2], @sheet.cells.map { |c| c[:input].delete(" ") }
  end

  def test_clear_keeps_the_variables_and_reset_does_not
    @sheet.submit("w = 5")
    @sheet.submit("/clear")
    assert_empty @sheet.cells
    assert_equal "5", @sheet.submit("w")[:text]
    @sheet.submit("/reset")
    assert_equal "w", @sheet.submit("w")[:text] # a bare name is its symbol again
    assert_equal 1, RCAS::Results.line - 1
  end

  def test_save_writes_a_markdown_transcript
    @sheet.submit("factor(x**2 - 1)")
    Dir.mktmpdir("rcas-app") do |dir|
      file = File.join(dir, "session.md")
      assert_match(/saved/, @sheet.submit("/save #{file}")[:text])
      text = File.read(file)
      assert_includes text, "factor(x**2 - 1)"
      assert_includes text, "=> (-1 + x)*(1 + x)"
      assert_includes text, "$$"
    end
  end

  def test_the_state_is_what_the_page_needs
    state = @sheet.state
    assert_equal RCAS::VERSION, state[:version]
    assert_equal "dark", state[:theme]
    assert_includes state[:commands].keys.join, "/help"
  end

  def test_the_window_decides_the_colour_of_a_plot
    sheet = RCAS::App::Worksheet.new(theme: "auto")
    dark = sheet.submit("plot(sin(x), x: -PI..PI)", theme: "dark")[:svg]
    light = sheet.submit("plot(sin(x), x: -PI..PI)", theme: "light")[:svg]
    assert_includes dark, "#111827"
    assert_includes light, "#ffffff"
  end
end

class AppServerTest < Minitest::Test
  def setup
    RCAS.forget
    RCAS::Results.clear
    @sheet = RCAS::App::Worksheet.new
    @server = RCAS::App.build(@sheet, port: 0)
    begin
      @server.start
    rescue SystemCallError => e
      # A sandbox that refuses to bind a loopback port is an environment
      # fact, not a defect: say so rather than reporting nine failures
      # nobody can act on (22 Sept 2026, after a review could not run these).
      @server = nil
      skip "cannot open a loopback port here (#{e.class}: #{e.message})"
    end
    @thread = Thread.new { @server.run }
  end

  def teardown
    @server&.stop
    @thread&.kill
    RCAS.forget
    RCAS::Results.clear
  end

  def base = "http://127.0.0.1:#{@server.port}"

  def post(path, body, token: @server.token, host: nil)
    uri = URI("#{base}#{path}")
    request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
    request["X-RCAS-Token"] = token if token
    request["Host"] = host if host
    request.body = JSON.generate(body)
    Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(request) }
  end

  def test_the_page_and_its_assets_are_served
    page = Net::HTTP.get_response(URI("#{base}/"))
    assert_equal "200", page.code
    assert_includes page.body, "<title>rcas</title>"
    assert_equal "text/css; charset=utf-8", Net::HTTP.get_response(URI("#{base}/app.css"))["content-type"]
    assert_equal "text/javascript; charset=utf-8", Net::HTTP.get_response(URI("#{base}/app.js"))["content-type"]
    assert_equal "404", Net::HTTP.get_response(URI("#{base}/nothing-here")).code
  end

  def test_katex_is_served_when_it_is_installed
    skip "katex is not installed (npm install)" unless RCAS::App.katex_dir
    assert_equal "200", Net::HTTP.get_response(URI("#{base}/katex/katex.min.css")).code
    assert_equal "200", Net::HTTP.get_response(URI("#{base}/katex/fonts/KaTeX_Main-Regular.woff2")).code
  end

  def test_evaluating_through_the_api
    response = post("/api/eval", { source: "factor(x**4 - 1)" })
    assert_equal "200", response.code
    assert_equal "(-1 + x)*(1 + x)*(1 + x**2)", JSON.parse(response.body)["text"]
  end

  def test_completion_and_continuation_through_the_api
    assert_equal ["integrate"], JSON.parse(post("/api/complete", { prefix: "integ" }).body)["candidates"]
    assert JSON.parse(post("/api/incomplete", { source: "if true" }).body)["incomplete"]
  end

  def test_the_cells_come_back_for_a_reloaded_window
    post("/api/eval", { source: "1 + 1" })
    cells = JSON.parse(post("/api/cells", {}).body)["cells"]
    assert_equal ["1 + 1"], cells.map { |c| c["input"] }
  end

  # Anything that can run Ruby has to be out of reach of other pages.
  def test_the_api_needs_the_token
    assert_equal "403", post("/api/eval", { source: "1" }, token: nil).code
    assert_equal "403", post("/api/eval", { source: "1" }, token: "wrong").code
    assert_equal "403", post("/api/eval", { source: "1" }, token: "x" * @server.token.bytesize).code
  end

  # A name that resolves to 127.0.0.1 must not reach the session either.
  def test_the_api_refuses_a_foreign_host_header
    assert_equal "403", post("/api/eval", { source: "1" }, host: "rebind.example.com").code
  end

  def test_files_outside_the_asset_directory_stay_there
    %w[/../../../etc/passwd /..%2f..%2fetc/passwd /app/../../../etc/passwd].each do |path|
      response = Net::HTTP.get_response(URI("#{base}#{path}"))
      refute_equal "200", response.code, "#{path} was served"
    end
  end

  def test_the_url_carries_the_token
    assert_includes @server.url, "token=#{@server.token}"
    assert_includes @server.url, "127.0.0.1:#{@server.port}"
  end
end

class AppWindowTest < Minitest::Test
  def teardown = RCAS::App::Window.instance_variable_set(:@browser, nil)

  def test_the_browser_can_be_named_by_the_environment
    with_env("RCAS_BROWSER" => "/opt/my-browser") do
      assert_includes RCAS::App::Window.candidates, "/opt/my-browser"
    end
  end

  def test_the_candidates_include_the_ones_render_already_looks_for
    assert_includes RCAS::App::Window.candidates, "google-chrome"
    assert_includes RCAS::App::Window.candidates, "chromium"
  end

  def test_the_window_is_an_app_window_with_its_own_profile
    flags = RCAS::App::Window.flags("http://127.0.0.1:1234/?token=t", size: [900, 700], profile: "/tmp/p")
    assert_includes flags, "--app=http://127.0.0.1:1234/?token=t"
    assert_includes flags, "--user-data-dir=/tmp/p"
    assert_includes flags, "--window-size=900,700"
  end

  def test_the_profile_is_under_the_rcas_home
    assert_equal File.join(RCAS::Chat::HOME, "app"), RCAS::App::Window.profile
  end

  def with_env(values)
    old = values.to_h { |k, _| [k, ENV[k]] }
    values.each { |k, v| ENV[k] = v }
    yield
  ensure
    old.each { |k, v| ENV[k] = v }
  end
end

class AppLauncherTest < Minitest::Test
  def test_the_desktop_entry_runs_this_checkout
    entry = RCAS::App::Launcher.desktop_entry
    assert_includes entry, "[Desktop Entry]"
    assert_includes entry, "Name=rcas"
    assert_includes entry, File.join(RCAS::App.root, "bin", "rcas-app")
    assert_includes entry, "Terminal=false"
    # The window is opened with --class=rcas, so the icon groups with it.
    assert_includes entry, "StartupWMClass=rcas"
  end

  def test_the_desktop_entry_is_written_where_it_is_asked
    Dir.mktmpdir("rcas-launcher") do |dir|
      path = File.join(dir, "rcas.desktop")
      RCAS::App::Launcher.install_desktop_entry(path)
      assert_includes File.read(path), "Exec="
    end
  end

  def test_the_bundle_describes_itself_to_macos
    plist = RCAS::App::Launcher.plist
    assert_includes plist, "<key>CFBundleExecutable</key><string>rcas</string>"
    assert_includes plist, "<string>#{RCAS::VERSION}</string>"
    assert_includes plist, RCAS::App::Launcher::IDENTIFIER
  end

  def test_the_macos_bundle_is_a_runnable_application
    skip "the bundle is built with macOS's own tools" unless RCAS::App::Window.macos?
    Dir.mktmpdir("rcas-bundle") do |dir|
      bundle = File.join(dir, "rcas.app")
      RCAS::App::Launcher.install_bundle(bundle)
      runner = File.join(bundle, "Contents", "MacOS", "rcas")
      assert_path_exists File.join(bundle, "Contents", "Info.plist")
      assert_path_exists runner
      assert File.executable?(runner)
      assert_includes File.read(runner), "bin/rcas-app"
      # sips and iconutil are part of macOS and normally produce the icon,
      # but an environment that refuses to run them still gets a working
      # bundle - that is what the library promises, and it is what the
      # assertions above check.
      icns = File.join(bundle, "Contents", "Resources", "rcas.icns")
      if icon_tools?
        assert_path_exists icns
      else
        refute_path_exists icns, "no sips/iconutil, so there should be no icon either"
      end
    end
  end

  # Present *and* runnable: a sandbox may have the binaries on PATH and
  # still refuse to spawn them.
  def icon_tools?
    sips = RCAS::Render.which("sips")
    iconutil = RCAS::Render.which("iconutil")
    return false unless sips && iconutil
    RCAS::Render.run(sips, "--help")
    true
  rescue RCAS::Render::Error, SystemCallError
    false
  end

  def test_the_command_is_this_ruby_and_this_program
    ruby, script = RCAS::App::Launcher.command
    assert_equal RbConfig.ruby, ruby
    assert_path_exists script
  end

  def test_paths_with_spaces_are_quoted
    assert_equal "/usr/bin/ruby", RCAS::App::Launcher.quote("/usr/bin/ruby")
    assert_equal '"/My Apps/ruby"', RCAS::App::Launcher.quote("/My Apps/ruby")
  end
end

class AppOptionsTest < Minitest::Test
  def test_the_flags_are_read
    options = RCAS::App.parse(%w[--port 8080 --output latex --theme light --no-window])
    assert_equal 8080, options[:port]
    assert_equal "latex", options[:mode]
    assert_equal "light", options[:theme]
    refute options[:window]
  end

  def test_an_unknown_flag_says_so
    error = assert_raises(RCAS::App::Error) { RCAS::App.parse(%w[--wat]) }
    assert_match(/--wat/, error.message)
  end
end

# The page's own JavaScript, where a harness can run it: test/js holds
# plain Node scripts against the real app.js with a stub DOM. Node is not a
# dependency of rcas, so without it these skip.
class AppScriptTest < Minitest::Test
  def test_enter_submits_the_line_it_was_pressed_on
    node = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |d| File.join(d, "node") }.find { |f| File.executable?(f) }
    skip "node is not installed" unless node
    out, status = Open3.capture2e(node, File.expand_path("js/app_race.js", __dir__))
    assert status.success?, out
  end
end
