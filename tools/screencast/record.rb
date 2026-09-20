# Replay a .rcas script against the real bin/rcas-chat and record what it
# prints. Nothing is transcribed by hand: the results, the info lines, the
# timings and the typeset pictures all come out of the pty.
#
#   ruby tools/screencast/record.rb tools/screencast/tour.rcas
#
# Script format: "# ..." is a caption, a blank line is a beat, anything else
# is an input line. Since "#" is a Ruby comment, the script is also a session
# you can paste into rcas.
require "pty"
require "json"
require "base64"
require "fileutils"
require_relative "config"

SCRIPT = ARGV[0] or abort "usage: record.rb SCRIPT.rcas"
IMGDIR = File.join(Cast::BUILD, "shots", File.basename(SCRIPT, ".*"))
HOME   = File.join(Cast::BUILD, "home")
OUT    = File.join(Cast::BUILD, "#{File.basename(SCRIPT, '.*')}.json")

FileUtils.rm_rf(IMGDIR)
FileUtils.mkdir_p([IMGDIR, HOME])
# Start in text mode so a script can show the switch to typeset; a high render
# scale so the captured pictures stay crisp at video resolution.
File.write(File.join(HOME, "settings.json"),
           JSON.dump("output" => "text", "scale" => Cast::SCALE))

EVENTS = File.readlines(SCRIPT, chomp: true).map do |line|
  case line
  when /\A\s*#(.*)\z/ then { "type" => "comment", "text" => Regexp.last_match(1).strip }
  when /\A\s*\z/      then { "type" => "beat" }
  else                     { "type" => "input", "text" => line }
  end
end

TOKEN  = "[[IMG%d]]"                  # stands in for a picture while parsing
IMGRE  = /\A\[\[IMG(\d+)\]\]\z/
PROMPT = /\A\[\d+\]❯\s?/         # the chat's "[3]> " with its chevron
BARE   = /\A\[\d+\]❯\s*\z/
RULE   = /\A─+\z/

$shot = 0

# iTerm's inline-image escape carries the PNG itself, and the size the
# terminal gave it.
def extract_images(s)
  images = []
  s = s.gsub(/\e\]1337;File=([^:]*):([A-Za-z0-9+\/=]+)\a/) do
    params, payload = Regexp.last_match(1), Regexp.last_match(2)
    path = File.join(IMGDIR, format("s%03d.png", $shot += 1))
    File.binwrite(path, Base64.decode64(payload))
    name = params[/name=([A-Za-z0-9+\/=]+)/, 1]
    images << { "kind" => "image", "path" => path,
                "w" => params[/width=(\d+)px/, 1].to_i,
                "h" => params[/height=(\d+)px/, 1].to_i,
                # "plot.png" from Plot#picture, "rcas.png" from a typeset
                # render: the two are laid out differently (screencast.rb).
                "name" => name && Base64.decode64(name) }
    format(TOKEN, images.size - 1)
  end
  [s, images]
end

def clean(s)
  # the pty hands us bytes; the banner, the rules and the chevron are UTF-8
  s = s.dup.force_encoding(Encoding::UTF_8).scrub("")
  s = s.gsub(/\e\][^\a\e]*(\a|\e\\)/, "")   # other OSC
       .gsub(/\e\[[0-9;?]*[a-zA-Z]/, "")    # CSI
       .gsub(/\e[()][B0]/, "")              # charset
  s.gsub("\r\n", "\n").split("\n", -1).map { |l| l.rpartition("\r").last.rstrip }
end

def parse(chunk, input)
  chunk, images = extract_images(chunk)
  clean(chunk).filter_map do |line|
    next if line.match?(BARE)                              # the prompt that follows
    line = line.sub(PROMPT, "") while line.match?(PROMPT)  # drop echoed prompt(s)
    next if line.strip.empty? || line.match?(RULE)         # we draw our own rule
    next if line.strip == input.strip                      # the echoed input
    if (m = line.strip.match(IMGRE))
      images[m[1].to_i]
    elsif line.match?(/\A\s*\(\d+(\.\d+)?s\)\s*\z/)
      { "kind" => "timing", "text" => line.strip }
    elsif line.start_with?("=> ")
      { "kind" => "line", "style" => "result", "text" => line }
    elsif line.start_with?("   ")
      { "kind" => "line", "style" => "cont", "text" => line }
    elsif line.start_with?("  ")
      { "kind" => "line", "style" => "info", "text" => line.strip }
    else
      { "kind" => "line", "style" => "plain", "text" => line }
    end
  end
end

# --- drive the chat ------------------------------------------------------
out        = +""
transcript = []
since      = Time.now

# The chat is done with a line when it has written a fresh bare prompt and
# gone quiet. Quiescence alone is not enough: typesetting a result takes a
# couple of seconds, during which the chat says nothing at all.
settle = lambda do |from = 0, quiet = 0.4, max = 120|
  t0, last = Time.now, out.bytesize
  loop do
    sleep 0.1
    break if Time.now - t0 > max
    if out.bytesize != last
      last = out.bytesize
      since = Time.now
      next
    end
    next unless Time.now - since > quiet
    # Not "no output yet": right after the input line is erased the chunk is
    # empty, and that is precisely the gap in which a picture is rendering.
    tail = clean(out.byteslice(from..) || "").reject(&:empty?).last
    break if tail&.match?(BARE)
  end
end

PTY.spawn({ "RCAS_HOME" => HOME, "TERM" => "xterm-256color",
            "TERM_PROGRAM" => "iTerm.app", "COLUMNS" => Cast::COLS.to_s },
          "ruby", "bin/rcas-chat", chdir: Cast::REPO) do |r, w, pid|
  Thread.new { loop { out << r.readpartial(4096) } rescue nil }

  settle.call(0, 1.2)
  transcript << { "type" => "banner", "scale" => Cast::SCALE,
                  "lines" => clean(out.dup).reject { |l| l.empty? || l.match?(PROMPT) || l.match?(RULE) } }

  EVENTS.each do |ev|
    unless ev["type"] == "input"
      transcript << ev
      next
    end
    from = out.bytesize
    w.puts(ev["text"])
    since = Time.now
    settle.call(from)
    els = parse(out.byteslice(from..) || "", ev["text"])
    transcript << ev.merge("elements" => els)
    warn format("  %-46s %s", ev["text"],
                els.map { |e| e["kind"] == "image" ? "[png]" : (e["style"] || e["kind"]) }.join(" "))
  end

  w.puts("/exit") rescue nil
  sleep 0.8
  Process.kill("TERM", pid) rescue nil
end

File.write(OUT, JSON.pretty_generate(transcript))
puts "#{transcript.count { |e| e['type'] == 'input' }} inputs, #{$shot} pictures -> #{OUT}"
