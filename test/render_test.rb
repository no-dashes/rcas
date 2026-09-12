# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "stringio"

class RenderTest < Minitest::Test
  include RCAS::Sets

  def setup
    @saved = ENV.to_h.slice("TMUX", "TERM", "TERM_PROGRAM", "LC_TERMINAL", "ITERM_SESSION_ID", "RCAS_TEX_THEME", "COLORFGBG", "RCAS_TEX_INLINE")
    @cache = Dir.mktmpdir("rcas-render-test")
    RCAS::Render.cache_dir = @cache
    RCAS::Render.backend = :auto
    RCAS::Render.reset!
  end

  def teardown
    %w[TMUX TERM TERM_PROGRAM LC_TERMINAL ITERM_SESSION_ID RCAS_TEX_THEME COLORFGBG RCAS_TEX_INLINE].each { |k| ENV.delete(k) }
    @saved.each { |k, v| ENV[k] = v }
    RCAS::Render.cache_dir = nil
    RCAS::Render.backend = nil
    RCAS::Render.inline = nil
    RCAS::Render.theme = nil
    RCAS::Render.reset!
    FileUtils.rm_rf(@cache)
  end

  # A 1x1 transparent PNG.
  PNG = ["89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d4944415478da63f8ffff3f0300050001" \
         "01a1cef7f10000000049454e44ae426082"].pack("H*").freeze

  def test_png_dimensions
    assert_equal [1, 1], RCAS::Render.png_dimensions(PNG)
    assert_nil RCAS::Render.png_dimensions("not a png")
  end

  def test_inline_image_sequence
    ENV.delete("TMUX")
    ENV["TERM"] = "xterm-256color"
    seq = RCAS::Render.inline_image(PNG, name: "f.png")
    assert seq.start_with?("\e]1337;File=inline=1;size=#{PNG.bytesize};")
    assert_includes seq, "name=#{Base64.strict_encode64('f.png')}"
    assert_includes seq, "width=1px;height=1px"
    assert seq.end_with?(":#{Base64.strict_encode64(PNG)}\a")
  end

  def test_inline_image_is_wrapped_for_tmux
    ENV["TMUX"] = "/tmp/tmux-1/default,1,0"
    seq = RCAS::Render.inline_image(PNG)
    assert seq.start_with?("\ePtmux;\e\e]1337;")
    assert seq.end_with?("\a\e\\")
  end

  def test_inline_detection
    ENV["TERM_PROGRAM"] = "iTerm.app"
    refute RCAS::Render.inline?(StringIO.new), "a non-tty is never inline"
    RCAS::Render.inline = true
    assert RCAS::Render.inline?(StringIO.new)
    RCAS::Render.inline = false
    refute RCAS::Render.inline?($stdout)
  end

  def test_theme_from_colorfgbg
    ENV.delete("RCAS_TEX_THEME")
    ENV["COLORFGBG"] = "15;0"
    assert_equal "dark", RCAS::Render.colorfgbg_theme
    ENV["COLORFGBG"] = "0;15"
    assert_equal "light", RCAS::Render.colorfgbg_theme
    ENV.delete("COLORFGBG")
    assert_nil RCAS::Render.colorfgbg_theme
    assert_equal "#000000", RCAS::Render.text_color("light")
    assert_equal "#ffffff", RCAS::Render.text_color("dark")
  end

  def test_show_prints_latex_when_not_inline
    RCAS::Render.inline = false
    io = StringIO.new
    RCAS::Render.show((:x + 1) / 2, io: io)
    assert_equal "\\frac{x + 1}{2}\n", io.string
    io = StringIO.new
    RCAS.show(QQ, io: io)
    assert_equal "\\mathbb{Q}\n", io.string
  end

  def test_unknown_backend_raises
    RCAS::Render.backend = :mathjax
    RCAS::Render.reset!
    assert_raises(RCAS::Render::Error) { RCAS::Render.selected }
  end

  def test_latex_backend_renders_and_caches
    skip "latex + dvipng not installed" unless RCAS::Render::TeX.available?
    RCAS::Render.backend = :latex
    RCAS::Render.reset!
    bytes = RCAS::Render.png((:x + 1) / (:x - 1), theme: "dark")
    w, h = RCAS::Render.png_dimensions(bytes)
    assert w > 20 && h > 20, "expected a real picture, got #{w}x#{h}"
    assert_equal 1, Dir[File.join(@cache, "*.png")].size
    assert_equal bytes, RCAS::Render.png((:x + 1) / (:x - 1), theme: "dark"), "second call comes from the cache"
    assert_equal 1, Dir[File.join(@cache, "*.png")].size
    file = File.join(@cache, "out.png")
    ((:x + 1) / (:x - 1)).to_png(file, theme: "dark")
    assert File.file?(file)
    assert_raises(RCAS::Render::Error) { RCAS::Render.png('\undefinedmacro', theme: "dark") }
  end

  def test_katex_backend_renders
    skip "node, katex or Chrome not installed" unless RCAS::Render::KaTeX.available?
    RCAS::Render.backend = :katex
    RCAS::Render.reset!
    html = RCAS::Render.html(:x**2)
    assert_includes html, 'class="katex'
    assert_includes html, "mathnormal"
    bytes = RCAS::Render.png((QQ**[2, 2])[[1, 2], [3, 4]], theme: "light")
    w, h = RCAS::Render.png_dimensions(bytes)
    assert w > 40 && h > 40, "expected a real picture, got #{w}x#{h}"
    assert_raises(RCAS::Render::Error) { RCAS::Render.png('\undefinedmacro', theme: "dark") }
  end
end
