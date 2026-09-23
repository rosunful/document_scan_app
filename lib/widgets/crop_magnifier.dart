import 'package:flutter/material.dart';

/// Circular zoom lens shown while a crop handle is being dragged. It displays
/// the region under the finger magnified and positioned away from the thumb,
/// so the user can position a corner or edge precisely even when the point is
/// covered by their hand.
///
/// [imageChild] is the editor image laid out at the full preview area
/// (no crop overlay): a [Positioned] whose rect mirrors the main preview
/// (e.g. `Positioned(left: origin.dx, top: origin.dy, width, height)`),
/// placed inside the preview coordinate space that [dragLocal] uses.
/// [previewSize] is that content's box size in the same coordinate space as
/// [dragLocal]. [overlay] is drawn unmagnified on top (e.g. hairlines for the
/// crop quad), aligned so the point under the finger sits at the loupe's
/// center, keeping UI chrome thin no matter the zoom.
class CropMagnifier extends StatelessWidget {
  final Widget imageChild;
  final Widget? overlay;
  final Size previewSize;
  final Offset dragLocal;
  final double zoom;
  final double radius;
  final double verticalGap;

  const CropMagnifier({
    super.key,
    required this.imageChild,
    required this.previewSize,
    required this.dragLocal,
    this.overlay,
    this.zoom = 3.0,
    this.radius = 90,
    this.verticalGap = 12,
  });
  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    var cx = dragLocal.dx - radius * 0.4;
    var cy = dragLocal.dy - radius * 2 - verticalGap;
    if (cy < radius) {
      cy = dragLocal.dy + radius * 2 + verticalGap;
    }
    if (cx < radius) {
      cx = dragLocal.dx + radius * 1.4;
    }
    cx = cx.clamp(radius, screenSize.width - radius);
    cy = cy.clamp(radius, screenSize.height - radius);

    final translateX = radius - zoom * dragLocal.dx;
    final translateY = radius - zoom * dragLocal.dy;

    return Positioned(
      left: cx - radius,
      top: cy - radius,
      width: radius * 2,
      height: radius * 2,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 14)],
          ),
          child: ClipOval(
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: OverflowBox(
                    maxWidth: previewSize.width,
                    maxHeight: previewSize.height,
                    alignment: Alignment.topLeft,
                    child: Transform(
                      transform: Matrix4.identity()
                        ..translateByDouble(translateX, translateY, 0, 1)
                        ..scaleByDouble(zoom, zoom, zoom, 1),
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: previewSize.width,
                        height: previewSize.height,
                        child: Stack(
                          children: [imageChild],
                        ),
                      ),
                    ),
                  ),
                ),
                if (overlay != null)
                  Positioned.fill(
                      child: OverflowBox(
                        maxWidth: previewSize.width,
                        maxHeight: previewSize.height,
                        alignment: Alignment.topLeft,
                        child: Transform(
                          transform: Matrix4.identity()
                            ..translateByDouble(
                              radius - dragLocal.dx,
                              radius - dragLocal.dy,
                              0,
                              1,
                            ),
                          alignment: Alignment.topLeft,
                          child: SizedBox(
                            width: previewSize.width,
                            height: previewSize.height,
                            child: overlay!,
                          ),
                        ),
                      ),
                    ),
                Center(
                  child: CustomPaint(
                    painter: _ReticlePainter(),
                    size: Size.square(radius * 0.27),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReticlePainter extends CustomPainter {
  const _ReticlePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final r12 = size.width / 2;
    final r4 = 4.0;
    canvas
      ..drawCircle(c, r12, paint)
      ..drawCircle(c, r4, paint)
      ..drawLine(c - Offset(r12, 0), c - Offset(r4, 0), paint)
      ..drawLine(c + Offset(r4, 0), c + Offset(r12, 0), paint)
      ..drawLine(c - Offset(0, r12), c - Offset(0, r4), paint)
      ..drawLine(c + Offset(0, r4), c + Offset(0, r12), paint);
  }

  @override
  bool shouldRepaint(covariant _ReticlePainter oldDelegate) => false;
}
