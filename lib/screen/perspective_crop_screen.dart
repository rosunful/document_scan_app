import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/auto_crop_service.dart';
import '../theme/app_theme.dart';
import '../widgets/crop_magnifier.dart';
import '../widgets/quad_overlay.dart';

/// Pop result meaning the user backed out of cropping entirely and wants to
/// return to the camera for a fresh session (the caller discards the scan).
const String kBackToCamera = 'backToCamera';

/// Lets the user drag the document's four corners to fix perspective. The
/// result is written to [targetPath] with OpenCV's warpPerspective and
/// returned via pop when Apply is tapped.
///
/// When [initialCorners] is provided (normalized 0..1, TL/TR/BR/BL — e.g. a
/// quad auto-detected by the scanner), the crop line starts over the document
/// instead of spanning the full image.
class PerspectiveCropScreen extends StatefulWidget {
  final String sourcePath;
  final String targetPath;
  final List<Offset>? initialCorners;

  const PerspectiveCropScreen({
    super.key,
    required this.sourcePath,
    required this.targetPath,
    this.initialCorners,
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
  Offset? _dragLocal;

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
        // Start from an auto-detected quad when one was supplied, otherwise
        // fall back to the whole image and let the user drag each corner.
        final initial = widget.initialCorners;
        _corners = initial == null || initial.length != 4
            ? [
                Offset.zero,
                Offset(_imageSize.width, 0),
                _imageSize.bottomRight(Offset.zero),
                Offset(0, _imageSize.height),
              ]
            : [
                for (final c in initial)
                  Offset(c.dx * _imageSize.width, c.dy * _imageSize.height),
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
    // Corners 0–3, then mid-edge handles 4–7 (edge i between corners i and i+1).
    for (var i = 0; i < 8; i++) {
      final screen = i < 4
          ? _origin + _corners[i] * _scale
          : (_origin +
                    _corners[i - 4] * _scale +
                    _origin +
                    _corners[(i - 4 + 1) % 4] * _scale) /
                2;
      final dist = (screen - pos).distance;
      if (dist < 44 && dist < bestDist) {
        best = i;
        bestDist = dist;
      }
    }
    _dragIndex = best;
  }

  Offset _clampToImage(Offset p) => Offset(
    p.dx.clamp(0.0, _imageSize.width).toDouble(),
    p.dy.clamp(0.0, _imageSize.height).toDouble(),
  );

  void _onPanUpdate(DragUpdateDetails details) {
    final i = _dragIndex;
    if (i == null) return;
    final img = (details.localPosition - _origin) / _scale;
    setState(() {
      _dragLocal = details.localPosition;
      final next = List<Offset>.from(_corners);
      if (i < 4) {
        // Corner drag: that corner follows the finger.
        next[i] = _clampToImage(img);
      } else {
        // Mid-edge drag: the whole edge moves — both adjacent corners follow
        // the drag delta (CamScanner-style expand/contract).
        final a = i - 4;
        final b = (a + 1) % 4;
        final mid = (_corners[a] + _corners[b]) / 2;
        final delta = img - mid;
        next[a] = _clampToImage(_corners[a] + delta);
        next[b] = _clampToImage(_corners[b] + delta);
      }
      _corners = next;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    _dragIndex = null;
    _dragLocal = null;
  }

  /// The image + crop-quad paint, laid out at the full preview rect. Used by the
  /// main view; the zoom loupe magnifies only [_buildPreviewImage] so the crop
  /// chrome stays thin.
  Widget _buildPreviewContent(List<Offset> screenCorners) {
    final colors = context.myAppColors;
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildPreviewImage(),
        CustomPaint(
          painter: QuadOverlayPainter(
            corners: screenCorners,
            activeIndex: _dragIndex,
            maskColor: Colors.black.withValues(alpha: 0.55),
            handleColor: colors.buttonColor,
            handleFill: Colors.white,
          ),
        ),
      ],
    );
  }

  /// The page image only, laid out at the full preview rect.
  Widget _buildPreviewImage() {
    return Positioned(
      left: _origin.dx,
      top: _origin.dy,
      width: _imageSize.width * _scale,
      height: _imageSize.height * _scale,
      child: Image.file(
        File(widget.sourcePath),
        fit: BoxFit.fill,
        gaplessPlayback: true,
      ),
    );
  }

  Future<void> _apply() async {
    setState(() => _applying = true);
    final result = await AutoCropService.applyPerspective(
      sourcePath: widget.sourcePath,
      targetPath: widget.targetPath,
      quad: [
        for (final c in _corners) [c.dx, c.dy],
      ],
    );
    if (!mounted) return;
    if (result != null) {
      Navigator.of(context).pop(result);
    } else {
      setState(() => _applying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not apply the correction. Try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.myAppColors;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_loading && !_applying) {
          Navigator.of(context).pop(kBackToCamera);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Fix perspective', style: TextStyle(fontSize: 16)),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: _loading || _applying
                ? null
                : () => Navigator.of(context).pop(kBackToCamera),
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
                    _origin = Offset(
                      (box.width - dispW) / 2,
                      (box.height - dispH) / 2,
                    );
                    final corners = [
                      for (final c in _corners) _origin + c * scale,
                    ];

                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(color: Colors.black),
                        _buildPreviewContent(corners),
                        Positioned(
                          top: 18,
                          left: 24,
                          right: 24,
                          child: Text(
                            'Drag the dots or edges onto the document',
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
                        if (_dragIndex != null && _dragLocal != null)
                          CropMagnifier(
                            previewSize: box,
                            dragLocal: _dragLocal!,
                            imageChild: _buildPreviewImage(),
                            overlay: CustomPaint(
                              painter: QuadEdgesPainter(
                                corners: corners,
                                color: colors.buttonColor,
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
                        : () => Navigator.of(context).pop(kBackToCamera),
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
      ),
    );
  }
}
