# Shared geometry for the screencast tool.
#
# record.rb sizes the pty to COLS, so what rcas-chat wraps, right-aligns and
# rules is exactly what the frame shows.
module Cast
  REPO   = File.expand_path("../..", __dir__)
  BUILD  = File.join(__dir__, "build")

  FPS    = 20
  W, H   = 1120, 760
  PAD    = 34
  CHROME = 44                             # the window's title bar
  FS     = 26
  CW     = FS * 0.6023                    # Menlo advance width
  LH     = 36
  COLS   = ((W - 2 * PAD) / CW).floor

  # The recording renders KaTeX at RENDER_SCALE so the pictures stay crisp at
  # video resolution; IMG_K brings them back to the size of the terminal text
  # and is calibrated against a scale-4.6 capture (see record.rb).
  IMG_K  = (ENV["IMG_K"] || 0.18).to_f
  SCALE  = ENV.fetch("RENDER_SCALE", "4.6").to_f

  BG, BAR = "#16181d", "#22252c"
  FG, DIM, COMMENT, AMBER = "#e8e8ea", "#5f6673", "#6f8ba3", "#ffc86b"
end
