import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../services/auto_crop_service.dart';
import '../services/document_detection_service.dart';
import '../theme/app_theme.dart';
import '../widgets/crop_magnifier.dart';
import '../widgets/quad_overlay.dart';
import 'perspective_crop_screen.dart' show kBackToCamera;

/// Batch "fix perspective" flow for a group of captured pages.
///
/// Every page is shown full-screen with the auto-detected crop line overlaid
/// (nothing is cropped yet, straight warp only — no enhancement). The user can:
/// - swipe (or tap the dots) to switch pages,
/// - drag the four corner handles of any page to adjust its crop line,
/// - tap **Apply** to crop the current page along its line and advance
///   immediately to the next (no intermediate screen),
/// - tap **Apply All** to crop every remaining page with its detected line
///   without reviewing each one.
///
/// Pops with the `List<String>` of processed page paths when everything is
/// applied, or `null` when cancelled (the caller keeps the raw group). Any
/// temp crops written on the way are removed on cancel. When [exitToCamera]
/// is set, cancelling instead pops [kBackToCamera] so the caller can discard
/// the session and reopen the camera.
class BatchCropScreen extends StatefulWidget {
  const BatchCropScreen({
    super.key,
    required this.sourcePaths,
    this.exitToCamera = false,
  });

  final List<String> sourcePaths;

  /// Cancel pops [kBackToCamera] instead of `null` (preview → camera exit).
  final bool exitToCamera;

  @override
  State<BatchCropScreen> createState() => _BatchCropScreenState();
}

class _BatchCropScreenState extends State<BatchCropScreen> {
  final DocumentDetectionService _detection = DocumentDetectionService();
  final PageController _pageController = PageController();
  late final List<String> _sourcePaths = List.of(widget.sourcePaths);

  // Per-page crop lines (pixel coordinates) and results, keyed by page index.
  late final List<List<Offset>?> _quads = List.filled(
    _sourcePaths.length,
    null,
  );
  late final List<String?> _results = List.filled(_sourcePaths.length, null);

  // Temp files written during this review — cleaned up if the user cancels.
  final List<String> _tempCrops = [];

  int _current = 0;
  bool _applying = false;
  bool _applyingAll = false;

  int get _count => _sourcePaths.length;
  bool get _busy => _applying || _applyingAll;

  @override
  void dispose() {
    _pageController.dispose();
    _detection.dispose();
    super.dispose();
  }

  void _onCorners(int index, List<Offset> corners) {
    if (_quads[index] == corners) return;
    setState(() => _quads[index] = corners);
  }

  Future<String> _derivedCropPath(String tag) async {
    final dir = await getTemporaryDirectory();
    return '${dir.path}/crop_${tag}_${DateTime.now().microsecondsSinceEpoch}.jpg';
  }

