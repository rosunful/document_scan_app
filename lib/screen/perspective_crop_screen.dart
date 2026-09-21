import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/auto_crop_service.dart';
import '../theme/app_theme.dart';

/// Lets the user drag the document's four corners to fix perspective. The
/// result is written to [targetPath] with OpenCV's warpPerspective and
/// returned via pop when Apply is tapped.
class PerspectiveCropScreen extends StatefulWidget {
  final String sourcePath;
  final String targetPath;

  const PerspectiveCropScreen({
    super.key,
    required this.sourcePath,
    required this.targetPath,
  });

  @override
  State<PerspectiveCropScreen> createState() => _PerspectiveCropScreenState();
}

class _PerspectiveCropScreenState extends State<PerspectiveCropScreen> {
  bool _loading = true;
  bool _applying = false;

  Size _imageSize = Size.zero;
  List<Offset> _corners = const [];

  // Mapping from image coordinates to the on-screen box, recomputed each
  // build and read by the pan handlers.
  double _scale = 1;
  Offset _origin = Offset.zero;

  int? _dragIndex;

  // Keeps the image away from the screen edges so the corner handles never
  // end up right on (or sliding off) the border.
  static const double _inset = 28;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await File(widget.sourcePath).readAsBytes();
      final image = await decodeImageFromList(bytes);

      if (!mounted) {
        image.dispose();
        return;
      }

      setState(() {
        _imageSize = Size(image.width.toDouble(), image.height.toDouble());
        // Fully manual: start from the whole image and let the user drag each
        // corner onto the page. No auto-detection involved.
        _corners = [
          Offset.zero,
          Offset(_imageSize.width, 0),
          _imageSize.bottomRight(Offset.zero),
          Offset(0, _imageSize.height),
        ];
        _loading = false;
      });
      image.dispose();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load the image.')),
      );
      Navigator.of(context).pop();
    }
  }

  void _onPanStart(DragStartDetails details) {
    final pos = details.localPosition;
    var best = -1;
    var bestDist = double.infinity;
    for (var i = 0; i < _corners.length; i++) {
      final screen = _origin + _corners[i] * _scale;
      final dist = (screen - pos).distance;
      if (dist < 44 && dist < bestDist) {
        best = i;
        bestDist = dist;
      }
    }
    _dragIndex = best;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final i = _dragIndex;
    if (i == null) return;
    final img = (details.localPosition - _origin) / _scale;
    setState(() {
      final next = List<Offset>.from(_corners);
      next[i] = Offset(
        img.dx.clamp(0.0, _imageSize.width).toDouble(),
        img.dy.clamp(0.0, _imageSize.height).toDouble(),
      );
      _corners = next;
    });
  }

  void _onPanEnd(DragEndDetails details) => _dragIndex = null;

  Future<void> _apply() async {
    setState(() => _applying = true);
    final result = await AutoCropService.applyPerspective(
      sourcePath: widget.sourcePath,
      targetPath: widget.targetPath,
      quad: [for (final c in _corners) [c.dx, c.dy]],
    );
    if (!mounted) return;
    if (result != null) {
      Navigator.of(context).pop(result);
    } else {
      setState(() => _applying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not apply the correction. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.myAppColors;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Fix perspective', style: TextStyle(fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _loading || _applying ? null : () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: colors.buttonColor),
                  const SizedBox(height: 12),
                  const Text(
                    'Looking for the page…',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            )
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: _applying ? null : _onPanStart,
              onPanUpdate: _applying ? null : _onPanUpdate,
              onPanEnd: _applying ? null : _onPanEnd,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final box = constraints.biggest;
                  final scale = math.min(
                    (box.width - _inset * 2) / _imageSize.width,
                    (box.height - _inset * 2) / _imageSize.height,
                  );
                  final dispW = _imageSize.width * scale;
                  final dispH = _imageSize.height * scale;
                  _scale = scale;
                  _origin = Offset((box.width - dispW) / 2, (box.height - dispH) / 2);
                  final corners = [
                    for (final c in _corners) _origin + c * scale,
                  ];

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: Colors.black),
                      Positioned(
                        left: _origin.dx,
                        top: _origin.dy,
                        width: dispW,
                        height: dispH,
                        child: Image.file(
                          File(widget.sourcePath),
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                        ),
                      ),
                      CustomPaint(
                        painter: _QuadPainter(
                          corners: corners,
                          activeIndex: _dragIndex,
                          maskColor: Colors.black.withValues(alpha: 0.55),
                          handleColor: colors.buttonColor,
                          handleFill: Colors.white,
                        ),
                      ),
                      Positioned(
                        top: 18,
                        left: 24,
                        right: 24,
                        child: Text(
                          'Drag the corner dots onto the document corners',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12.5,
                            shadows: const [
                              Shadow(color: Colors.black54, blurRadius: 6),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _loading || _applying
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.buttonColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _loading || _applying ? null : _apply,
                  child: _applying
                      ? SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Apply'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuadPainter extends CustomPainter {
  final List<Offset> corners;
  final int? activeIndex;
  final Color maskColor;
  final Color handleColor;
  final Color handleFill;

  const _QuadPainter({
    required this.corners,
    required this.activeIndex,
    required this.maskColor,
    required this.handleColor,
    required this.handleFill,
  });

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
  }

  @override
  bool shouldRepaint(covariant _QuadPainter oldDelegate) =>
      oldDelegate.corners != corners || oldDelegate.activeIndex != activeIndex;
}