import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:provider/provider.dart';

import '../repository/document_repository.dart';
import '../services/enchance_service.dart';
import '../services/enhance_worker.dart';
import '../theme/app_theme.dart';
import '../widgets/enhance_panel.dart';
import 'batch_crop_screen.dart';
import 'camera_scan_preview_screen.dart';
import 'perspective_crop_screen.dart';

class ScanPreviewScreen extends StatefulWidget {
  /// Batch-cropped pages used for the default display.
  final List<String> imagePaths;

  /// Index-aligned untouched raw captures, kept so a page can be re-cropped
  /// back from the true original photo. Falls back to [imagePaths] when the
  /// caller has no raws (e.g. auto-scan).
  final List<String>? originalPaths;

  const ScanPreviewScreen({
    super.key,
    required this.imagePaths,
    this.originalPaths,
  });

  @override
  State<ScanPreviewScreen> createState() => _ScanPreviewScreenState();
}

/// One captured page and everything we've derived from it.
class _PageEntry {
  /// Untouched raw capture — the source for re-cropping.
  final String originalPath;

  /// Batch-crop output — the default display until the user re-crops one page.
  String processedPath;
  String? manualPath; // user's own crop, wins over everything
  String? perspectivePath; // user's perspective fix, beats manual
  EnhanceSettings enhance = const EnhanceSettings();
  EnhancePreviewCache? _enhanceCache;

  final EnhanceWorkerSet enhanceWorkers;

  _PageEntry({
    required this.originalPath,
    required this.processedPath,
    required this.enhanceWorkers,
  });

  String get displayPath => manualPath ?? perspectivePath ?? processedPath;

  /// Debounced enhancer for the current [displayPath]; recreates automatically
  /// when the displayed source changes. Renders through the screen's shared
  /// persistent workers so every slider change reuses the loaded OpenCV lib.
  EnhancePreviewCache get enhanceCache =>
      _enhanceCache ??= EnhancePreviewCache(
        sourcePath: displayPath,
        writer: enhanceWorkers.enhance,
        fastSourceWriter: enhanceWorkers.prep,
      );

  /// Call after [displayPath] changes so the cached preview matches the new
  /// source instead of the old file.
  void resetEnhanceCache() {
    _enhanceCache?.dispose();
    _enhanceCache = null;
  }

  void dispose() {
    _enhanceCache?.dispose();
    _enhanceCache = null;
  }

  List<String> get allPaths => [
    originalPath,
    if (originalPath != processedPath) processedPath,
    ?manualPath,
    ?perspectivePath,
  ];
}

class _ScanPreviewScreenState extends State<ScanPreviewScreen> {
  final PageController _controller = PageController();
  late final List<_PageEntry> _pages;
  final EnhanceWorkerSet _enhanceWorkers = EnhanceWorkerSet();
  int _page = 0;
  bool _saving = false;
  int _savedCount = 0;

  @override
  void initState() {
    super.initState();
    // Warm the workers up front so the OpenCV lib is already loaded by the
    // time the user moves a slider — the first render must be fast too.
    unawaited(_enhanceWorkers.ensureWarm());
    final raws = widget.originalPaths;
    _pages = [
      for (var i = 0; i < widget.imagePaths.length; i++)
        _PageEntry(
          originalPath: raws != null && i < raws.length
              ? raws[i]
              : widget.imagePaths[i],
          processedPath: widget.imagePaths[i],
          enhanceWorkers: _enhanceWorkers,
        ),
    ];
    // Seed the current page's enhance cache with its starting settings so its
    // default (non-original) look is backed by a real render before Save.
    // Other pages seed lazily when swiped to, so opening the screen doesn't
    // burst-render the whole document; Save still flushes every page.
    final first = _pages.first;
    if (!first.enhance.isUntouched) {
      first.enhanceCache.update(first.enhance);
    }
  }

  @override
  void dispose() {
    _enhanceWorkers.dispose();
    _controller.dispose();
    for (final entry in _pages) {
      entry.dispose();
    }
    super.dispose();
  }

  _PageEntry get _current => _pages[_page];

  String _derivedPath(String source, String tag) {
    final file = File(source);
    final name = file.uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    final base = dot == -1 ? name : name.substring(0, dot);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return '${file.parent.path}${Platform.pathSeparator}${base}_${tag}_$stamp.jpg';
  }

