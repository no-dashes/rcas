# frozen_string_literal: true

module RCAS
  # Function plotting.
  #
  #   plot(sin(x))                          # -10..10, drawn in the terminal
  #   plot(x**2 - 1, x: -3..3)
  #   plot([sin(x), cos(x)], x: 0..2*PI)
  #   plot(Normal(0, 1))                    # the density of a distribution
  #   scatter([1, 2, 3], [2, 4, 7])         # data, with linreg(...) alongside
  #   plot(1/x, x: -3..3).save("hyperbola.svg")
  #   plot(sin(x)).show                     # inline picture in iTerm2
  #
  # A Plot prints as Unicode braille art, which needs nothing but a terminal
  # and is what `inspect` shows; `to_svg` and `save` write a picture, `to_png`
  # and `show` rasterize it with headless Chrome (the renderer the typeset
  # output already uses). Sampling is uniform; values that are complex,
  # infinite or undefined leave a gap, and a jump across a pole breaks the
  # line rather than drawing a vertical stroke.
  #
  # Sources (keys: MANUAL.md, Sources): line drawing [Bre65]; the braille
  # canvas is the technique of drawille and UnicodePlots.jl; the y range for
  # functions with poles is trimmed to the central 96 per cent of the sampled
  # values, as gnuplot's autoscaling does in spirit.
  class Plot
    class Error < StandardError; end

    # Braille cells are 2 by 4 dots; these are the bit values of the dots.
    DOTS = [[0x01, 0x02, 0x04, 0x40], [0x08, 0x10, 0x20, 0x80]].freeze
    BRAILLE_BLANK = 0x2800
    COLORS = %w[#2563eb #dc2626 #059669 #d97706 #7c3aed #0891b2].freeze
    DEFAULT_RANGE = (-10.0..10.0)

    Curve = Struct.new(:label, :points, :marker)

    attr_reader :curves, :var, :xlo, :xhi, :ylo, :yhi, :title, :width, :height

    def initialize(curves, var:, xlo:, xhi:, ylo:, yhi:, title: nil, width: 60, height: 15)
      @curves = curves
      @var = var
      @xlo = xlo
      @xhi = xhi
      @ylo = ylo
      @yhi = yhi
      @title = title
      @width = width
      @height = height
      freeze
    end

    def x_range = (xlo..xhi)
    def y_range = (ylo..yhi)

    # ---- the terminal picture ------------------------------------------------

    def to_s
      canvas = Canvas.new(width, height)
      draw_axes(canvas)
      curves.each { |curve| draw_curve(canvas, curve) }
      frame(canvas.rows)
    end

    def inspect = to_s

    def draw_axes(canvas)
      if ylo < 0 && yhi > 0
        row = pixel_y(0)
        (0...canvas.pixel_width).step(4) { |px| canvas.set(px, row) }
      end
      return unless xlo < 0 && xhi > 0
      column = pixel_x(0)
      (0...canvas.pixel_height).step(2) { |py| canvas.set(column, py) }
    end

    def draw_curve(canvas, curve)
      previous = nil
      curve.points.each do |point|
        if point.nil?
          previous = nil
          next
        end
        x, y = point
        px = pixel_x(x)
        py = pixel_y(y)
        if curve.marker == :stem
          base = pixel_y([0.0, ylo].max)
          canvas.line(px, base, px, py)
          canvas.set(px, py)
        elsif curve.marker
          canvas.set(px, py)
        elsif previous && !jump?(previous, point)
          canvas.line(pixel_x(previous[0]), pixel_y(previous[1]), px, py)
        elsif inside?(y)
          canvas.set(px, py)
        end
        previous = point
      end
    end

    # A pole: the two samples straddle the whole picture in opposite directions.
    def jump?(a, b)
      return false unless (b[1] - a[1]).abs > (yhi - ylo)
      (a[1] <=> 0) != (b[1] <=> 0)
    end

    def inside?(y) = y >= ylo && y <= yhi

    def pixel_x(x) = (((x - xlo) / (xhi - xlo)) * (width * 2 - 1)).round
    def pixel_y(y) = (((yhi - y) / (yhi - ylo)) * (height * 4 - 1)).round

    def self.label(value)
      return "0" if value.zero?
      text = format("%.4g", value)
      text.include?("e") ? text : text.sub(/\.0+\z/, "")
    end

    # y labels in a gutter, the canvas, then the x axis and its labels.
    def frame(rows)
      top = self.class.label(yhi)
      bottom = self.class.label(ylo)
      gutter = [top.size, bottom.size].max
      lines = []
      lines << title if title
      rows.each_with_index do |row, i|
        mark = if i.zero? then top.rjust(gutter) + " ┤"
               elsif i == rows.size - 1 then bottom.rjust(gutter) + " ┤"
               else (" " * gutter) + " │"
               end
        lines << mark + row
      end
      lines << (" " * (gutter + 1)) + "└" + "─" * width
      left = self.class.label(xlo)
      right = self.class.label(xhi)
      pad = [width - left.size - right.size, 1].max
      lines << (" " * (gutter + 2)) + left + (" " * pad) + right
      lines << "  " + legend if curves.size > 1 || curves.first&.label
      lines.join("\n")
    end

    def legend = curves.map(&:label).compact.join(", ")

    # ---- pictures --------------------------------------------------------------

    def svg_size = [720, 440]

    def to_svg(theme: nil)
      w, h = svg_size
      theme = (theme || Render.theme).to_s
      background = theme == "light" ? "#ffffff" : "#111827"
      foreground = theme == "light" ? "#111827" : "#e5e7eb"
      grid = theme == "light" ? "#9ca3af" : "#4b5563"
      left = 60
      right = 20
      top = title ? 34 : 16
      bottom = 40
      plot_w = w - left - right
      plot_h = h - top - bottom
      sx = ->(x) { left + (x - xlo) / (xhi - xlo) * plot_w }
      sy = ->(y) { top + (yhi - y) / (yhi - ylo) * plot_h }

      parts = []
      parts << %(<rect width="#{w}" height="#{h}" fill="#{background}"/>)
      parts << %(<text x="#{w / 2}" y="22" fill="#{foreground}" font-family="sans-serif" font-size="16" text-anchor="middle">#{escape(title)}</text>) if title
      parts << %(<rect x="#{left}" y="#{top}" width="#{plot_w}" height="#{plot_h}" fill="none" stroke="#{grid}" stroke-width="1"/>)
      if ylo < 0 && yhi > 0
        y0 = sy.call(0).round(2)
        parts << %(<line x1="#{left}" y1="#{y0}" x2="#{left + plot_w}" y2="#{y0}" stroke="#{grid}" stroke-width="1" stroke-dasharray="4 3"/>)
      end
      if xlo < 0 && xhi > 0
        x0 = sx.call(0).round(2)
        parts << %(<line x1="#{x0}" y1="#{top}" x2="#{x0}" y2="#{top + plot_h}" stroke="#{grid}" stroke-width="1" stroke-dasharray="4 3"/>)
      end
      [[xlo, :x], [xhi, :x]].each_with_index do |(value, _), i|
        x = i.zero? ? left : left + plot_w
        anchor = i.zero? ? "start" : "end"
        parts << %(<text x="#{x}" y="#{h - 14}" fill="#{foreground}" font-family="sans-serif" font-size="13" text-anchor="#{anchor}">#{self.class.label(value)}</text>)
      end
      [[yhi, top + 4], [ylo, top + plot_h]].each do |value, y|
        parts << %(<text x="#{left - 8}" y="#{y}" fill="#{foreground}" font-family="sans-serif" font-size="13" text-anchor="end">#{self.class.label(value)}</text>)
      end
      curves.each_with_index do |curve, i|
        color = COLORS[i % COLORS.size]
        if curve.marker
          base = sy.call([0.0, ylo].max).round(2)
          curve.points.compact.select { |_, y| inside?(y) }.each do |x, y|
            cx = sx.call(x).round(2)
            cy = sy.call(y).round(2)
            parts << %(<line x1="#{cx}" y1="#{base}" x2="#{cx}" y2="#{cy}" stroke="#{color}" stroke-width="2"/>) if curve.marker == :stem
            parts << %(<circle cx="#{cx}" cy="#{cy}" r="3.5" fill="#{color}"/>)
          end
        else
          segments(curve).each do |segment|
            points = segment.map { |x, y| "#{sx.call(x).round(2)},#{sy.call([[y, ylo].max, yhi].min).round(2)}" }.join(" ")
            parts << %(<polyline points="#{points}" fill="none" stroke="#{color}" stroke-width="2" stroke-linejoin="round"/>)
          end
        end
        next unless curve.label
        parts << %(<text x="#{left + 10}" y="#{top + 18 + i * 18}" fill="#{color}" font-family="sans-serif" font-size="13">#{escape(curve.label)}</text>)
      end
      %(<svg xmlns="http://www.w3.org/2000/svg" width="#{w}" height="#{h}" viewBox="0 0 #{w} #{h}">#{parts.join}</svg>)
    end

    # Pieces of the curve without gaps or jumps across a pole.
    def segments(curve)
      out = []
      current = []
      previous = nil
      curve.points.each do |point|
        if point.nil? || (previous && jump?(previous, point))
          out << current if current.size > 1
          current = []
        end
        current << point if point
        previous = point
      end
      out << current if current.size > 1
      out
    end

    def escape(text) = text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")

    def to_png(path = nil, theme: nil)
      chrome = Render.which(*Render::KaTeX::CHROME_CANDIDATES)
      raise Error, "a picture needs Google Chrome or Chromium; save(\"plot.svg\") needs nothing" if chrome.nil?
      w, h = svg_size
      bytes = Dir.mktmpdir("rcas-plot") do |dir|
        page = File.join(dir, "plot.html")
        File.write(page, %(<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;padding:0}</style></head><body>#{to_svg(theme: theme)}</body></html>))
        shot = File.join(dir, "plot.png")
        Render.run(chrome, "--headless=new", "--disable-gpu", "--no-sandbox", "--hide-scrollbars", "--no-first-run",
                   "--force-device-scale-factor=#{Render.device_scale}", "--window-size=#{w},#{h}",
                   "--screenshot=#{shot}", "file://#{page}")
        raise Error, "Chrome produced no picture" unless File.file?(shot)
        File.binread(shot)
      end
      return bytes if path.nil?
      File.binwrite(path, bytes)
      path
    end

    # "plot.svg" needs nothing, "plot.png" needs Chrome.
    def save(path)
      if File.extname(path).downcase == ".png"
        to_png(path)
      else
        File.write(path, to_svg)
      end
      path
    end

    # Inline in iTerm2 when the terminal and Chrome allow it, text otherwise.
    def show(io: $stdout)
      if Render.inline?(io) && Render.which(*Render::KaTeX::CHROME_CANDIDATES)
        begin
          io.print(Render.inline_image(to_png, name: "plot.png"))
          io.puts
          return nil
        rescue Error, Render::Error
          nil
        end
      end
      io.puts(to_s)
      nil
    end

    # A grid of braille dots.
    class Canvas
      def initialize(width, height)
        @width = width
        @height = height
        @cells = Array.new(width * height, 0)
      end

      def pixel_width = @width * 2
      def pixel_height = @height * 4

      def set(px, py)
        return if px.negative? || py.negative? || px >= pixel_width || py >= pixel_height
        @cells[(py / 4) * @width + (px / 2)] |= DOTS[px % 2][py % 4]
      end

      # Bresenham's line algorithm [Bre65].
      def line(x0, y0, x1, y1)
        dx = (x1 - x0).abs
        dy = -(y1 - y0).abs
        sx = x0 < x1 ? 1 : -1
        sy = y0 < y1 ? 1 : -1
        error = dx + dy
        x = x0
        y = y0
        loop do
          set(x, y)
          break if x == x1 && y == y1
          double = 2 * error
          if double >= dy
            error += dy
            x += sx
          end
          if double <= dx
            error += dx
            y += sy
          end
        end
      end

      def rows
        (0...@height).map do |cy|
          (0...@width).map { |cx| (BRAILLE_BLANK + @cells[cy * @width + cx]).chr(Encoding::UTF_8) }.join
        end
      end
    end
  end

  # Building plots from expressions, distributions and data.
  module Plotting
    SAMPLES = 400

    module_function

    # plot(f, x: -5..5), plot([f, g], x: 0..1), plot(f, :t, -1, 1)
    def plot(f, var = nil, from = nil, to = nil, x: nil, y: nil, n: SAMPLES, title: nil, labels: nil, width: 60, height: 15)
      functions = f.is_a?(Array) ? f : [f]
      return distribution_plot(functions, var, from, to, x, y, n, title, labels, width, height) if functions.first.is_a?(Distributions::Distribution)
      functions = functions.map { |g| Expression.lift(g) }
      variable = plot_variable(functions, var, x)
      lo, hi = plot_range(var, from, to, x)
      curves = functions.each_with_index.map do |g, i|
        Curve_for(g, variable, lo, hi, n, labels ? labels[i] : (functions.size > 1 ? g.to_s : nil))
      end
      ylo, yhi = y_range(curves, y)
      Plot.new(curves, var: variable, xlo: lo, xhi: hi, ylo: ylo, yhi: yhi, title: title, width: width, height: height)
    end

    def Curve_for(g, variable, lo, hi, n, label)
      Plot::Curve.new(label, sample(g, variable, lo, hi, n), false)
    end

    # The density of a distribution over a sensible range.
    def distribution_plot(distributions, var, from, to, x, y, n, title, labels, width, height)
      variable = Var.new(:x)
      lo, hi = if x || from then plot_range(var, from, to, x) else natural_range(distributions) end
      discrete = distributions.first.discrete?
      curves = distributions.each_with_index.map do |d, i|
        label = labels ? labels[i] : (distributions.size > 1 ? d.to_s : nil)
        if discrete
          points = (lo.ceil..hi.floor).map { |k| [k.to_f, numeric(d.pdf(k))] }.select { |_, v| v }
          Plot::Curve.new(label, points, :stem)
        else
          Plot::Curve.new(label, sample(d.pdf(variable), variable, lo, hi, n), false)
        end
      end
      ylo, yhi = y_range(curves, y)
      ylo = 0.0 if ylo > 0
      Plot.new(curves, var: variable, xlo: lo, xhi: hi, ylo: ylo, yhi: yhi,
               title: title || (distributions.size == 1 ? distributions.first.to_s : nil), width: width, height: height)
    end

    # Mean plus or minus four standard deviations, kept inside the support.
    def natural_range(distributions)
      los = []
      his = []
      distributions.each do |d|
        mean = numeric(d.mean)
        spread = numeric(d.stdev)
        raise Plot::Error, "plot: #{d} has no numeric mean and spread; give a range" if mean.nil? || spread.nil? || spread.zero?
        low = mean - 4 * spread
        high = mean + 4 * spread
        bottom = numeric(d.support.first)
        top = numeric(d.support.last)
        low = bottom if bottom && bottom > low
        high = top if top && top < high
        los << low
        his << high
      end
      [los.min, his.max]
    end

    # Points of data: scatter([1, 2], [3, 4]) or scatter([[1, 3], [2, 4]])
    def scatter(xs, ys = nil, title: nil, label: nil, x: nil, y: nil, width: 60, height: 15)
      pairs = if ys.nil?
                xs.map { |p| [numeric(p[0]), numeric(p[1])] }
              else
                raise ArgumentError, "scatter: the lists must have the same length" unless xs.size == ys.size
                xs.zip(ys).map { |a, b| [numeric(a), numeric(b)] }
              end
      pairs = pairs.reject { |a, b| a.nil? || b.nil? }
      raise ArgumentError, "scatter: no points to draw" if pairs.empty?
      lo, hi = x ? [numeric(x.begin), numeric(x.end)] : padded(pairs.map(&:first))
      curve = Plot::Curve.new(label, pairs, :dot)
      ylo, yhi = y ? [numeric(y.begin), numeric(y.end)] : padded(pairs.map(&:last))
      Plot.new([curve], var: Var.new(:x), xlo: lo, xhi: hi, ylo: ylo, yhi: yhi, title: title, width: width, height: height)
    end

    def padded(values)
      lo = values.min
      hi = values.max
      return [lo - 1, hi + 1] if (hi - lo).abs < 1e-12
      pad = (hi - lo) * 0.05
      [lo - pad, hi + pad]
    end

    def plot_variable(functions, var, range)
      name = var || (range.is_a?(Hash) ? range.keys.first : nil)
      return Expression.lift(name) if name
      names = functions.flat_map(&:variables).uniq
      raise ArgumentError, "plot: #{functions.first} has no variable to plot over" if names.empty?
      raise ArgumentError, "plot: which variable? give a range, e.g. plot(f, x: -1..1)" if names.size > 1
      Var.new(names.first)
    end

    def plot_range(var, from, to, range)
      if range
        r = range.is_a?(Hash) ? range.values.first : range
        raise ArgumentError, "plot: expected a range, e.g. x: -5..5" unless r.is_a?(Range)
        from = r.begin
        to = r.end
      end
      return [DEFAULT_LOW, DEFAULT_HIGH] if from.nil? && to.nil?
      lo = numeric(from)
      hi = numeric(to)
      raise ArgumentError, "plot: the range must be finite, got #{from}..#{to}" if lo.nil? || hi.nil?
      raise ArgumentError, "plot: the range is empty" if hi <= lo
      [lo, hi]
    end

    DEFAULT_LOW = Plot::DEFAULT_RANGE.begin
    DEFAULT_HIGH = Plot::DEFAULT_RANGE.end

    def sample(g, variable, lo, hi, n)
      tree = Expression.floatify_tree(Expression.lift(g))
      name = variable.name
      (0..n).map do |i|
        x = lo + (hi - lo) * i / n.to_f
        v = evaluate(tree, name, x)
        v ? [x, v] : nil
      end
    end

    def evaluate(tree, name, x)
      v = tree.call(name => x)
      v = v.value if v.is_a?(Num)
      return nil unless v.is_a?(Numeric) && !v.is_a?(Complex)
      v = v.to_f
      v.finite? ? v : nil
    rescue StandardError
      nil
    end

    def numeric(value)
      return nil if value.nil?
      v = value.is_a?(Numeric) ? value : Expression.lift(value).evalf
      v.is_a?(Numeric) && !v.is_a?(Complex) && v.finite? ? v.to_f : nil
    rescue StandardError
      nil
    end

    # Auto scale, trimmed to the central 96 per cent when a pole would
    # otherwise flatten the picture.
    def y_range(curves, given)
      if given
        lo = numeric(given.begin)
        hi = numeric(given.end)
        raise ArgumentError, "plot: the y range must be finite" if lo.nil? || hi.nil?
        return [lo, hi]
      end
      values = curves.flat_map { |c| c.points.compact.map(&:last) }.sort
      raise Plot::Error, "plot: the function has no finite values in this range" if values.empty?
      lo = values.first
      hi = values.last
      if values.size > 20
        low = values[(values.size * 0.02).floor]
        high = values[(values.size * 0.98).floor]
        lo, hi = [low, high] if high > low && (hi - lo) > 8 * (high - low)
      end
      if (hi - lo).abs < 1e-12
        [lo - 1, hi + 1]
      else
        pad = (hi - lo) * 0.05
        [lo - pad, hi + pad]
      end
    end
  end
end
