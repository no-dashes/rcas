# frozen_string_literal: true

module RCAS
  # Plane geometry with exact coordinates: points, lines and circles, and the
  # questions a school course asks about them.
  #
  #   a = point(0, 0); b = point(4, 0); c = point(0, 3)
  #   distance(a, b)                  # => 4
  #   distance(c, line(a, b))         # => 3     (the distance to a line)
  #   angle(b, a, c)                  # => pi/2
  #   area(a, b, c)                   # => 6
  #   intersect(line(a, c), circle(a, 2))
  #   perpendicular_bisector(a, b)
  #
  # Everything is exact: a distance is a square root, an angle a multiple of
  # pi where the cosine is a known value, and a float only when you ask with
  # evalf. Coordinates may be symbolic.
  #
  # Sources (keys: MANUAL.md, Sources): analytic geometry as in [Spi08,
  # ch. 4]; the shoelace formula for the area [Bra86].
  module Geometry
    class Error < ArgumentError; end

    # A point of the plane.
    class Point
      attr_reader :x, :y

      def initialize(x, y)
        @x = Expression.lift(x).simplify
        @y = Expression.lift(y).simplify
        freeze
      end

      def coordinates = [x, y]
      def +(other) = Point.new(x + other.x, y + other.y)
      def -(other) = Point.new(x - other.x, y - other.y)
      def *(factor) = Point.new(x * factor, y * factor)
      def to_vector = VectorSpace.new(RR, 2).unchecked([x, y])
      def to_s = "(#{x}, #{y})"
      def inspect = to_s
      def to_latex(wrap: nil) = "\\left(#{LaTeX.of(x)},\; #{LaTeX.of(y)}\\right)"
      def ==(other) = other.is_a?(Point) && Scalar.zero?((x - other.x).simplify) && Scalar.zero?((y - other.y).simplify)
      alias eql? ==
      def hash = [Point, x, y].hash
      def evalf = Point.new(Num.new(x.evalf), Num.new(y.evalf))
    end

    # The line a*x + b*y + c = 0, kept in that form so that vertical lines
    # need no special case.
    class Line
      attr_reader :a, :b, :c

      def initialize(a, b, c)
        a = Expression.lift(a).simplify
        b = Expression.lift(b).simplify
        c = Expression.lift(c).simplify
        raise Error, "a line needs a direction: a and b cannot both be zero" if Scalar.zero?(a) && Scalar.zero?(b)
        @a, @b, @c = normalize(a, b, c)
        freeze
      end

      # Scale so that the first non-zero coefficient is positive and, when the
      # coefficients are rational, integral and coprime.
      def normalize(a, b, c)
        values = [a, b, c]
        if values.all? { |v| v.is_a?(Num) && (v.value.is_a?(Integer) || v.value.is_a?(Rational)) }
          rationals = values.map { |v| Rational(v.value) }
          scale = rationals.map(&:denominator).reduce(1, :lcm)
          integers = rationals.map { |r| (r * scale).to_i }
          divisor = integers.reject(&:zero?).map(&:abs).reduce(0, :gcd)
          integers = integers.map { |i| i / divisor } unless divisor.zero?
          integers = integers.map(&:-@) if (integers.find { |i| !i.zero? } || 0).negative?
          return integers.map { |i| Num.new(i) }
        end
        values
      end

      def self.through(p, q)
        raise Error, "the two points are the same" if p == q
        a = q.y - p.y
        b = p.x - q.x
        new(a, b, -(a * p.x + b * p.y))
      end

      def self.point_slope(p, slope)
        slope = Expression.lift(slope)
        new(slope, -1, p.y - slope * p.x)
      end

      def slope = Scalar.zero?(b) ? nil : (-a / b).simplify         # nil: vertical
      def intercept = Scalar.zero?(b) ? nil : (-c / b).simplify
      def direction = [(-b).simplify, a]
      def normal_vector = [a, b]
      def equation(x = :x, y = :y) = Equation.new((a * Expression.lift(x) + b * Expression.lift(y) + c).simplify, 0)
      def contains?(p) = Scalar.zero?((a * p.x + b * p.y + c).simplify)
      def parallel?(other) = Scalar.zero?((a * other.b - b * other.a).simplify)
      def perpendicular?(other) = Scalar.zero?((a * other.a + b * other.b).simplify)

      # The point of the line closest to p.
      def foot(p)
        t = ((a * p.x + b * p.y + c) / (a**2 + b**2)).simplify
        Point.new(p.x - a * t, p.y - b * t)
      end

      def to_s = equation.to_s
      def inspect = to_s
      def to_latex(wrap: nil) = "#{LaTeX.of(equation)}"
      def ==(other) = other.is_a?(Line) && parallel?(other) && Scalar.zero?((a * other.c - c * other.a).simplify) && Scalar.zero?((b * other.c - c * other.b).simplify)
      alias eql? ==
      def hash = [Line, a, b, c].hash
    end

    class Circle
      attr_reader :center, :radius

      def initialize(center, radius)
        @center = center
        @radius = Expression.lift(radius).simplify
        raise Error, "a circle needs a positive radius" if @radius.is_a?(Num) && !@radius.value.positive?
        freeze
      end

      def equation(x = :x, y = :y)
        x = Expression.lift(x)
        y = Expression.lift(y)
        Equation.new(((x - center.x)**2 + (y - center.y)**2).simplify, (radius**2).simplify)
      end

      def area = (PI * radius**2).simplify
      def circumference = (2 * PI * radius).simplify
      def contains?(p) = Scalar.zero?(((p.x - center.x)**2 + (p.y - center.y)**2 - radius**2).expand)
      def to_s = "circle(#{center}, #{radius})"
      def inspect = to_s
      def to_latex(wrap: nil) = LaTeX.of(equation)
      def ==(other) = other.is_a?(Circle) && center == other.center && Scalar.zero?((radius - other.radius).simplify)
      alias eql? ==
      def hash = [Circle, center, radius].hash
    end

    module_function

    def point(x, y = nil)
      return x if x.is_a?(Point)
      return Point.new(x[0], x[1]) if x.is_a?(Array)
      Point.new(x, y)
    end

    def line(first, second = nil, slope: nil)
      return first if first.is_a?(Line) && second.nil?
      p = point(first)
      return Line.point_slope(p, slope) if slope
      Line.through(p, point(second))
    end

    def circle(center, radius) = Circle.new(point(center), radius)

    def midpoint(p, q) = Point.new(((p.x + q.x) / 2).simplify, ((p.y + q.y) / 2).simplify)

    # Point to point, point to line (either order), or between parallel lines.
    def distance(a, b)
      return point_distance(a, b) if a.is_a?(Point) && b.is_a?(Point)
      return line_distance(b, a) if a.is_a?(Line) && b.is_a?(Point)
      return line_distance(a, b) if a.is_a?(Point) && b.is_a?(Line)
      if a.is_a?(Line) && b.is_a?(Line)
        raise Error, "the lines meet, so their distance is zero only there" unless a.parallel?(b)
        return line_distance(point_on(b), a)
      end
      raise Error, "distance: give two points, a point and a line, or two parallel lines"
    end

    def point_distance(p, q) = RCAS.sqrt(((q.x - p.x)**2 + (q.y - p.y)**2).expand).simplify

    def line_distance(p, l) = (RCAS.abs(l.a * p.x + l.b * p.y + l.c) / RCAS.sqrt((l.a**2 + l.b**2).expand)).simplify

    def point_on(l)
      Scalar.zero?(l.b) ? Point.new((-l.c / l.a).simplify, 0) : Point.new(0, (-l.c / l.b).simplify)
    end

    # The angle at b in the corner a-b-c, exact where the cosine is known.
    def angle(a, b, c)
      u = [a.x - b.x, a.y - b.y]
      v = [c.x - b.x, c.y - b.y]
      dot = (u[0] * v[0] + u[1] * v[1]).expand
      norms = RCAS.sqrt((u[0]**2 + u[1]**2).expand) * RCAS.sqrt((v[0]**2 + v[1]**2).expand)
      raise Error, "angle: the corner point coincides with another" if Scalar.zero?(norms.simplify)
      RCAS.acos((dot / norms).simplify)
    end

    # The angle between two lines, in [0, pi/2].
    def line_angle(l, m)
      cosine = (RCAS.abs(l.a * m.a + l.b * m.b) / (RCAS.sqrt((l.a**2 + l.b**2).expand) * RCAS.sqrt((m.a**2 + m.b**2).expand))).simplify
      RCAS.acos(cosine)
    end

    # Triangle area by the shoelace formula, or the area of a circle.
    def area(a, b = nil, c = nil)
      return a.area if a.is_a?(Circle)
      (RCAS.abs(((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)).expand) / 2).simplify
    end

    def perimeter(a, b = nil, c = nil)
      return a.circumference if a.is_a?(Circle)
      (point_distance(a, b) + point_distance(b, c) + point_distance(c, a)).simplify
    end

    def collinear?(a, b, c) = Scalar.zero?(((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)).expand)

    def centroid(*points)
      points = points.flatten
      Point.new(points.map(&:x).reduce(:+) / points.size, points.map(&:y).reduce(:+) / points.size)
    end

    def perpendicular_bisector(p, q)
      m = midpoint(p, q)
      Line.new(q.x - p.x, q.y - p.y, (-((q.x - p.x) * m.x + (q.y - p.y) * m.y)).expand)
    end

    def parallel_through(l, p) = Line.new(l.a, l.b, (-(l.a * p.x + l.b * p.y)).expand)
    def perpendicular_through(l, p) = Line.new(l.b, -l.a, (-(l.b * p.x - l.a * p.y)).expand)

    # The circle through three points that do not lie on a line.
    def circumcircle(a, b, c)
      raise Error, "the three points lie on a line" if collinear?(a, b, c)
      centre = intersect(perpendicular_bisector(a, b), perpendicular_bisector(b, c))
      Circle.new(centre, point_distance(centre, a))
    end

    # => a Point, an Array of points, nil (nothing), or the shared line or circle.
    def intersect(first, second)
      case [first, second]
      in [Line, Line] then line_line(first, second)
      in [Line, Circle] then line_circle(first, second)
      in [Circle, Line] then line_circle(second, first)
      in [Circle, Circle] then circle_circle(first, second)
      else raise Error, "intersect: give two lines, a line and a circle, or two circles"
      end
    end

    def line_line(l, m)
      determinant = (l.a * m.b - m.a * l.b).simplify
      return (l == m ? l : nil) if Scalar.zero?(determinant)
      Point.new(((l.b * m.c - m.b * l.c) / determinant).simplify, ((m.a * l.c - l.a * m.c) / determinant).simplify)
    end

    def line_circle(l, k)
      foot = l.foot(k.center)
      gap = (k.radius**2 - point_distance(foot, k.center)**2).simplify
      value = gap.is_a?(Num) ? gap.value : gap.evalf
      return [] if value.is_a?(Numeric) && value.negative?
      return [foot] if Scalar.zero?(gap)
      step = (RCAS.sqrt(gap) / RCAS.sqrt((l.a**2 + l.b**2).expand)).simplify
      direction = l.direction
      [Point.new((foot.x + direction[0] * step).simplify, (foot.y + direction[1] * step).simplify),
       Point.new((foot.x - direction[0] * step).simplify, (foot.y - direction[1] * step).simplify)]
    end

    # Subtracting the two circle equations leaves the radical line.
    def circle_circle(k, l)
      return (k == l ? k : nil) if k.center == l.center
      radical = Line.new((2 * (l.center.x - k.center.x)).simplify,
                         (2 * (l.center.y - k.center.y)).simplify,
                         (k.center.x**2 + k.center.y**2 - l.center.x**2 - l.center.y**2 - k.radius**2 + l.radius**2).expand)
      line_circle(radical, k)
    end
  end
end