  void _deleteQuietly(String? path) {
    if (path == null) return;
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // Best-effort cleanup.
    }
  }

  Future<void> _cropManually() async {
    final colors = context.myAppColors;
    final entry = _current;

    try {
      final cropped = await ImageCropper().cropImage(
        sourcePath: entry.originalPath,
        compressQuality: 92,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Page',
            toolbarColor: colors.cardColor,
            toolbarWidgetColor: colors.headingTextColor,
            activeControlsWidgetColor: colors.buttonColor,
            backgroundColor: colors.backgroundColor,
            lockAspectRatio: false,
          ),
          IOSUiSettings(
            title: 'Crop Page',
            doneButtonTitle: 'Done',
            cancelButtonTitle: 'Cancel',
            aspectRatioLockEnabled: false,
          ),
        ],
      );
      if (cropped == null || !mounted) return;

      setState(() {
        _deleteQuietly(entry.manualPath);
        _deleteQuietly(entry.perspectivePath);
        entry.manualPath = cropped.path;
        entry.perspectivePath = null;
      });
      _refreshEnhance(entry);
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? "Couldn't open the cropper.")),
        );
      }
    }
  }

  Future<void> _cropPerspective() async {
    final entry = _current;
    final target = _derivedPath(entry.originalPath, 'persp');
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => PerspectiveCropScreen(
          sourcePath: entry.originalPath,
          targetPath: target,
        ),
      ),
    );
    if (!mounted) return;
    if (result == kBackToCamera) {
      _exitToCamera();
      return;
    }
    if (result == null) return;

    setState(() {
      _deleteQuietly(entry.manualPath);
      _deleteQuietly(entry.perspectivePath);
      entry.manualPath = null;
      entry.perspectivePath = result;
    });
    _refreshEnhance(entry);
  }

  Future<void> _retake() async {
    final set = await Navigator.of(context).push<ScanPageSet>(
      MaterialPageRoute(builder: (_) => const CustomCameraScreen()),
    );
    if (set == null || set.crops.isEmpty || !mounted) return;

    _PageEntry entryOf(int i) => _PageEntry(
      originalPath: i < set.origins.length ? set.origins[i] : set.crops[i],
      processedPath: set.crops[i],
      enhanceWorkers: _enhanceWorkers,
    );

    final index = _page;
    final old = _pages[index];

    setState(() {
      _pages[index] = entryOf(0);
    });

    // Anything extra they shot during the retake gets appended rather than lost.
    if (set.crops.length > 1) {
      setState(() {
        for (var i = 1; i < set.crops.length; i++) {
          _pages.add(entryOf(i));
        }
      });
    }

    for (final path in old.allPaths) {
      _deleteQuietly(path);
    }
    old.dispose();
  }

  void _discard() {
    for (final entry in _pages) {
      for (final path in entry.allPaths) {
        _deleteQuietly(path);
      }
      entry.dispose();
    }
    Navigator.of(context).pop();
  }

  void _setEnhance(EnhanceSettings settings) {
    setState(() => _current.enhance = settings);
    _current.enhanceCache.update(settings);
  }

  void _resetEnhance() {
    const reset = EnhanceSettings(filter: EnhanceFilter.original);
    setState(() => _current.enhance = reset);
    _current.enhanceCache.update(reset);
  }

  /// Re-points a page's enhancement cache at its current display path and
  /// (re)renders if a filter is active. Used after re-crop / perspective fix.
  void _refreshEnhance(_PageEntry entry) {
    entry.resetEnhanceCache();
    if (!entry.enhance.isUntouched) {
      entry.enhanceCache.update(entry.enhance);
    }
  }

  void _applyEnhanceToAll() {
    final settings = _current.enhance;
    setState(() {
      for (final entry in _pages) {
        entry.enhance = settings;
      }
    });
    for (final entry in _pages) {
      entry.enhanceCache.update(settings);
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Applied to every page')));
  }

  /// Steps back to the crop step: re-opens the batch crop over the raw
  /// captures so the user can fix page boundaries. A non-null result replaces
  /// each page's processed crop; cancelling the crop keeps the preview intact,
  /// while backing out of the crop screen discards the session and reopens
  /// the camera.
  Future<void> _redoCrop() async {
    if (_saving) return;
    final raws = [for (final entry in _pages) entry.originalPath];
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => BatchCropScreen(sourcePaths: raws, exitToCamera: true),
      ),
    );
    if (!mounted) return;
    if (result == kBackToCamera) {
      _exitToCamera();
      return;
    }
    if (result is! List<String>) return;
    final crops = result;

    setState(() {
      for (var i = 0; i < _pages.length; i++) {
        final entry = _pages[i];
        // Replace only files derived from the capture — never the raw itself.
        if (entry.processedPath != entry.originalPath) {
          _deleteQuietly(entry.processedPath);
        }
        if (i < crops.length) {
          entry.processedPath = crops[i];
        }
        _deleteQuietly(entry.manualPath);
        _deleteQuietly(entry.perspectivePath);
        entry.manualPath = null;
        entry.perspectivePath = null;
      }
    });
    for (final entry in _pages) {
      _refreshEnhance(entry);
    }
  }

  /// Discards the whole scan session and reopens the camera for a fresh one.
  void _exitToCamera() {
    if (_saving) return;
    final nav = Navigator.of(context);
    for (final entry in _pages) {
      for (final path in entry.allPaths) {
        _deleteQuietly(path);
      }
      entry.dispose();
    }
    nav.pop();
    nav.push(MaterialPageRoute(builder: (_) => const CustomCameraScreen()));
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _savedCount = 0;
    });

    var warned = false;
    final enhanced = <String>[];
    for (final entry in _pages) {
      if (entry.enhance.isUntouched) {
        enhanced.add(entry.displayPath);
      } else {
        // Reuse the exact file the preview settled on (compute now if pending),
        // so the saved page matches what was shown. Retry once if a render
        // genuinely failed.
        var target = await entry.enhanceCache.flush();
        target ??= await entry.enhanceCache.flush();
        if (target == null) {
          // Don't silently save an unfiltered page; keep the save going but
          // tell the user which pages fell back to the original.
          warned = true;
          target = entry.displayPath;
        }
        enhanced.add(target);
      }
      if (!mounted) return;
      setState(() => _savedCount++);
    }

    if (warned && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(
          content: Text(
            'Some pages could not be enhanced and were saved as the original.',
          ),
        ),
      );
    }

    if (!mounted) return;
    final repository = context.read<DocumentRepository>();
    await repository.saveDocument(sourcePaths: enhanced);

    // Everything that isn't the final saved copy can go — raws, crops, and
    // the enhanced temp files were all moved into permanent storage above.
    for (final path in enhanced) {
      _deleteQuietly(path);
    }
    for (final entry in _pages) {
      for (final path in entry.allPaths) {
        _deleteQuietly(path);
      }
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${enhanced.length} page${enhanced.length == 1 ? '' : 's'} saved',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.myAppColors;
    final pageCount = _pages.length;
    final entry = _current;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) _redoCrop();
      },
      child: Scaffold(
        backgroundColor: colors.backgroundColor,
        appBar: AppBar(
          backgroundColor: colors.backgroundColor,
          foregroundColor: colors.headingTextColor,
          titleSpacing: 0,
          leading: IconButton(
            tooltip: 'Back to crop',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _saving ? null : _redoCrop,
          ),
          title: Text(
            pageCount > 1 ? 'Page ${_page + 1} of $pageCount' : 'Preview',
            style: const TextStyle(fontSize: 16),
          ),
          actions: [
            IconButton(
              tooltip: 'Discard',
              icon: const Icon(Icons.delete_outline_rounded),
              color: Colors.redAccent,
              onPressed: _saving ? null : _discard,
            ),
            _AppBarAction(
              icon: Icons.crop_rounded,
              label: 'Crop manually',
              active: entry.manualPath != null,
              activeColor: colors.buttonColor,
              onTap: _cropManually,
            ),
            _AppBarAction(
              icon: Icons.view_in_ar_rounded,
              label: 'Fix perspective',
              active: entry.perspectivePath != null,
              activeColor: colors.buttonColor,
              onTap: _cropPerspective,
            ),
            _AppBarAction(
              icon: Icons.refresh_rounded,
              label: 'Retake',
              active: false,
              activeColor: colors.buttonColor,
              onTap: _retake,
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: pageCount,
                    onPageChanged: (i) {
                      setState(() => _page = i);
                      final entry = _pages[i];
                      if (!entry.enhance.isUntouched &&
                          !entry.enhanceCache.isSettled) {
                        entry.enhanceCache.update(entry.enhance);
                      }
                    },
                    itemBuilder: (context, i) {
                      final page = _pages[i];
                      final cache = page.enhanceCache;
                      final shownPath = cache.displayPath ?? page.displayPath;
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          InteractiveViewer(
                            child: Center(
                              child: Image.file(
                                File(shownPath),
                                key: ValueKey(shownPath),
                                fit: BoxFit.contain,
                                width: double.infinity,
                                gaplessPlayback: true,
                              ),
                            ),
                          ),
                          // Thin, unobtrusive hint while a real render is on its
                          // way; preview renders are fast, so this rarely shows.
                          if (cache.isComputing)
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: LinearProgressIndicator(
                                minHeight: 2,
                                backgroundColor: Colors.black12,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                if (pageCount > 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(pageCount, (i) {
                        final active = i == _page;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: active ? 18 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: active
                                ? colors.buttonColor
                                : colors.borderColor,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        );
                      }),
                    ),
                  ),
                EnhancePanel(
                  settings: entry.enhance,
                  onChanged: _setEnhance,
                  onReset: _resetEnhance,
                  onApplyAll: pageCount > 1 ? _applyEnhanceToAll : null,
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colors.headingTextColor,
                              side: BorderSide(color: colors.borderColor),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: _saving ? null : _redoCrop,
                            child: const Text('Back'),
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
                            onPressed: _saving ? null : _save,
                            child: Text(
                              pageCount > 1
                                  ? 'Save $pageCount Pages'
                                  : 'Save Document',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_saving)
              Container(
                color: colors.backgroundColor.withValues(alpha: 0.92),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: colors.buttonColor),
                    const SizedBox(height: 16),
                    Text(
                      'Enhancing page ${_savedCount + 1} of $pageCount…',
                      style: TextStyle(
                        color: colors.headingTextColor.withValues(alpha: 0.75),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Compact app-bar toggle that fills in when its mode is active.
class _AppBarAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback? onTap;

  const _AppBarAction({
    required this.icon,
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myAppColors;
    final disabled = onTap == null;
    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
        child: Material(
          color: active ? activeColor : colors.borderColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: onTap,
            child: SizedBox(
              width: 40,
              height: 36,
              child: Icon(
                icon,
                size: 19,
                color: disabled
                    ? colors.headingTextColor.withValues(alpha: 0.35)
                    : active
                    ? Colors.white
                    : colors.headingTextColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