  void _deleteTempFile(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // Best-effort cleanup.
    }
  }

  /// Crops page [index] along [quadPixels] (upright pixel coordinates).
  Future<String?> _crop(int index, List<Offset> quadPixels) async {
    final target = await _derivedCropPath('page${index + 1}');
    final result = await AutoCropService.applyPerspective(
      sourcePath: _sourcePaths[index],
      targetPath: target,
      quad: [
        for (final p in quadPixels) [p.dx, p.dy],
      ],
    );
    if (result == null) {
      _deleteTempFile(target);
    } else {
      _tempCrops.add(target);
    }
    return result;
  }

  /// Builds a crop line for a page that has no editor state yet (never
  /// viewed): detects the document and falls back to the full image.
  Future<List<Offset>?> _standaloneQuad(int index) async {
    try {
      final bytes = await File(_sourcePaths[index]).readAsBytes();
      final image = await decodeImageFromList(bytes);
      if (!mounted) {
        image.dispose();
        return null;
      }
      final size = Size(image.width.toDouble(), image.height.toDouble());
      image.dispose();

      final detected = await _detection.detectCorners(_sourcePaths[index]);
      return detected == null
          ? [
              Offset.zero,
              Offset(size.width, 0),
              size.bottomRight(Offset.zero),
              Offset(0, size.height),
            ]
          : [
              for (final p in detected.toList())
                Offset(p.x * size.width, p.y * size.height),
            ];
    } catch (_) {
      return null;
    }
  }

  Future<void> _applyCurrent() async {
    if (_busy || _quads[_current] == null) return;
    setState(() => _applying = true);
    final out = await _crop(_current, _quads[_current]!);
    if (!mounted) return;
    setState(() {
      _applying = false;
      if (out != null) _results[_current] = out;
    });
    if (out == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not apply the correction. Try again.'),
        ),
      );
      return;
    }
    if (_current >= _count - 1) {
      await _complete();
    } else {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _applyAll() async {
    if (_busy) return;
    await _complete();
  }

  /// Finishes the batch: crops every page not yet applied (with its detected
  /// line) and pops the final list. A failure anywhere keeps the review open.
  Future<void> _complete() async {
    setState(() => _applyingAll = true);
    var ok = true;
    for (var i = 0; i < _count && ok; i++) {
      if (_results[i] != null) continue;
      var quad = _quads[i];
      if (quad == null) {
        quad = await _standaloneQuad(i);
        if (quad == null) {
          ok = false;
          break;
        }
      }
      final out = await _crop(i, quad);
      if (out == null) {
        ok = false;
        break;
      }
      _results[i] = out;
    }
    if (!mounted) return;
    if (!ok) {
      setState(() => _applyingAll = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not finish cropping the pages.')),
      );
      return;
    }
    Navigator.of(context).pop(List<String>.from(_results.whereType<String>()));
  }

  void _cancel() {
    if (_busy) return;
    for (final path in _tempCrops) {
      _deleteTempFile(path);
    }
    Navigator.of(context).pop(widget.exitToCamera ? kBackToCamera : null);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.myAppColors;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(colors),
              const SizedBox(height: 4),
              if (_count > 1) _buildDots(colors),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (i) => setState(() => _current = i),
                  itemCount: _count,
                  itemBuilder: (context, i) => _PageCropEditor(
                    sourcePath: _sourcePaths[i],
                    detection: _detection,
                    onCorners: (corners) => _onCorners(i, corners),
                  ),
                ),
              ),
              _buildBottomBar(colors),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(CustomAppColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded),
            color: Colors.white,
            onPressed: _busy ? null : _cancel,
          ),
          Expanded(
            child: Text(
              'Fix perspective',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: _busy ? null : _applyAll,
            icon: _applyingAll
                ? const SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.done_all_rounded, size: 20),
            label: Text(_applyingAll ? 'Applying…' : 'Apply All'),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildDots(CustomAppColors colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Page ${_current + 1} of $_count',
          style: const TextStyle(color: Colors.white70, fontSize: 12.5),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 18,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: _current > _count / 2,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _count; i++)
                  GestureDetector(
                    onTap: _busy
                        ? null
                        : () => _pageController.animateToPage(
                            i,
                            duration: const Duration(milliseconds: 240),
                            curve: Curves.easeOut,
                          ),
                    child: Container(
                      height: 22,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: i == _current ? 18 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: _results[i] != null
                              ? colors.buttonColor
                              : i == _current
                              ? Colors.white
                              : Colors.white38,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar(CustomAppColors colors) {
    return SafeArea(
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
                onPressed: _busy ? null : _cancel,
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
                onPressed: _busy || _quads[_current] == null
                    ? null
                    : _applyCurrent,
                child: _applying
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(_current >= _count - 1 ? 'Apply & Finish' : 'Apply'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single page of the batch review: the full image with a draggable crop
/// line overlaid. Detects its own crop line lazily (native + ONNX fallback).
///
/// Corner dragging only engages when a touch starts on a corner handle (an
/// eagerly-winning recognizer), so a pan anywhere else falls through to the
/// surrounding [PageView] and switches pages instead.
class _PageCropEditor extends StatefulWidget {
  const _PageCropEditor({
    required this.sourcePath,
    required this.detection,
    required this.onCorners,
  });

  final String sourcePath;
  final DocumentDetectionService detection;
  final ValueChanged<List<Offset>> onCorners;

  @override
  State<_PageCropEditor> createState() => _PageCropEditorState();
}

class _PageCropEditorState extends State<_PageCropEditor> {
  static const double _inset = 28;
  static const double _handleHitSize = 44;

  final GlobalKey _boxKey = GlobalKey();

  bool _loading = true;
  bool _failed = false;
  Size _imageSize = Size.zero;
  List<Offset> _corners = const [];

  // Image → screen mapping, recomputed each build and read by the handles.
  double _scale = 1;
  Offset _origin = Offset.zero;

  int? _dragIndex;
  Offset? _dragLocal;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await File(widget.sourcePath).readAsBytes();
      final image = await decodeImageFromList(bytes);
      final size = Size(image.width.toDouble(), image.height.toDouble());
      image.dispose();

      final detected = await widget.detection.detectCorners(widget.sourcePath);
      if (!mounted) return;
      setState(() {
        _imageSize = size;
        _corners = detected == null
            ? [
                Offset.zero,
                Offset(size.width, 0),
                size.bottomRight(Offset.zero),
                Offset(0, size.height),
              ]
            : [
                for (final p in detected.toList())
                  Offset(p.x * size.width, p.y * size.height),
              ];
        _loading = false;
      });
      widget.onCorners(_corners);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  List<Offset> _screenCorners(Size box) {
    final scale = math.min(
      (box.width - _inset * 2) / _imageSize.width,
      (box.height - _inset * 2) / _imageSize.height,
    );
    final dispW = _imageSize.width * scale;
    final dispH = _imageSize.height * scale;
    _scale = scale;
    _origin = Offset((box.width - dispW) / 2, (box.height - dispH) / 2);
    return [for (final c in _corners) _origin + c * scale];
  }

  /// Screen position of handle [i]: corners `0–3`, mid-edge handles `4–7`
  /// (handle 4 + edge sits between corners [edge] and [edge + 1]).
  Offset _screenHandle(int i, List<Offset> screen) {
    if (i < 4) return screen[i];
    final edge = i - 4;
    return (screen[edge] + screen[(edge + 1) % 4]) / 2;
  }

  Offset _clampToImage(Offset p) => Offset(
    p.dx.clamp(0.0, _imageSize.width).toDouble(),
    p.dy.clamp(0.0, _imageSize.height).toDouble(),
  );

  void _onHandleDown(int index, Offset _) {
    setState(() => _dragIndex = index);
  }

  void _onHandleUpdate(Offset globalPosition) {
    final i = _dragIndex;
    if (i == null) return;
    final box = _boxKey.currentContext?.findRenderObject();
    if (box is! RenderBox) return;
    final local = box.globalToLocal(globalPosition);
    final img = (local - _origin) / _scale;
    setState(() {
      _dragLocal = local;
      final next = List<Offset>.from(_corners);
      if (i < 4) {
        // Corner drag: that corner follows the finger.
        next[i] = _clampToImage(img);
      } else {
        // Mid-edge drag: the whole edge moves — both adjacent corners follow
        // the drag delta (CamScanner-style expand/contract).
        final edge = i - 4;
        final a = edge;
        final b = (edge + 1) % 4;
        final mid = (_corners[a] + _corners[b]) / 2;
        final delta = img - mid;
        next[a] = _clampToImage(_corners[a] + delta);
        next[b] = _clampToImage(_corners[b] + delta);
      }
      _corners = next;
    });
  }

  void _onHandleEnd() {
    if (_dragIndex == null) return;
    setState(() {
      _dragIndex = null;
      _dragLocal = null;
    });
    widget.onCorners(_corners);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = constraints.biggest;

        if (_loading || _failed || _imageSize == Size.zero) {
          return Center(
            child: _failed
                ? const Text(
                    'Could not load this image',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  )
                : const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text(
                        'Looking for the page…',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
          );
        }

        final screen = _screenCorners(box);
        final dragLocal = _dragLocal;
        final colors = context.myAppColors;

        return Stack(
          key: _boxKey,
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            Container(color: Colors.black),
            _buildPreviewContent(screen),
            for (var i = 0; i < 8; i++)
              _buildHandle(i, _screenHandle(i, screen), box),
            Positioned(
              top: 18,
              left: 24,
              right: 24,
              child: IgnorePointer(
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
            ),
            if (_dragIndex != null && dragLocal != null)
              CropMagnifier(
                previewSize: box,
                dragLocal: dragLocal,
                imageChild: _buildPreviewImage(),
                overlay: CustomPaint(
                  painter: QuadEdgesPainter(
                    corners: screen,
                    color: colors.buttonColor,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// The image + crop-quad paint, laid out at the full preview rect. Used by
  /// the main view; the zoom loupe magnifies only [_buildPreviewImage] so the
  /// crop chrome stays thin.
  Widget _buildPreviewContent(List<Offset> screen) {
    final colors = context.myAppColors;
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildPreviewImage(),
        CustomPaint(
          painter: QuadOverlayPainter(
            corners: screen,
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
      child: IgnorePointer(
        child: Image.file(
          File(widget.sourcePath),
          fit: BoxFit.fill,
          gaplessPlayback: true,
        ),
      ),
    );
  }

  Widget _buildHandle(int index, Offset screenPos, Size box) {
    final left = (screenPos.dx - _handleHitSize / 2).clamp(
      0.0,
      box.width - _handleHitSize,
    );
    final top = (screenPos.dy - _handleHitSize / 2).clamp(
      0.0,
      box.height - _handleHitSize,
    );

    return Positioned(
      left: left,
      top: top,
      width: _handleHitSize,
      height: _handleHitSize,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          _HandleDragRecognizer:
              GestureRecognizerFactoryWithHandlers<_HandleDragRecognizer>(
                _HandleDragRecognizer.new,
                (instance) {
                  instance
                    ..onDown = ((g) => _onHandleDown(index, g))
                    ..onUpdate = _onHandleUpdate
                    ..onEnd = _onHandleEnd;
                },
              ),
        },
        child: Container(color: Colors.transparent),
      ),
    );
  }
}

/// Drag recognizer for a corner handle. It eagerly claims the pointer on
/// touch-down, so handling a corner always beats the surrounding [PageView]'s
/// swipe recognizer (which is why touching a handle drags the corner while
/// touching anywhere else changes pages).
class _HandleDragRecognizer extends OneSequenceGestureRecognizer {
  void Function(Offset globalPosition)? onDown;
  void Function(Offset globalPosition)? onUpdate;
  VoidCallback? onEnd;

  @override
  void addPointer(PointerDownEvent event) {
    super.addPointer(event);
    resolve(GestureDisposition.accepted);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerDownEvent) {
      onDown?.call(event.position);
    } else if (event is PointerMoveEvent) {
      onUpdate?.call(event.position);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      onEnd?.call();
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) => onEnd?.call();

  @override
  String get debugDescription => 'corner-handle-drag';
}
