# Turn a transcript recorded by record.rb into SVG frames.
#
#   ruby tools/screencast/screencast.rb build/tour.json
#
# Captions are the script's "# ..." lines: they appear in the terminal as the
# Ruby comments they are, so what the viewer reads is also what they could
# paste. Typing, beats and holds are the only things invented here; every
# result on screen was captured from a real session.
require "json"
require "base64"
require "fileutils"
require_relative "config"
include Cast

TRANSCRIPT = ARGV[0] or abort "usage: screencast.rb TRANSCRIPT.json"
EVENTS     = JSON.parse(File.read(TRANSCRIPT))
BANNER     = EVENTS.find { |e| e["type"] == "banner" }
FRAMES     = File.join(BUILD, "frames", File.basename(TRANSCRIPT, ".*"))

# IMG_K is calibrated against a scale-4.6 capture; hold the on-screen size
# steady whatever scale the recording actually used.
KFACTOR    = IMG_K * 4.6 / (BANNER&.dig("scale") || 4.6)
TYPE_HOLD  = 7                                            # beat before the answer
READ       = ->(s) { [10, (s.length * 0.9).round].max }   # caption reading time
HOLD       = (ENV["HOLD"] || 22).to_i                     # frames a result stays
BANNER_ON  = ENV["BANNER"] != "0"
# The recording renders at scale 4.6 so the pictures stay crisp, which makes
# the chat's own "(11.5s)" a fact about the capture rather than about rcas.
TIMINGS    = ENV["TIMINGS"] == "1"

def esc(s) = s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")

def wrap(text, width)
  text.split(/\s+/).each_with_object([+""]) do |word, lines|
    if lines.last.empty?                                   then lines.last << word
    elsif lines.last.length + 1 + word.length <= width     then lines.last << " " << word
    else lines << +word
    end
  end
end

# Room above and below a plot - its input line, the blank after it and the
# prompt that follows - so that holding on one does not scroll its top away.
IMG_ROOM = 3 * LH

IMAGES = {}
def image(el)
  IMAGES[el[:path]] ||= begin
    raw = `magick identify -format "%w %h" #{el[:path]}`.split.map(&:to_i)
    { data: Base64.strict_encode64(File.binread(el[:path])),
      **(el[:plot] ? fitted(el[:w], el[:h]) : { w: raw[0] * KFACTOR, h: raw[1] * KFACTOR }) }
  end
end

# A plot is a picture, not a rendered formula: it arrives with the size the
# terminal gave it, and a terminal fits that to its window. KFACTOR is the
# calibration for typeset formulas, where the render scale decides the size,
# and using it on a plot shrinks it to a quarter of the width.
def fitted(w, h)
  k = [(COLS - 3) * CW / w.to_f, (H - CHROME - 2 * PAD - IMG_ROOM) / h.to_f].min
  { w: w * k, h: h * k }
end

