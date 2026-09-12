# frozen_string_literal: true

require_relative "test_helper"
require "rcas/chat"
require "tmpdir"

class SettingsTest < Minitest::Test
  def test_load_save_reset
    Dir.mktmpdir do |dir|
      file = File.join(dir, "settings.json")
      assert_equal({}, RCAS::Chat::Settings.load(file))
      RCAS::Chat::Settings.save({ "output" => "latex", "scale" => 1.5, "junk" => 1 }, file)
      assert_equal({ "output" => "latex", "scale" => 1.5 }, RCAS::Chat::Settings.load(file), "unknown keys are dropped")
      File.write(file, "not json")
      assert_output(nil, /ignoring/) { assert_equal({}, RCAS::Chat::Settings.load(file)) }
      RCAS::Chat::Settings.reset(file)
      refute File.exist?(file)
    end
  end

  def test_apply_respects_environment
    old_scale = RCAS::Render.instance_variable_get(:@scale)
    RCAS::Render.scale = nil
    RCAS::Chat::Settings.apply({ "scale" => 2.5, "wrap" => 40 })
    assert_in_delta 2.5, RCAS::Render.scale
    assert_equal 40, RCAS::Render.wrap
    RCAS::Render.wrap = nil
    RCAS::Render.scale = nil
    begin
      ENV["RCAS_TEX_SCALE"] = "1"
      RCAS::Chat::Settings.apply({ "scale" => 3 })
      assert_in_delta 1.0, RCAS::Render.scale, 0.001, "environment wins over the file"
    ensure
      ENV.delete("RCAS_TEX_SCALE")
      RCAS::Render.scale = old_scale
    end
  end

  def test_home_layout
    assert_equal File.join(RCAS::Chat::HOME, "settings.json"), RCAS::Chat::Settings::FILE
    assert_equal File.join(RCAS::Chat::HOME, "history"), RCAS::Chat::REPL::HISTORY_FILE
    assert_equal File.join(RCAS::Chat::HOME, "sessions"), RCAS::Chat::Session::DIR unless ENV["RCAS_SESSION_DIR"]
  end

  def test_cache_cleanup_removes_only_this_sessions_files
    Dir.mktmpdir do |dir|
      old = RCAS::Render.instance_variable_get(:@cache_dir)
      RCAS::Render.cache_dir = dir
      foreign = File.join(dir, "other.png")
      File.write(foreign, "x")
      mine = File.join(dir, "mine.png")
      File.write(mine, "y")
      RCAS::Render.created_files << mine
      RCAS::Render.cleanup!
      refute File.exist?(mine)
      assert File.exist?(foreign), "files from other sessions stay"
      assert_empty RCAS::Render.created_files
    ensure
      RCAS::Render.cache_dir = old
    end
    assert_equal "/tmp/rcas", RCAS::Render.cache_dir unless ENV["RCAS_CACHE_DIR"]
  end
end
