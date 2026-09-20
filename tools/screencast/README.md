# tools/screencast

Turns a script of rcas input lines into a screencast (MP4 and GIF).

Nothing on screen is written by hand. The script is *replayed* against the
real `bin/rcas-chat` in a pseudo-terminal, and the results, the info lines,
the rules and the typeset pictures are decoded from what the chat actually
printed - the pictures come straight out of iTerm's inline-image escape, so
they are the same KaTeX renders a user sees. Only the typing, the pauses and
the window chrome are invented.

## The script

```ruby
# Arithmetic is exact - never a float by accident.
2/3r + 1/6r
sqrt(32)

# And when rcas cannot do one, it says so. It never guesses.
integrate(sin(x)/log(x), x)
```

- `# ...` is a caption. It appears in the terminal as the Ruby comment it is.
- A blank line is a beat.
- Anything else is typed in and evaluated, `/output typeset` included.

Because `#` is a Ruby comment, a script is also a session you can paste
straight into rcas - which is the point, and the closing line of the tour.

Two scripts are kept here:

| script       | what it is                                  |
| ------------ | ------------------------------------------- |
| `intro.rcas` | a short tour, about a minute                |
| `tour.rcas`  | the whole of MANUAL.md section 1, chapter by chapter (about eight minutes) |

Build the tour with `--no-gif`. GIF wants a small palette, and the tour is
now mostly typeset pictures and four colour plots: one global 96-colour
palette over all of that dithers into noise that no two frames share, and
the file came out at 396 MB against the mp4's 10. The format suits
`intro.rcas`, which is a minute of mostly text.

## Building

```sh
ruby tools/screencast/build.rb tools/screencast/tour.rcas
ruby tools/screencast/build.rb tools/screencast/tour.rcas --render-only
```

Everything lands in `build/` (gitignored). `--render-only` reuses the recorded
transcript, so tuning captions and pacing costs no rcas time: recording a full
tour takes minutes, laying it out takes seconds. `--no-gif` skips the GIF.

How long the recording takes is decided by *where the script switches to
typeset*, not by its length: a typeset result is a KaTeX render at
`RENDER_SCALE`, some ten seconds each, and a text one is instant. `tour.rcas`
switches before its calculus chapter, so about ninety of its lines are
rendered and a full recording is a quarter of an hour. Moving the
`/output typeset` line is the one edit that changes that number.

The three stages are also separate programs, if you want one of them alone:

| file            | what it does                                        |
| --------------- | --------------------------------------------------- |
| `record.rb`     | replays a script, writes `build/<name>.json`         |
| `screencast.rb` | transcript -> SVG frames in `build/frames/<name>/`   |
| `build.rb`      | both, then ImageMagick and ffmpeg                    |
| `config.rb`     | the geometry and colours both halves share           |

Needs `ffmpeg`, librsvg (`rsvg-convert`) and ImageMagick (`magick`) on the
PATH, plus what typesetting already needs (`npm install`, and a
Chromium-family browser). librsvg turns the frames into PNGs and ImageMagick
measures the captured pictures; on macOS, `brew install librsvg imagemagick
ffmpeg`.

## Settings

| variable       | default | what it does                                  |
| -------------- | ------- | --------------------------------------------- |
| `IMG_K`        | `0.18`  | typeset picture size, relative to the text    |
| `RENDER_SCALE` | `4.6`   | KaTeX scale used while recording              |
| `HOLD`         | `22`    | frames a result stays before the next line    |
| `BANNER`       | `1`     | `0` drops the chat's opening banner           |
| `TIMINGS`      | `0`     | `1` keeps the chat's own `(1.9s)` lines       |

`IMG_K` is calibrated against a scale-4.6 capture and `screencast.rb` corrects
for the scale actually recorded, so the two can be changed independently.

The timings are hidden by default on purpose. Recording renders KaTeX at scale
4.6 so the pictures stay crisp at video resolution, which makes a render take
ten seconds or so - a fact about the recording, not about rcas.

## Things that bit

- **Waiting for the chat to fall silent is not enough.** Typesetting a result
  takes seconds during which it prints nothing, so a recorder that stops at the
  first silence files the picture under the *next* input. `record.rb` waits for
  a fresh bare prompt instead.
- **A `/command` does not consume a line number.** The prompt shows the next
  number available, so `/output typeset` and the line after it share one.
- **The chat starts in typeset mode when it detects iTerm2**, so a script that
  wants to show the switch has to start in text: `record.rb` writes an
  `output: text` settings file into its own `RCAS_HOME` under `build/`, and
  never touches `~/.rcas`.
- **ImageMagick cannot render the frames any more.** Homebrew's `imagemagick`
  dropped its dependency on librsvg, so `magick` falls back to its own SVG
  renderer - which has no font configuration at all (`magick -list font` comes
  back empty, and `fontconfig` is not among its linked dependencies) and dies
  on the frames' `font-family` with ``unable to read font `' ``. `build.rb`
  rasterizes with `rsvg-convert` instead, which has pango and fontconfig
  behind it, renders Menlo and the embedded pictures correctly, and takes
  about a tenth of a second a frame; `magick` stays the fallback for a build
  of it that does have librsvg. `magick` is still needed either way, to
  measure the captured pictures.
- **The pty hands back bytes, not UTF-8.** The banner, the rules and the
  prompt's chevron have to be re-encoded before any regexp touches them.
