import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:provider/provider.dart';

import '../repository/document_repository.dart';
import '../theme/app_theme.dart';
import 'camera_scan_preview_screen.dart';
import 'enchance_screen.dart';
import 'perspective_crop_screen.dart';

class ScanPreviewScreen extends StatefulWidget {
  final List<String> imagePaths;

  const ScanPreviewScreen({super.key, required this.imagePaths});

  @override
  State<ScanPreviewScreen> createState() => _ScanPreviewScreenState();
}

/// One captured page and everything we've derived from it.
class _PageEntry {
  final String originalPath;
  String? manualPath;      // user's own crop, wins over everything
  String? perspectivePath; // user's perspective fix, beats manual

  _PageEntry(this.originalPath);

  String get displayPath => manualPath ?? perspectivePath ?? originalPath;

  List<String> get allPaths => [
        originalPath,
        ?manualPath,
        ?perspectivePath,
      ];
}

class _ScanPreviewScreenState extends State<ScanPreviewScreen> {
  final PageController _controller = PageController();
  late final List<_PageEntry> _pages;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _pages = widget.imagePaths.map((p) => _PageEntry(p)).toList();
  }

  @override
  void dispose() {
    _controller.dispose();
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
    if (result == null || !mounted) return;

    setState(() {
      _deleteQuietly(entry.manualPath);
      _deleteQuietly(entry.perspectivePath);
      entry.manualPath = null;
      entry.perspectivePath = result;
    });
  }

  Future<void> _retake() async {
    final captured = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(builder: (_) => const CustomCameraScreen()),
    );
    if (captured == null || captured.isEmpty || !mounted) return;

    final index = _page;
    final old = _pages[index];

    setState(() {
      _pages[index] = _PageEntry(captured.first);
    });

    // Anything extra they shot during the retake gets appended rather than lost.
    if (captured.length > 1) {
      setState(() {
        for (final path in captured.skip(1)) {
          _pages.add(_PageEntry(path));
        }
      });
    }

    for (final path in old.allPaths) {
      _deleteQuietly(path);
    }
  }

  void _discard() {
    for (final entry in _pages) {
      for (final path in entry.allPaths) {
        _deleteQuietly(path);
      }
    }
    Navigator.of(context).pop();
  }

   Future<void> _save() async {
  final sources = _pages.map((e) => e.displayPath).toList();
  final enhanced = await Navigator.of(context).push<List<String>>(
    MaterialPageRoute(builder: (_) => EnhanceScreen(imagePaths: sources)),
  );
  if (enhanced == null || !mounted) return; // user tapped Back

  final repository = context.read<DocumentRepository>();
  await repository.saveDocument(sourcePaths: enhanced);

  // Everything that isn't the final saved copy can go — originals, crops,
  // and the enhanced temp files were all copied into permanent storage above.
  for (final entry in _pages) {
    for (final path in entry.allPaths) {
      _deleteQuietly(path);
    }
  }
  for (final path in enhanced) {
    _deleteQuietly(path);
  }

  if (!mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  Navigator.of(context).pop();
  messenger.showSnackBar(
    SnackBar(content: Text('${enhanced.length} page${enhanced.length == 1 ? '' : 's'} saved')),
  );
}

  @override
  Widget build(BuildContext context) {
    final colors = context.myAppColors;
    final pageCount = _pages.length;
    final entry = _current;

    return Scaffold(
      backgroundColor: colors.backgroundColor,
      appBar: AppBar(
        backgroundColor: colors.backgroundColor,
        foregroundColor: colors.headingTextColor,
        titleSpacing: 0,
        title: Text(
          pageCount > 1 ? 'Page ${_page + 1} of $pageCount' : 'Preview',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
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
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: pageCount,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) {
                final page = _pages[i];
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    InteractiveViewer(
                      child: Center(
                        child: Image.file(
                          File(page.displayPath),
                          key: ValueKey(page.displayPath),
                          fit: BoxFit.contain,
                          width: double.infinity,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
//           Padding(
//             padding: const EdgeInsets.only(top: 8),
//             child: Text(
//               entry.manualPath != null
//                   ? 'Cropped manually'
// : entry.perspectivePath != null
//                           ? 'Perspective corrected'
//                           : 'Original',
//               style: const TextStyle(color: Colors.white54, fontSize: 12),
//             ),
//           ),
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
                      color: active ? colors.buttonColor : colors.borderColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.headingTextColor,
                        side: BorderSide(color: colors.borderColor),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _discard,
                      child: const Text('Discard'),
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
                      onPressed: _save,
                      child: Text(pageCount > 1 ? 'Save $pageCount Pages' : 'Save Document'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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


