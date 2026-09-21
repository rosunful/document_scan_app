import 'dart:math' as math;

/// Two-corner typeshorthand used across the detection pipeline
/// (analysis / full-resolution image coordinates).
typedef QuadCorner = (double, double);

/// A straight line segment, usually one edge fragment from HoughLinesP.
class QuadSegment {
  final double x1, y1, x2, y2;

  const QuadSegment(this.x1, this.y1, this.x2, this.y2);

  double get mx => (x1 + x2) / 2;
  double get my => (y1 + y2) / 2;

  double get length => math.sqrt(math.pow(x2 - x1, 2) + math.pow(y2 - y1, 2));
}

double dist(QuadCorner a, QuadCorner b) =>
    math.sqrt(math.pow(a.$1 - b.$1, 2) + math.pow(a.$2 - b.$2, 2));

/// Polygon area (shoelace), always non-negative.
double polyArea(List<QuadCorner> corners) {
  var a = 0.0;
  for (var i = 0; i < corners.length; i++) {
    final j = (i + 1) % corners.length;
    a += corners[i].$1 * corners[j].$2 - corners[j].$1 * corners[i].$2;
  }
  return a.abs() / 2;
}

/// Intersection of two infinite lines. Returns (NaN, NaN) when parallel.
QuadCorner lineIntersection(QuadSegment a, QuadSegment b) {
  final denom =
      (a.x1 - a.x2) * (b.y1 - b.y2) - (a.y1 - a.y2) * (b.x1 - b.x2);
  if (denom.abs() < 1e-9) return (double.nan, double.nan);
  final c1 = a.x1 * a.y2 - a.y1 * a.x2;
  final c2 = b.x1 * b.y2 - b.y1 * b.x2;
  final px = (c1 * (b.x1 - b.x2) - (a.x1 - a.x2) * c2) / denom;
  final py = (c1 * (b.y1 - b.y2) - (a.y1 - a.y2) * c2) / denom;
  return (px, py);
}

/// Orders four points as top-left, top-right, bottom-right, bottom-left.
///
/// Uses the angle around the centroid so the result keeps a valid, non
/// self-intersecting winding even for strongly tilted or rotated quads,
/// then rotates the first slot onto the corner with the smallest (x + y)
/// (the usual top-left for an upright page).
List<QuadCorner> orderCorners(List<QuadCorner> points) {
  var cx = 0.0, cy = 0.0;
  for (final p in points) {
    cx += p.$1;
    cy += p.$2;
  }
  cx /= points.length;
  cy /= points.length;

  final sorted = points.toList()..sort((a, b) {
        final aa = _angle(a.$1 - cx, a.$2 - cy);
        final ba = _angle(b.$1 - cx, b.$2 - cy);
        return aa.compareTo(ba);
      });

  var start = 0;
  var bestSum = double.infinity;
  for (var i = 0; i < sorted.length; i++) {
    final s = sorted[i].$1 + sorted[i].$2;
    if (s < bestSum) {
      bestSum = s;
      start = i;
    }
  }

  return [for (var i = 0; i < sorted.length; i++) sorted[(start + i) % sorted.length]];
}

double _angle(double dx, double dy) {
  final a = math.atan2(dy, dx);
  return a < 0 ? a + 2 * math.pi : a;
}

/// 1.0 for a perfect rectangle, falling toward 0 the more the quad
/// skews away from right angles or becomes an unrealistic page shape.
double quadQuality(List<QuadCorner> c) {
  var worst = 1.0;
  for (var i = 0; i < 4; i++) {
    final b = c[(i + 1) % 4];
    final v1 = (c[i].$1 - b.$1, c[i].$2 - b.$2);
    final v2 = (c[(i + 2) % 4].$1 - b.$1, c[(i + 2) % 4].$2 - b.$2);
    final mag = math.sqrt(v1.$1 * v1.$1 + v1.$2 * v1.$2) *
        math.sqrt(v2.$1 * v2.$1 + v2.$2 * v2.$2);
    if (mag == 0) return 0;
    final cosA = ((v1.$1 * v2.$1 + v1.$2 * v2.$2) / mag).abs().clamp(0.0, 1.0);
    worst = math.min(worst, 1 - cosA);
  }

  final width = math.max(dist(c[0], c[1]), dist(c[3], c[2]));
  final height = math.max(dist(c[0], c[3]), dist(c[1], c[2]));
  if (height <= 0) return 0;
  final aspect = width / height;
  if (aspect < 0.22 || aspect > 4.0) worst *= 0.35;
  return worst;
}

/// Reconstructs a quadrilateral from flat straight line segments (e.g. a
/// HoughLinesP result). Segments are bucketed by angle; the two strongest
/// orthogonal buckets are located and, for each, the two most distant
/// parallel lines become a pair of opposing page edges. The four
/// intersections of those lines are the corners. Returns null when there
/// is no usable pair of orientations.
List<QuadCorner>? quadFromLineClusters(List<QuadSegment> segments) {
  const nbins = 8;
  if (segments.length < 4) return null;

  final totals = List<double>.filled(nbins, 0);
  final byBin = List.generate(nbins, (_) => <QuadSegment>[]);
  for (final s in segments) {
    final ang = (math.atan2(s.y2 - s.y1, s.x2 - s.x1) + math.pi) % math.pi;
    final b = (ang / math.pi * nbins).floor().clamp(0, nbins - 1);
    byBin[b].add(s);
    totals[b] += s.length;
  }

  var ba = 0;
  for (var i = 1; i < nbins; i++) {
    if (totals[i] > totals[ba]) ba = i;
  }
  var bb = -1;
  for (var i = 0; i < nbins; i++) {
    final d = ((i - ba) % nbins + nbins) % nbins;
    if (math.min(d, nbins - d) < 2) continue;
    if (bb == -1 || totals[i] > totals[bb]) bb = i;
  }
  if (bb == -1 || totals[ba] <= 0 || totals[bb] < totals[ba] * 0.35) return null;

  final a = _extremes(byBin[ba], (ba + 0.5) * math.pi / nbins);
  final b = _extremes(byBin[bb], (bb + 0.5) * math.pi / nbins);
  if (a == null || b == null) return null;

  final corners = <QuadCorner>[
    lineIntersection(a.max, b.max),
    lineIntersection(a.max, b.min),
    lineIntersection(a.min, b.max),
    lineIntersection(a.min, b.min),
  ];
  if (corners.any((c) => c.$1.isNaN || c.$2.isNaN)) return null;
  return corners;
}

({QuadSegment max, QuadSegment min})? _extremes(
    List<QuadSegment> segments, double theta) {
  if (segments.isEmpty) return null;
  final nx = -math.sin(theta), ny = math.cos(theta);
  var maxS = segments.first, minS = segments.first;
  var maxOff = nx * maxS.mx + ny * maxS.my;
  var minOff = maxOff;
  for (final s in segments.skip(1)) {
    final off = nx * s.mx + ny * s.my;
    if (off > maxOff) {
      maxOff = off;
      maxS = s;
    }
    if (off < minOff) {
      minOff = off;
      minS = s;
    }
  }
  return (max: maxS, min: minS);
}