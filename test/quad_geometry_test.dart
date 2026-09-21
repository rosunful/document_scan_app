import 'package:flutter_test/flutter_test.dart';
import 'package:scan_documnet_app/services/quad_geometry.dart';

void main() {
  group('orderCorners', () {
    test('upright rectangle orders TL, TR, BR, BL', () {
      final ordered = orderCorners([
        (300.0, 0.0), // TR
        (0.0, 200.0), // BL
        (300.0, 200.0), // BR
        (0.0, 0.0), // TL
      ]);
      expect(ordered, [
        closeToPoint(0, 0),
        closeToPoint(300, 0),
        closeToPoint(300, 200),
        closeToPoint(0, 200),
      ]);
    });

    test('in-plane rotated quad stays a valid winding', () {
      final pts = <QuadCorner>[
        (250, 250),
        (250, 550),
        (600, 400),
        (600, 700),
      ];
      final ordered = orderCorners(pts);
      // Winding must be consistent: adjacent corners share a side length that
      // is one of the two rectangle side lengths.
      double side(int i) => dist(ordered[i], ordered[(i + 1) % 4]);
      final sides = [for (var i = 0; i < 4; i++) side(i)];
      final sortedSides = sides.toList()..sort();
      expect(sortedSides[0], closeTo(sortedSides[1], 1e-6));
      expect(sortedSides[2], closeTo(sortedSides[3], 1e-6));
      // No self-intersection: polyArea uses the order as given and must be non-zero.
      expect(polyArea(ordered), greaterThan(0));
    });

    test('single point ordering returns original', () {
      final ordered = orderCorners([(5.0, 6.0)]);
      expect(ordered, [(5.0, 6.0)]);
    });
  });

  group('quadQuality', () {
    test('perfect rectangle scores 1', () {
      expect(
        quadQuality([
          (0.0, 0.0),
          (400.0, 0.0),
          (400.0, 500.0),
          (0.0, 500.0),
        ]),
        closeTo(1.0, 1e-9),
      );
    });

    test('degenerate collapsed quad scores low', () {
      expect(
        quadQuality([
          (0.0, 0.0),
          (100.0, 0.0),
          (100.0, 0.0),
          (0.0, 0.0),
        ]),
        lessThan(0.5),
      );
    });
  });

  group('lineIntersection', () {
    test('intersects two crossing lines', () {
      final p = lineIntersection(
        const QuadSegment(0, 0, 10, 10),
        const QuadSegment(0, 10, 10, 0),
      );
      expect(p.$1, closeTo(5, 1e-9));
      expect(p.$2, closeTo(5, 1e-9));
    });

    test('parallel lines give NaN', () {
      final p = lineIntersection(
        const QuadSegment(0, 0, 10, 0),
        const QuadSegment(0, 5, 10, 5),
      );
      expect(p.$1.isNaN, isTrue);
      expect(p.$2.isNaN, isTrue);
    });
  });

  group('polyArea', () {
    test('shoelace area of a 300x200 rect', () {
      expect(
        polyArea([
          (0.0, 0.0),
          (300.0, 0.0),
          (300.0, 200.0),
          (0.0, 200.0),
        ]),
        closeTo(60000, 1e-6),
      );
    });
  });

  group('quadFromLineClusters', () {
    test('reconstructs a page from four clean edges', () {
      // A ~300x200 page offset a little, sides made of collinear fragments.
      final segments = [
        // top
        const QuadSegment(50, 40, 150, 40),
        const QuadSegment(150, 40, 340, 41),
        // bottom
        const QuadSegment(50, 240, 220, 240),
        const QuadSegment(220, 240, 340, 241),
        // left
        const QuadSegment(50, 40, 50, 160),
        const QuadSegment(50, 160, 50, 240),
        // right
        const QuadSegment(340, 41, 340, 140),
        const QuadSegment(340, 140, 340, 241),
      ];
      final corners = quadFromLineClusters(segments);
      expect(corners, isNotNull);
      final page = orderCorners(corners!);
      expect(page[0].$1, closeTo(50, 6)); // TL.x
      expect(page[0].$2, closeTo(40, 6)); // TL.y
      expect(page[1].$1, closeTo(340, 6)); // TR.x
      expect(page[2].$2, closeTo(240, 6)); // BR.y
      expect(quadQuality(page), greaterThan(0.8));
    });

    test('returns null when edges are all parallel', () {
      final corners = quadFromLineClusters([
        const QuadSegment(0, 0, 100, 0),
        const QuadSegment(0, 10, 100, 10),
        const QuadSegment(0, 20, 100, 20),
      ]);
      expect(corners, isNull);
    });

    test('returns null with too few segments', () {
      expect(quadFromLineClusters(const []), isNull);
      expect(
        quadFromLineClusters(const [
          QuadSegment(0, 0, 10, 0),
          QuadSegment(0, 0, 0, 10),
          QuadSegment(0, 0, 10, 10),
        ]),
        isNull,
      );
    });
  });
}

Matcher closeToPoint(double x, double y) =>
    predicate((QuadCorner p) => (p.$1 - x).abs() < 1e-6 && (p.$2 - y).abs() < 1e-6,
        'corner at ($x, $y)');