import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:document_scan/document_scan.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/scan_service.dart';
import '../theme/app_theme.dart';
import 'batch_crop_screen.dart';
import 'camera_pervious_screen.dart';

enum _ScreenState { loading, ready, error }

/// Result of the capture flow. [crops] are the batch-cropped final pages (safe
/// to feed PDF/OCR flows), and [origins] are the untouched raw captures — kept
/// index-aligned so the preview screen can re-crop a page back from the true
/// original photo when a previous crop went too far. The receiver of this
/// result owns cleanup of every file.
class ScanPageSet {
  final List<String> origins;
  final List<String> crops;

  const ScanPageSet({required this.origins, required this.crops});
}

/// Custom document-capture camera. Every captured photo is collected raw into
/// a single group — no per-photo crop or enhancement — and the crop review runs
/// only when the user taps Done. Pops with a [ScanPageSet], or `null` if they
/// cancel without capturing anything.
class CustomCameraScreen extends StatefulWidget {
  const CustomCameraScreen({super.key});

  @override
  State<CustomCameraScreen> createState() => _CustomCameraScreenState();
}

class _CustomCameraScreenState extends State<CustomCameraScreen>
    with WidgetsBindingObserver {
  final ImagePicker _picker = ImagePicker();

  final DocumentDetector _detector = DocumentDetector();

  CameraController? _controller;
  _ScreenState _state = _ScreenState.loading;
  String _errorMessage = '';
  bool _torchOn = false;
  bool _isCapturing = false;
  bool _processing = false;
  final List<String> _capturedPages = [];
  final ScrollController _thumbnailsController = ScrollController();

  // Thumbnail strip navigation: arrows page through the strip five thumbnails
  // at a time; finger swiping still works.
  static const int _thumbnailsPerPage = 5;
  static const double _thumbnailExtent = 52; // 44 wide + 8 right padding
  bool _thumbnailsCanPrev = false;
  bool _thumbnailsCanNext = false;

  // Realtime detection pipeline: the camera's image stream is drained by
  // detectStream, which emits a DetectionEvent per handled frame. Each success
  // draws the smoothed document quad over the live preview.
  StreamController<ScanInput>? _frames;
  StreamSubscription<DetectionEvent>? _detectionSub;
  DocumentCorners? _corners;
  bool _detectionStarted = false;

  // Set while the user is retaking a specific page from the review screen —
  // the next capture replaces that page instead of appending a new one.
  int? _retakeIndex;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _thumbnailsController.addListener(_onThumbnailsScroll);
    _setup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_teardownDetection());
    _thumbnailsController
      ..removeListener(_onThumbnailsScroll)
      ..dispose();
    super.dispose();
  }

  // Release the camera when the app is backgrounded and re-acquire it when
  // it returns, or the OS may kill the session (or leave it locked) while
  // you're away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState appState) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (appState == AppLifecycleState.inactive) {
      unawaited(_teardownDetection());
    } else if (appState == AppLifecycleState.resumed) {
      _setup();
    }
  }

  Future<void> _setup() async {
    setState(() => _state = _ScreenState.loading);
    try {
      final cameras = await CameraService.loadCameras();
      final camera = CameraService.pickRearCamera(cameras);
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        // The detector feeds on raw frames from the image stream: YUV420 on
        // Android, BGRA on iOS. Stills (takePicture) are unaffected by this —
        // they always come back as a compressed JPEG file.
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _state = _ScreenState.ready;
      });
      await _startDetection(controller);
    } on CameraServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _state = _ScreenState.error;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Could not open the camera. Check that permission is granted.';
        _state = _ScreenState.error;
      });
    }
  }

  /// Wires the camera's image stream into [DocumentDetector.detectStream] with
  /// a stabilizer so the on-screen quad doesn't jitter. Detects native corners
  /// at ~10 fps; frames in between are dropped by the detector under backpressure.
  Future<void> _startDetection(CameraController controller) async {
    if (_detectionStarted) return;
    _detectionStarted = true;
    final frames = StreamController<ScanInput>();
    _frames = frames;

    _detectionSub = _detector
        .detectStream(
          frames.stream,
          stabilize: CornerStabilizer(),
          minInterval: const Duration(milliseconds: 100),
          sensitivity: DetectionSensitivity.lenient,
        )
        .listen(_onDetectionEvent);

    // sensorOrientation is the clockwise rotation (degrees) to bring the frame
    // upright. On Android (YUV420) the native side needs it; on iOS the BGRA
    // path is already preview-oriented, so 0 is correct there.
    final rotation = Platform.isIOS
        ? 0
        : controller.description.sensorOrientation;

    try {
      await controller.startImageStream((image) {
        if (!mounted || frames.isClosed || _isCapturing) return;
        final input = _toScanInput(image, rotation);
        if (input != null) frames.add(input);
      });
    } catch (_) {
      // startImageStream unsupported on this platform — live detection is a
      // nice-to-have; the manual shutter still works without it.
      _detectionSub?.cancel();
      _detectionSub = null;
      await _frames?.close();
      _frames = null;
    }
  }

  Future<void> _teardownDetection() async {
    final controller = _controller;
    _detectionStarted = false;
    await _detectionSub?.cancel();
    _detectionSub = null;
    await _frames?.close();
    _frames = null;
    try {
      if (controller != null && controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {
      // Ignore — the controller may already be torn down.
    }
    await controller?.dispose();
    if (mounted) {
      setState(() {
        _controller = null;
        _corners = null;
      });
    }
  }

  // Converts a CameraImage to a ScanInput.bgraFrame (iOS) / yuvFrame (Android).
  ScanInput? _toScanInput(CameraImage image, int rotation) {
    if (image.planes.isEmpty) return null;

    if (image.format.group == ImageFormatGroup.bgra8888) {
      final plane = image.planes.first;
      return ScanInput.bgraFrame(
        width: image.width,
        height: image.height,
        rotation: rotation,
        bytes: plane.bytes,
        bytesPerRow: plane.bytesPerRow,
      );
    }

    // YUV420 (Android): three planes, each with its own row stride.
    if (image.planes.length < 3) return null;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    return ScanInput.yuvFrame(
      width: image.width,
      height: image.height,
      rotation: rotation,
      yBytes: yPlane.bytes,
      uBytes: uPlane.bytes,
      vBytes: vPlane.bytes,
      yRowStride: yPlane.bytesPerRow,
      uvRowStride: uPlane.bytesPerRow,
      uvPixelStride: uPlane.bytesPerPixel ?? 1,
    );
  }

  void _onDetectionEvent(DetectionEvent event) {
    if (!mounted || _isCapturing) return;
    switch (event) {
      case DetectionSuccess(:final corners):
        if (_corners != corners) setState(() => _corners = corners);
      case DetectionEmpty():
        if (_corners != null) setState(() => _corners = null);
      case DetectionSkipped():
        break; // normal backpressure — ignore
      case DetectionError():
        break; // keep the last quad; a transient frame error isn't fatal
    }
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null) return;
    final next = !_torchOn;
    try {
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      setState(() => _torchOn = next);
    } catch (_) {
      // Some devices/emulators don't support torch mode — fail quietly.
    }
  }

  /// Status line under the preview, driven by capture phase and detection.
  String get _statusMessage {
    if (_processing) return 'Processing pages…';
    if (_retakeIndex != null) {
      return 'Retaking page ${_retakeIndex! + 1} — capture to replace it';
    }
    if (_isCapturing) return 'Scanning…';
    if (_corners == null) {
      return _capturedPages.isEmpty
          ? 'Align document in frame'
          : '${_capturedPages.length} page${_capturedPages.length == 1 ? '' : 's'} captured';
    }
    return 'Document detected';
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isCapturing) {
      return;
    }
    if (_processing) return;
    setState(() => _isCapturing = true);
    try {
      final file = await controller.takePicture();

      if (!mounted) {
        _deleteTempFile(file.path);
        return;
      }

      // Collect the raw still into the group. Cropping/enhancement happens
      // later, on Done, for the whole batch at once.
      setState(() {
        final retakeIndex = _retakeIndex;
        if (retakeIndex != null) {
          final index = retakeIndex.clamp(0, _capturedPages.length);
          if (index < _capturedPages.length) {
            _deleteTempFile(_capturedPages[index]);
          }
          _capturedPages.insert(index, file.path);
          _retakeIndex = null;
        } else {
          _capturedPages.add(file.path);
        }
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not capture the photo. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  /// Best-effort removal of a temp file (captured still or auto-crop) that
  /// didn't make it into the page list.
  void _deleteTempFile(String? path) {
    if (path == null) return;
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // Best-effort cleanup.
    }
  }

  /// Opens the gallery and adds the picked photo to the capture group. Photos
  /// are collected raw here and go through the same crop review as camera
  /// shots when Done is tapped — no immediate cropping or enhancement.
  Future<void> _pickFromGallery() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );
      if (picked == null || !mounted) return; // user cancelled the picker
      setState(() => _capturedPages.add(picked.path));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not access your photos.')),
        );
      }
    }
  }

  void _removePage(int index) => setState(() => _capturedPages.removeAt(index));

  Future<void> _openPageReview(int index) async {
    final result = await Navigator.of(context).push<ReviewResult>(
      MaterialPageRoute(
        builder: (_) => PageReviewScreen(
          imagePaths: List.of(_capturedPages),
          initialIndex: index,
        ),
        fullscreenDialog: true,
      ),
    );
    if (result == null || !mounted) return;

    setState(() {
      switch (result.type) {
        case ReviewResultType.retake:
          _capturedPages.removeAt(result.index);
          _retakeIndex = result.index;
          break;
        case ReviewResultType.delete:
          _capturedPages.removeAt(result.index);
          break;
      }
    });
  }

  void _reorderPages(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final page = _capturedPages.removeAt(oldIndex);
      _capturedPages.insert(newIndex, page);
    });
  }

  void _onThumbnailsScroll() {
    if (!_thumbnailsController.hasClients) return;
    final position = _thumbnailsController.position;
    final canPrev = position.pixels > 0.01;
    final canNext = position.pixels < position.maxScrollExtent - 0.01;
    if (canPrev == _thumbnailsCanPrev && canNext == _thumbnailsCanNext) return;
    setState(() {
      _thumbnailsCanPrev = canPrev;
      _thumbnailsCanNext = canNext;
    });
  }

  /// Scrolls the thumbnail strip one page of [_thumbnailsPerPage] items.
  void _pageThumbnails(bool forward) {
    if (!_thumbnailsController.hasClients) return;
    final position = _thumbnailsController.position;
    final delta = _thumbnailExtent * _thumbnailsPerPage;
    final target = forward
        ? (position.pixels + delta).clamp(0.0, position.maxScrollExtent)
        : (position.pixels - delta).clamp(0.0, position.maxScrollExtent);
    _thumbnailsController.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  /// Runs the batch crop review for the captured pages. Every page shows in
  /// the paged [BatchCropScreen] (swipe/tap dots to switch, drag corners,
  /// Apply crops and advances immediately, Apply All skips the review). A
  /// cancelled review (`null`) keeps the raw collection intact and returns to
  /// the camera; completing it pops a [ScanPageSet] with the processed pages
  /// and the untouched raws (kept so the preview screen can re-crop a page
  /// back from the true original capture).
  Future<void> _finish() async {
    final pages = List<String>.from(_capturedPages);
    if (pages.isEmpty || _processing) return;

    setState(() => _processing = true);
    List<String>? processed;
    try {
      processed = await Navigator.of(context).push<List<String>>(
        MaterialPageRoute(builder: (_) => BatchCropScreen(sourcePaths: pages)),
      );
      if (!mounted) return;
    } finally {
      if (mounted) setState(() => _processing = false);
    }

    if (processed == null) return; // cancelled — keep the raw group
    final origins = List<String>.from(pages);
    _capturedPages
      ..clear()
      ..addAll(processed);
    if (mounted) {
      Navigator.of(
        context,
      ).pop(ScanPageSet(origins: origins, crops: processed));
    }
  }

  void _cancel() {
    if (_capturedPages.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(
      ScanPageSet(
        origins: List<String>.from(_capturedPages),
        crops: List<String>.from(_capturedPages),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.myAppColors;

    // Keep the thumbnail chevrons in sync after every layout — the scroll
    // listener alone only fires once the user drags the strip, leaving the
    // arrows dormant until then.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onThumbnailsScroll();
    });

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        backgroundColor: colors.backgroundColor,
        body: SafeArea(
          child: switch (_state) {
            _ScreenState.loading => const Center(
              child: CircularProgressIndicator(),
            ),
            _ScreenState.error => _buildError(colors),
            _ScreenState.ready => _buildCamera(colors),
          },
        ),
      ),
    );
  }

  Widget _buildError(CustomAppColors colors) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.no_photography_rounded,
            color: colors.descriptionColor,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.headingTextColor, fontSize: 15),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: colors.descriptionColor),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.buttonColor,
                  foregroundColor: Colors.white,
                ),
                onPressed: _setup,
                child: const Text('Try Again'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCamera(CustomAppColors colors) {
    final controller = _controller!;

    return Column(
      children: [
        // Top bar: close, title, flash toggle.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              _RoundIconButton(
                icon: Icons.close_rounded,
                onTap: _cancel,
                colors: colors,
              ),
              Expanded(
                child: Text(
                  'Scan Document',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.headingTextColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _RoundIconButton(
                icon: _torchOn
                    ? Icons.flash_on_rounded
                    : Icons.flash_off_rounded,
                onTap: _toggleTorch,
                colors: colors,
              ),
            ],
          ),
        ),

        // Larger live preview — fills the flexible space, with corner guides.
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Center(
              child: FractionallySizedBox(
                widthFactor: 1,
                heightFactor: 0.92,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: Colors.black),
                      _BoxedCameraPreview(
                        controller: controller,
                        corners: _corners,
                        overlayColor: colors.buttonColor,
                      ),
                      const _CornerGuides(),
                      if (_isCapturing) Container(color: Colors.black26),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // Status text (centered) + captured-page thumbnails.
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 14, 0, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.descriptionColor, fontSize: 13),
              ),
              if (_capturedPages.isNotEmpty) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      _RoundIconButton(
                        icon: Icons.chevron_left_rounded,
                        onTap: _thumbnailsCanPrev
                            ? () => _pageThumbnails(false)
                            : null,
                        colors: colors,
                        size: 36,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: 64,
                          child: Scrollbar(
                            controller: _thumbnailsController,
                            thumbVisibility: true,
                            scrollbarOrientation: ScrollbarOrientation.bottom,
                            thickness: 4,
                            radius: const Radius.circular(2),
                            child: ReorderableListView.builder(
                              scrollDirection: Axis.horizontal,
                              scrollController: _thumbnailsController,
                              buildDefaultDragHandles: false,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              onReorder: _reorderPages,
                              itemCount: _capturedPages.length,
                              itemBuilder: (context, i) {
                                final path = _capturedPages[i];
                                return ReorderableDragStartListener(
                                  key: ValueKey(path),
                                  index: i,
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: _PageThumbnail(
                                      path: path,
                                      onTap: () => _openPageReview(i),
                                      onRemove: () => _removePage(i),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _RoundIconButton(
                        icon: Icons.chevron_right_rounded,
                        onTap: _thumbnailsCanNext
                            ? () => _pageThumbnails(true)
                            : null,
                        colors: colors,
                        size: 36,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),

        // Bottom controls: Done, shutter, gallery import.
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SizedBox(
                width: 56,
                child: _capturedPages.isNotEmpty
                    ? TextButton(
                        onPressed: _processing ? null : _finish,
                        child: Text(
                          'Done',
                          style: TextStyle(
                            color: colors.buttonColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              GestureDetector(
                onTap: _isCapturing || _processing ? null : _capture,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colors.buttonColor.withValues(alpha: 0.45),
                      width: 3,
                    ),
                  ),
                  padding: const EdgeInsets.all(5),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isCapturing
                          ? colors.descriptionColor
                          : colors.buttonColor,
                    ),
                  ),
                ),
              ),
              _RoundIconButton(
                icon: Icons.photo_library_rounded,
                onTap: _processing ? null : _pickFromGallery,
                colors: colors,
                size: 48,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Rounded-corner brackets drawn over the preview to guide framing.
class _CornerGuides extends StatelessWidget {
  const _CornerGuides();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: CustomPaint(painter: _CornerGuidesPainter()),
    );
  }
}

class _CornerGuidesPainter extends CustomPainter {
  const _CornerGuidesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;
    const inset = 16.0;
    const len = 30.0;

    final path = Path()
      // top-left
      ..moveTo(inset, inset + len)
      ..lineTo(inset, inset)
      ..lineTo(inset + len, inset)
      // top-right
      ..moveTo(w - inset - len, inset)
      ..lineTo(w - inset, inset)
      ..lineTo(w - inset, inset + len)
      // bottom-right
      ..moveTo(w - inset, h - inset - len)
      ..lineTo(w - inset, h - inset)
      ..lineTo(w - inset - len, h - inset)
      // bottom-left
      ..moveTo(inset + len, h - inset)
      ..lineTo(inset, h - inset)
      ..lineTo(inset, h - inset - len);

    canvas.drawPath(path, paint);

    final flash = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final inner = Offset(w / 2, h / 2);
    final radius = math.min(w, h) * 0.42;
    canvas.drawCircle(inner, radius, flash);
    canvas.drawLine(
      inner.translate(-radius, 0),
      inner.translate(radius, 0),
      flash..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Fills its bounding box with the camera feed (cropping to fit) rather
/// than letterboxing it, whatever size that box is.
class _BoxedCameraPreview extends StatelessWidget {
  final CameraController controller;
  final DocumentCorners? corners;
  final Color overlayColor;

  const _BoxedCameraPreview({
    required this.controller,
    this.corners,
    required this.overlayColor,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxAspect = constraints.maxWidth / constraints.maxHeight;
        var scale = boxAspect * controller.value.aspectRatio;
        if (scale < 1) scale = 1 / scale;
        return Transform.scale(
          scale: scale,
          child: Center(
            child: CameraPreview(
              controller,
              child: CustomPaint(
                painter: _DetectionOverlayPainter(corners, overlayColor),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Draws the detected document quad over the camera preview. The corners are
/// normalized 0..1 over the upright preview, so `corner * size` maps directly
/// onto the widget (which sits inside the same scale/crop as the feed).
class _DetectionOverlayPainter extends CustomPainter {
  _DetectionOverlayPainter(this.corners, this.color)
    : _fill = Paint()
        ..color = color.withValues(alpha: 0.18)
        ..style = PaintingStyle.fill,
      _stroke = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
      _corner = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

  final DocumentCorners? corners;
  final Color color;
  final Paint _fill;
  final Paint _stroke;
  final Paint _corner;

  @override
  void paint(Canvas canvas, Size size) {
    final c = corners;
    if (c == null) return;

    final tl = Offset(c.topLeft.x * size.width, c.topLeft.y * size.height);
    final tr = Offset(c.topRight.x * size.width, c.topRight.y * size.height);
    final br = Offset(
      c.bottomRight.x * size.width,
      c.bottomRight.y * size.height,
    );
    final bl = Offset(
      c.bottomLeft.x * size.width,
      c.bottomLeft.y * size.height,
    );

    final path = Path()
      ..moveTo(tl.dx, tl.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(br.dx, br.dy)
      ..lineTo(bl.dx, bl.dy)
      ..close();

    canvas.drawPath(path, _fill);
    canvas.drawPath(path, _stroke);

    const radius = 6.0;
    for (final p in [tl, tr, br, bl]) {
      canvas.drawCircle(p, radius, _corner);
    }
  }

  @override
  bool shouldRepaint(covariant _DetectionOverlayPainter oldDelegate) =>
      oldDelegate.corners != corners || oldDelegate.color != color;
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final CustomAppColors colors;
  final double size;

  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    required this.colors,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? colors.cardColor : colors.borderColor,
          border: Border.all(color: colors.borderColor),
        ),
        child: Icon(
          icon,
          color: enabled ? colors.headingTextColor : colors.descriptionColor,
          size: size * 0.48,
        ),
      ),
    );
  }
}

class _PageThumbnail extends StatelessWidget {
  final String path;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _PageThumbnail({
    required this.path,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(path),
              width: 44,
              height: 56,
              fit: BoxFit.cover,
            ),
          ),
        ),
        Positioned(
          top: 0,
          right: -6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 18,
              height: 18,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black87,
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 12,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// import 'dart:io';
// import 'package:camera/camera.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:image_cropper/image_cropper.dart';
// import 'package:image_picker/image_picker.dart';
// import '../services/scan_service.dart';
// import '../theme/app_theme.dart';

// enum _ScreenState { loading, ready, error }

// /// Custom document-capture camera. Pops with a `List<String>` of captured
// /// page file paths when the user taps Done, or `null` if they cancel
// /// without capturing anything.
// class CustomCameraScreen extends StatefulWidget {
//   const CustomCameraScreen({super.key});

//   @override
//   State<CustomCameraScreen> createState() => _CustomCameraScreenState();
// }

// class _CustomCameraScreenState extends State<CustomCameraScreen> with WidgetsBindingObserver {
//   final ImagePicker _picker = ImagePicker();

//   CameraController? _controller;
//   _ScreenState _state = _ScreenState.loading;
//   String _errorMessage = '';
//   bool _torchOn = false;
//   bool _isCapturing = false;
//   final List<String> _capturedPages = [];

//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addObserver(this);
//     _setup();
//   }

//   @override
//   void dispose() {
//     WidgetsBinding.instance.removeObserver(this);
//     _controller?.dispose();
//     super.dispose();
//   }

//   // Release the camera when the app is backgrounded and re-acquire it when
//   // it returns, or the OS may kill the session (or leave it locked) while
//   // you're away.
//   @override
//   void didChangeAppLifecycleState(AppLifecycleState appState) {
//     final controller = _controller;
//     if (controller == null || !controller.value.isInitialized) return;
//     if (appState == AppLifecycleState.inactive) {
//       controller.dispose();
//     } else if (appState == AppLifecycleState.resumed) {
//       _setup();
//     }
//   }

//   Future<void> _setup() async {
//     setState(() => _state = _ScreenState.loading);
//     try {
//       final cameras = await CameraService.loadCameras();
//       final camera = CameraService.pickRearCamera(cameras);
//       final controller = CameraController(
//         camera,
//         ResolutionPreset.high,
//         enableAudio: false,
//         imageFormatGroup: ImageFormatGroup.jpeg,
//       );
//       await controller.initialize();
//       if (!mounted) return;
//       setState(() {
//         _controller = controller;
//         _state = _ScreenState.ready;
//       });
//     } on CameraServiceException catch (e) {
//       if (!mounted) return;
//       setState(() {
//         _errorMessage = e.message;
//         _state = _ScreenState.error;
//       });
//     } catch (_) {
//       if (!mounted) return;
//       setState(() {
//         _errorMessage = 'Could not open the camera. Check that permission is granted.';
//         _state = _ScreenState.error;
//       });
//     }
//   }

//   Future<void> _toggleTorch() async {
//     final controller = _controller;
//     if (controller == null) return;
//     final next = !_torchOn;
//     try {
//       await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
//       setState(() => _torchOn = next);
//     } catch (_) {
//       // Some devices/emulators don't support torch mode — fail quietly.
//     }
//   }

//   Future<void> _capture() async {
//     final controller = _controller;
//     if (controller == null || !controller.value.isInitialized || _isCapturing) return;
//     setState(() => _isCapturing = true);
//     try {
//       final file = await controller.takePicture();
//       setState(() => _capturedPages.add(file.path));
//     } catch (_) {
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(content: Text('Could not capture the photo. Try again.')),
//         );
//       }
//     } finally {
//       if (mounted) setState(() => _isCapturing = false);
//     }
//   }

//   /// Opens the gallery, then hands the picked photo straight to the crop
//   /// screen. Image enhancement (B&W, contrast, etc.) is a later step —
//   /// cropping is all we do here for now.
//   Future<void> _pickFromGallery() async {
//     final colors = context.myAppColors;
//     try {
//       final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
//       if (picked == null || !mounted) return; // user cancelled the picker

//       final cropped = await ImageCropper().cropImage(
//         sourcePath: picked.path,
//         compressQuality: 90,
//         uiSettings: [
//           AndroidUiSettings(
//             toolbarTitle: 'Crop Document',
//             toolbarColor: colors.cardColor,
//             toolbarWidgetColor: colors.headingTextColor,
//             activeControlsWidgetColor: colors.buttonColor,
//             backgroundColor: colors.backgroundColor,
//             lockAspectRatio: false,
//           ),
//           IOSUiSettings(
//             title: 'Crop Document',
//             doneButtonTitle: 'Done',
//             cancelButtonTitle: 'Cancel',
//             aspectRatioLockEnabled: false,
//           ),
//         ],
//       );

//       if (cropped == null || !mounted) return; // user cancelled the crop
//       setState(() => _capturedPages.add(cropped.path));
//     } on PlatformException catch (e) {
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text(e.message ?? 'Could not access your photos.')),
//         );
//       }
//     }
//   }

//   void _removePage(int index) => setState(() => _capturedPages.removeAt(index));

//   void _finish() => Navigator.of(context).pop(List<String>.from(_capturedPages));

//   void _cancel() {
//     Navigator.of(context).pop(_capturedPages.isEmpty ? null : _capturedPages);
//   }

//   @override
//   Widget build(BuildContext context) {
//     final colors = context.myAppColors;

//     return PopScope(
//       canPop: false,
//       onPopInvoked: (didPop) {
//         if (!didPop) _cancel();
//       },
//       child: Scaffold(
//         backgroundColor: colors.backgroundColor,
//         body: SafeArea(
//           child: switch (_state) {
//             _ScreenState.loading => const Center(child: CircularProgressIndicator()),
//             _ScreenState.error => _buildError(colors),
//             _ScreenState.ready => _buildCamera(colors),
//           },
//         ),
//       ),
//     );
//   }

//   Widget _buildError(CustomAppColors colors) {
//     return Padding(
//       padding: const EdgeInsets.all(24),
//       child: Column(
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           Icon(Icons.no_photography_rounded, color: colors.descriptionColor, size: 48),
//           const SizedBox(height: 16),
//           Text(
//             _errorMessage,
//             textAlign: TextAlign.center,
//             style: TextStyle(color: colors.headingTextColor, fontSize: 15),
//           ),
//           const SizedBox(height: 20),
//           Row(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [
//               TextButton(
//                 onPressed: () => Navigator.of(context).pop(),
//                 child: Text('Cancel', style: TextStyle(color: colors.descriptionColor)),
//               ),
//               const SizedBox(width: 12),
//               ElevatedButton(
//                 style: ElevatedButton.styleFrom(backgroundColor: colors.buttonColor, foregroundColor: Colors.white),
//                 onPressed: _setup,
//                 child: const Text('Try Again'),
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildCamera(CustomAppColors colors) {
//     final controller = _controller!;

//     return Column(
//       children: [
//         // Top bar: close, title, flash toggle.
//         Padding(
//           padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
//           child: Row(
//             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//             children: [
//               _RoundIconButton(icon: Icons.close_rounded, onTap: _cancel, colors: colors),
//               // Text(
//               //   'Scan Document',
//               //   style: TextStyle(color: colors.headingTextColor, fontWeight: FontWeight.w700, fontSize: 15),
//               // ),
//               _RoundIconButton(
//                 icon: _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
//                 onTap: _toggleTorch,
//                 colors: colors,
//               ),
//             ],
//           ),
//         ),
//         const SizedBox(height: 60,),

//         // Boxed live preview — intentionally not full screen.
//         Padding(
//           padding: const EdgeInsets.symmetric(horizontal: 32),
//           child: AspectRatio(
//             aspectRatio: 3 / 4,
//             child: ClipRRect(
//               borderRadius: BorderRadius.circular(20),
//               child: Stack(
//                 fit: StackFit.expand,
//                 children: [
//                   Container(color: Colors.black),
//                   _BoxedCameraPreview(controller: controller),
//                   Center(
//                     child: FractionallySizedBox(
//                       widthFactor: 0.86,
//                       heightFactor: 0.86,
//                       // child: DecoratedBox(
//                       //   decoration: BoxDecoration(
//                       //     border: Border.all(color: Colors.white70, width: 2),
//                       //     borderRadius: BorderRadius.circular(12),
//                       //   ),
//                       // ),
//                     ),
//                   ),
//                   if (_isCapturing) Container(color: Colors.black26),
//                 ],
//               ),
//             ),
//           ),
//         ),

//         // Everything below the preview shares the remaining space.
//         Expanded(
//           child: Column(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [
//               Text(
//                 _capturedPages.isEmpty
//                     ? 'Align document in frame'
//                     : '${_capturedPages.length} page${_capturedPages.length == 1 ? '' : 's'} captured',
//                 style: TextStyle(color: colors.descriptionColor, fontSize: 12.5),
//               ),
//               if (_capturedPages.isNotEmpty) ...[
//                 const SizedBox(height: 12),
//                 SizedBox(
//                   height: 56,
//                   child: ListView.separated(
//                     scrollDirection: Axis.horizontal,
//                     padding: const EdgeInsets.symmetric(horizontal: 24),
//                     itemCount: _capturedPages.length,
//                     separatorBuilder: (_, __) => const SizedBox(width: 8),
//                     itemBuilder: (context, i) => _PageThumbnail(
//                       path: _capturedPages[i],
//                       onRemove: () => _removePage(i),
//                     ),
//                   ),
//                 ),
//               ],
//             ],
//           ),
//         ),

//         // Bottom controls: Done, shutter, gallery import.
//         Padding(
//           padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
//           child: Row(
//             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//             children: [
//               SizedBox(
//                 width: 56,
//                 child: _capturedPages.isNotEmpty
//                     ? TextButton(
//                         onPressed: _finish,
//                         child: Text(
//                           'Done',
//                           style: TextStyle(color: colors.buttonColor, fontWeight: FontWeight.w700),
//                         ),
//                       )
//                     : const SizedBox.shrink(),
//               ),
//               GestureDetector(
//                 onTap: _isCapturing ? null : _capture,
//                 child: Container(
//                   width: 72,
//                   height: 72,
//                   decoration: BoxDecoration(
//                     shape: BoxShape.circle,
//                     border: Border.all(color: colors.buttonColor, width: 4),
//                   ),
//                   padding: const EdgeInsets.all(4),
//                   child: DecoratedBox(
//                     decoration: BoxDecoration(
//                       shape: BoxShape.circle,
//                       color: _isCapturing ? colors.descriptionColor : colors.buttonColor,
//                     ),
//                   ),
//                 ),
//               ),
//               _RoundIconButton(icon: Icons.photo_library_rounded, onTap: _pickFromGallery, colors: colors, size: 48),
//             ],
//           ),
//         ),
//       ],
//     );
//   }
// }

// /// Fills its bounding box with the camera feed (cropping to fit) rather
// /// than letterboxing it, whatever size that box is.
// class _BoxedCameraPreview extends StatelessWidget {
//   final CameraController controller;

//   const _BoxedCameraPreview({required this.controller});

//   @override
//   Widget build(BuildContext context) {
//     return LayoutBuilder(
//       builder: (context, constraints) {
//         final boxAspect = constraints.maxWidth / constraints.maxHeight;
//         var scale = boxAspect * controller.value.aspectRatio;
//         if (scale < 1) scale = 1 / scale;
//         return Transform.scale(
//           scale: scale,
//           child: Center(child: CameraPreview(controller)),
//         );
//       },
//     );
//   }
// }

// class _RoundIconButton extends StatelessWidget {
//   final IconData icon;
//   final VoidCallback? onTap;
//   final CustomAppColors colors;
//   final double size;

//   const _RoundIconButton({
//     required this.icon,
//     required this.onTap,
//     required this.colors,
//     this.size = 40,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return GestureDetector(
//       onTap: onTap,
//       child: Container(
//         width: size,
//         height: size,
//         decoration: BoxDecoration(
//           shape: BoxShape.circle,
//           color: colors.cardColor,
//           border: Border.all(color: colors.borderColor),
//         ),
//         child: Icon(icon, color: colors.headingTextColor, size: size * 0.48),
//       ),
//     );
//   }
// }

// class _PageThumbnail extends StatelessWidget {
//   final String path;
//   final VoidCallback onRemove;

//   const _PageThumbnail({required this.path, required this.onRemove});

//   @override
//   Widget build(BuildContext context) {
//     return Stack(
//       clipBehavior: Clip.none,
//       children: [
//         ClipRRect(
//           borderRadius: BorderRadius.circular(8),
//           child: Image.file(File(path), width: 44, height: 56, fit: BoxFit.cover),
//         ),
//         Positioned(
//           top: -6,
//           right: -6,
//           child: GestureDetector(
//             onTap: onRemove,
//             child: Container(
//               width: 18,
//               height: 18,
//               decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black87),
//               child: const Icon(Icons.close_rounded, size: 12, color: Colors.white),
//             ),
//           ),
//         ),
//       ],
//     );
//   }
// }
