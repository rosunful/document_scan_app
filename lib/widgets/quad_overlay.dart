import 'package:flutter/material.dart';

/// Draws the crop quad over an image, dimming everything outside it and
/// rendering the four corner handles plus a mid-edge handle on each edge.
/// [corners] are screen coordinates (already scaled to the widget) in
/// TL/TR/BR/BL order.
///
/// [activeIndex] convention: `0–3` are the corners, `4–7` are the mid-edge
/// handles (edge *i* runs from corner *i* to corner *(i+1) % 4*).
class QuadOverlayPainter extends CustomPainter {
  final List<Offset> corners;
  final int? activeIndex;
  final Color maskColor;
  final Color handleColor;
  final Color handleFill;

  const QuadOverlayPainter({
    required this.corners,
    required this.activeIndex,
    required this.maskColor,
    required this.handleColor,
    required this.handleFill,
  });

  Offset _midpoint(int i) => (corners[i] + corners[(i + 1) % 4]) / 2;

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length != 4) return;

    // Dim everything outside the selected quad.
    final quadPath = Path()..addPolygon(corners, true);
    final rectPath = Path()..addRect(Offset.zero & size);
    final mask = Path.combine(PathOperation.difference, rectPath, quadPath);
    canvas.drawPath(mask, Paint()..color = maskColor);

    // Edges.
    final edgePaint = Paint()
      ..color = handleColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(quadPath, edgePaint);

    // Corner handles.
    for (var i = 0; i < corners.length; i++) {
      final active = i == activeIndex;
      canvas.drawCircle(
        corners[i],
        active ? 14 : 11,
        Paint()
          ..color = active ? handleColor : handleColor.withValues(alpha: 0.5),
      );
      canvas.drawCircle(
        corners[i],
        active ? 7 : 5.5,
        Paint()..color = handleFill,
      );
    }

    // Mid-edge handles — slightly smaller than the corners.
    for (var i = 0; i < corners.length; i++) {
      final active = 4 + i == activeIndex;
      canvas.drawCircle(
        _midpoint(i),
        active ? 11 : 8,
        Paint()
          ..color = active ? handleColor : handleColor.withValues(alpha: 0.5),
      );
      canvas.drawCircle(
        _midpoint(i),
        active ? 5.5 : 4,
        Paint()..color = handleFill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant QuadOverlayPainter oldDelegate) =>
      oldDelegate.corners != corners || oldDelegate.activeIndex != activeIndex;
}

/// Draws only the crop-quad edges as hairlines plus tiny corner/midpoint dots —
/// used inside the zoom loupe so the crops stay thin and precise while the
/// magnified image below is what actually enlarges.
class QuadEdgesPainter extends CustomPainter {
  final List<Offset> corners;
  final Color color;

  const QuadEdgesPainter({required this.corners, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length != 4) return;

    final quadPath = Path()..addPolygon(corners, true);
    final edgePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(quadPath, edgePaint);

    final dotPaint = Paint()..color = color;
    for (var i = 0; i < corners.length; i++) {
      canvas.drawCircle(corners[i], 2, dotPaint);
      canvas.drawCircle((corners[i] + corners[(i + 1) % 4]) / 2, 1.6, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant QuadEdgesPainter oldDelegate) =>
      oldDelegate.corners != corners || oldDelegate.color != color;
}