def draw(el, y)
  case el[:kind]
  when :rule
    [%(<text x="#{PAD}" y="#{y + FS}" fill="#{DIM}">#{"─" * COLS}</text>), LH]
  when :blank
    ["", LH]
  when :comment
    [%(<text x="#{PAD}" y="#{y + FS}" fill="#{COMMENT}">#{esc("# " + el[:text])}</text>), LH]
  when :input
    p = "[#{el[:n]}]❯ "
    [%(<text x="#{PAD}" y="#{y + FS}" fill="#{FG}" font-weight="bold">#{esc(p)}</text>) +
     %(<text x="#{(PAD + p.length * CW).round(2)}" y="#{y + FS}" fill="#{FG}">#{esc(el[:text])}</text>), LH]
  when :result
    [%(<text x="#{PAD}" y="#{y + FS}" fill="#{DIM}">=&gt; </text>) +
     %(<text x="#{(PAD + 3 * CW).round(2)}" y="#{y + FS}" fill="#{AMBER}">#{esc(el[:text][3..])}</text>), LH]
  when :cont
    [%(<text x="#{PAD}" y="#{y + FS}" fill="#{AMBER}">#{esc(el[:text])}</text>), LH]
  when :info, :plain
    [%(<text x="#{PAD}" y="#{y + FS}" fill="#{DIM}">#{esc("  " + el[:text])}</text>), LH]
  when :timing
    [%(<text x="#{(PAD + (COLS - el[:text].length) * CW).round(2)}" y="#{y + FS}" fill="#{DIM}">#{esc(el[:text])}</text>), LH]
  when :image
    i = image(el)
    [%(<image x="#{(PAD + 3 * CW).round(2)}" y="#{y + 6}" width="#{i[:w].round(2)}" ) +
     %(height="#{i[:h].round(2)}" href="data:image/png;base64,#{i[:data]}"/>), i[:h] + 12]
  end
end

def frame(els, cursor: nil, cursor_on: true)
  y, parts, rows = 0, [], []
  els.each { |el| s, h = draw(el, y); parts << s; rows << y; y += h }

  off = [y - (H - CHROME - 2 * PAD), 0].max    # scroll: keep the bottom in view
  cur = ""
  if cursor && cursor_on
    row, col = cursor
    cur = %(<rect x="#{(PAD + col * CW).round(2)}" y="#{rows[row] - off + CHROME + PAD + 6}" ) +
          %(width="#{CW.round(2)}" height="#{(FS * 1.15).round(2)}" fill="#{FG}" opacity="0.85"/>)
  end

  <<~SVG
    <svg xmlns="http://www.w3.org/2000/svg" width="#{W}" height="#{H}">
      <rect width="#{W}" height="#{H}" rx="12" fill="#{BG}"/>
      <g transform="translate(0 #{CHROME + PAD - off})"
         font-family="Menlo, DejaVu Sans Mono, monospace" font-size="#{FS}" xml:space="preserve">
    #{parts.join("\n")}
      </g>
      #{cur}
      <rect width="#{W}" height="#{CHROME}" fill="#{BAR}"/>
      <path d="M0 12 a12 12 0 0 1 12 -12 h#{W - 24} a12 12 0 0 1 12 12 v#{CHROME - 12} h-#{W} z" fill="#{BAR}"/>
      <circle cx="26" cy="22" r="7" fill="#ff5f57"/>
      <circle cx="50" cy="22" r="7" fill="#febc2e"/>
      <circle cx="74" cy="22" r="7" fill="#28c840"/>
      <text x="#{W / 2}" y="28" fill="#8b919c" font-family="Menlo, monospace" font-size="17" text-anchor="middle">rcas-chat</text>
    </svg>
  SVG
end

frames  = []
screen  = []
line_no = 0
push    = ->(n, cursor: nil) { n.times { |k| frames << frame(screen, cursor: cursor, cursor_on: ((k + 3) / 10).even?) } }

EVENTS.each do |ev|
  case ev["type"]
  when "banner"
    next unless BANNER_ON
    ev["lines"].reject { |l| l.match?(/\[\d+\]❯/) }   # the prompt drawn under it
       .each { |l| screen << { kind: :plain, text: l.sub(/\A\s{0,2}/, "") } }
    push.call(40)
  when "comment"
    wrap(ev["text"], COLS - 2).each { |l| screen << { kind: :comment, text: l } }
    push.call(READ.call(ev["text"]))
  when "beat"
    push.call(10)
  when "input"
    # The prompt shows the next number to be used; a /command does not use it.
    n = line_no + 1
    line_no += 1 unless ev["text"].start_with?("/")
    prompt = "[#{n}]❯ "
    screen << { kind: :rule }
    row = screen.length
    ev["text"].length.times do |c|
      frames << frame(screen + [{ kind: :input, n: n, text: ev["text"][0, c + 1] }],
                      cursor: [row, prompt.length + c + 1])
    end
    TYPE_HOLD.times do |k|
      frames << frame(screen + [{ kind: :input, n: n, text: ev["text"] }],
                      cursor: [row, prompt.length + ev["text"].length], cursor_on: (k / 10).even?)
    end
    screen << { kind: :input, n: n, text: ev["text"] }
    ev["elements"].reject { |el| el["kind"] == "timing" && !TIMINGS }.each do |el|
      screen << (el["kind"] == "image" ? { kind: :image, path: el["path"], w: el["w"], h: el["h"],
                                           plot: el["name"] == "plot.png" }
                                       : { kind: (el["style"] || el["kind"]).to_sym, text: el["text"] })
    end
    screen << { kind: :blank }
    push.call(HOLD, cursor: [screen.length - 1, 0])
  end
end

push.call(30)

FileUtils.rm_rf(FRAMES); FileUtils.mkdir_p(FRAMES)
frames.each_with_index { |s, i| File.write(File.join(FRAMES, format("f%05d.svg", i)), s) }
puts "#{frames.length} frames (#{(frames.length / FPS.to_f).round(1)} s) -> #{FRAMES}"
