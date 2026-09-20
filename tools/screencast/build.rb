# Record, render and encode a screencast in one go.
#
#   ruby tools/screencast/build.rb tools/screencast/tour.rcas
#   ruby tools/screencast/build.rb tools/screencast/tour.rcas --render-only
#
# --render-only reuses the recorded transcript, so tuning captions and pacing
# costs no rcas time (a full tour takes minutes to record, seconds to lay out).
require "fileutils"
require_relative "config"

SCRIPT = ARGV.find { |a| !a.start_with?("-") } or abort <<~USAGE
  usage: build.rb SCRIPT.rcas [--render-only] [--no-gif]

    --render-only  skip the recording, reuse build/<name>.json
    --no-gif       encode the mp4 only
USAGE
NAME   = File.basename(SCRIPT, ".*")
JSON_  = File.join(Cast::BUILD, "#{NAME}.json")
FRAMES = File.join(Cast::BUILD, "frames", NAME)
PNGS   = File.join(Cast::BUILD, "png", NAME)
MP4    = File.join(Cast::BUILD, "#{NAME}.mp4")
GIF    = File.join(Cast::BUILD, "#{NAME}.gif")

def run(*cmd)
  warn "> #{cmd.join(' ')}"
  system(*cmd) or abort "failed: #{cmd.join(' ')}"
end

def which(name) = ENV["PATH"].split(File::PATH_SEPARATOR)
                             .map { |d| File.join(d, name) }.find { |f| File.executable?(f) }

# SVG frames to PNG. rsvg-convert first: Homebrew's ImageMagick no longer
# depends on librsvg, so `magick` falls back to its own SVG renderer, which
# has no font configuration at all (`magick -list font` is empty) and dies on
# the frames' font-family with "unable to read font ''". librsvg has pango and
# fontconfig behind it and renders Menlo, the embedded pictures and all, in
# about a tenth of a second a frame. ImageMagick stays the fallback, for a
# build of it that does have librsvg.
def rasterize(svgs)
  if (rsvg = which("rsvg-convert"))
    warn "> #{rsvg} (#{svgs.size} frames)"
    svgs.each_with_index do |svg, i|
      png = File.join(PNGS, File.basename(svg, ".svg") + ".png")
      system(rsvg, "-o", png, svg) or abort "failed: rsvg-convert #{svg}"
      warn "  #{i + 1}/#{svgs.size}" if ((i + 1) % 100).zero?
    end
  else
    # One mogrify over the whole directory: ImageMagick starts once, not per frame.
    run("magick", "mogrify", "-format", "png", "-path", PNGS, *svgs)
    abort "magick produced no PNGs - see the note above rasterize" if Dir[File.join(PNGS, "*.png")].empty?
  end
end

here = __dir__
run("ruby", File.join(here, "record.rb"), SCRIPT) unless ARGV.include?("--render-only")
run("ruby", File.join(here, "screencast.rb"), JSON_)

FileUtils.rm_rf(PNGS); FileUtils.mkdir_p(PNGS)
rasterize(Dir[File.join(FRAMES, "*.svg")].sort)

run("ffmpeg", "-y", "-loglevel", "error", "-framerate", Cast::FPS.to_s,
    "-i", File.join(PNGS, "f%05d.png"),
    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20", MP4)

unless ARGV.include?("--no-gif")
  run("ffmpeg", "-y", "-loglevel", "error", "-framerate", Cast::FPS.to_s,
      "-i", File.join(PNGS, "f%05d.png"),
      "-vf", "scale=840:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=96[p];" \
             "[b][p]paletteuse=dither=bayer:bayer_scale=3",
      "-loop", "0", GIF)
end

[MP4, GIF].each { |f| puts format("%-40s %s", f, File.exist?(f) ? "#{File.size(f) / 1024} KB" : "-") }
