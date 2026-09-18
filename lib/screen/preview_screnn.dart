import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:provider/provider.dart';

import '../repository/document_repository.dart';
import '../services/auto_crop_service.dart';
import '../theme/app_theme.dart';
import 'camera_scan_preview_screen.dart';
import 'enchance_screen.dart';

class ScanPreviewScreen extends StatefulWidget {
  final List<String> imagePaths;

  const ScanPreviewScreen({super.key, required this.imagePaths});

  @override
  State<ScanPreviewScreen> createState() => _ScanPreviewScreenState();
}

/// One captured page and everything we've derived from it.
class _PageEntry {  
  final String originalPath;
  String? autoPath;    // result of auto-crop, null until it runs
  String? manualPath;  // user's own crop, wins over everything
  bool autoEnabled;
  bool busy;
  bool autoFailed;     // detection ran and found nothing usable

  _PageEntry(this.originalPath, {this.autoEnabled = true, this.busy = false, this.autoFailed = false});

  String get displayPath => manualPath ?? (autoEnabled ? (autoPath ?? originalPath) : originalPath);

  List<String> get allPaths => [
        originalPath,
        if (autoPath != null) autoPath!,
        if (manualPath != null) manualPath!,
      ];
}

class _ScanPreviewScreenState extends State<ScanPreviewScreen> {
  final PageController _controller = PageController();
  late final List<_PageEntry> _pages;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _pages = widget.imagePaths.map((p) => _PageEntry(p, busy: true)).toList();
    _autoCropAll();
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

  Future<void> _autoCropAll() async {
    for (var i = 0; i < _pages.length; i++) {
      await _autoCropOne(i);
    }
  }

  Future<void> _autoCropOne(int index) async {
    final entry = _pages[index];
    if (entry.autoPath != null || entry.autoFailed) {
      if (entry.busy && mounted) setState(() => entry.busy = false);
      return;
    }

    if (mounted) setState(() => entry.busy = true);

    final result = await AutoCropService.crop(
      AutoCropRequest(
        sourcePath: entry.originalPath,
        targetPath: _derivedPath(entry.originalPath, 'auto'),
      ),
    );

    if (!mounted) return;
    setState(() {
      entry.busy = false;
      if (result != null) {
        entry.autoPath = result;
      } else {
        entry.autoFailed = true; // keep the original, don't retry on every toggle
      }
    });
  }

  Future<void> _toggleAutoCrop() async {
    final entry = _current;
    if (entry.busy) return;

    if (entry.autoEnabled) {
      setState(() => entry.autoEnabled = false);
      return;
    }

    // Turning auto back on discards a manual crop — they're alternatives.
    setState(() {
      _deleteQuietly(entry.manualPath);
      entry.manualPath = null;
      entry.autoEnabled = true;
    });
    await _autoCropOne(_page);

    if (mounted && entry.autoFailed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't find the page edges — crop it manually.")),
      );
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
        entry.manualPath = cropped.path;
        entry.autoEnabled = false;
      });
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? "Couldn't open the cropper.")),
        );
      }
    }
  }

  Future<void> _retake() async {
    final captured = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(builder: (_) => const CustomCameraScreen()),
    );
    if (captured == null || captured.isEmpty || !mounted) return;

    final index = _page;
    final old = _pages[index];

    setState(() {
      _pages[index] = _PageEntry(captured.first, busy: true);
    });

    // Anything extra they shot during the retake gets appended rather than lost.
    if (captured.length > 1) {
      setState(() {
        for (final path in captured.skip(1)) {
          _pages.add(_PageEntry(path, busy: true));
        }
      });
    }

    for (final path in old.allPaths) {
      _deleteQuietly(path);
    }

    for (var i = 0; i < _pages.length; i++) {
      if (_pages[i].busy) await _autoCropOne(i);
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
    final autoActive = entry.autoEnabled && entry.manualPath == null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Text(
          pageCount > 1 ? 'Page ${_page + 1} of $pageCount' : 'Preview',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          _AppBarAction(
            icon: Icons.crop_free_rounded,
            label: 'Auto crop',
            active: autoActive,
            activeColor: colors.buttonColor,
            onTap: entry.busy ? null : _toggleAutoCrop,
          ),
          _AppBarAction(
            icon: Icons.crop_rounded,
            label: 'Crop manually',
            active: entry.manualPath != null,
            activeColor: colors.buttonColor,
            onTap: entry.busy ? null : _cropManually,
          ),
          _AppBarAction(
            icon: Icons.refresh_rounded,
            label: 'Retake',
            active: false,
            activeColor: colors.buttonColor,
            onTap: entry.busy ? null : _retake,
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
                    if (page.busy)
                      Container(
                        color: Colors.black45,
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: colors.buttonColor),
                            const SizedBox(height: 12),
                            const Text(
                              'Finding page edges…',
                              style: TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              entry.manualPath != null
                  ? 'Cropped manually'
                  : entry.autoEnabled
                      ? (entry.autoFailed ? 'No edges detected — showing original' : 'Auto-cropped')
                      : 'Auto crop off — showing original',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
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
                      color: active ? colors.buttonColor : Colors.white38,
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
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
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
                      onPressed: _pages.any((p) => p.busy) ? null : _save,
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
    final disabled = onTap == null;
    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
        child: Material(
          color: active ? activeColor : Colors.white12,
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
                color: disabled ? Colors.white30 : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}



// import 'dart:io';
// import 'package:flutter/material.dart';
// import '../theme/app_theme.dart';

// class ScanPreviewScreen extends StatefulWidget {
//   final List<String> imagePaths;

//   const ScanPreviewScreen({super.key, required this.imagePaths});

//   @override
//   State<ScanPreviewScreen> createState() => _ScanPreviewScreenState();
// }

// class _ScanPreviewScreenState extends State<ScanPreviewScreen> {
//   final PageController _controller = PageController();
//   int _page = 0;

//   @override
//   void dispose() {
//     _controller.dispose();
//     super.dispose();
//   }

//   void _discard(BuildContext context) {
//     // We own these files directly now (the camera package writes them to a
//     // temp dir) — delete them since the user chose not to keep this scan.
//     for (final path in widget.imagePaths) {
//       try {
//         final file = File(path);
//         if (file.existsSync()) file.deleteSync();
//       } catch (_) {
//         // Best-effort cleanup; ignore failures.
//       }
//     }
//     Navigator.of(context).pop();
//   }

//   void _save(BuildContext context) {
//     // TODO: once a real repository replaces MockData, copy widget.imagePaths
//     // into permanent storage and create real DocumentItem entries here.
//     final pageCount = widget.imagePaths.length;
//     final messenger = ScaffoldMessenger.of(context);
//     Navigator.of(context).pop();
//     messenger.showSnackBar(
//       SnackBar(content: Text('$pageCount page${pageCount == 1 ? '' : 's'} saved (mock)')),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     final colors = context.myAppColors;
//     final pageCount = widget.imagePaths.length;

//     return Scaffold(
//       backgroundColor: Colors.black,
//       appBar: AppBar(
//         backgroundColor: Colors.black,
//         foregroundColor: Colors.white,
//         title: Text(pageCount > 1 ? 'Page ${_page + 1} of $pageCount' : 'Preview'),
//       ),
//       body: Column(
//         children: [
//           Expanded(
//             child: PageView.builder(
//               controller: _controller,
//               itemCount: pageCount,
//               onPageChanged: (i) => setState(() => _page = i),
//               itemBuilder: (context, i) => InteractiveViewer(
//                 child: Image.file(
//                   File(widget.imagePaths[i]),
//                   fit: BoxFit.contain,
//                   width: double.infinity,
//                 ),
//               ),
//             ),
//           ),
//           if (pageCount > 1)
//             Padding(
//               padding: const EdgeInsets.symmetric(vertical: 10),
//               child: Row(
//                 mainAxisAlignment: MainAxisAlignment.center,
//                 children: List.generate(pageCount, (i) {
//                   final active = i == _page;
//                   return AnimatedContainer(
//                     duration: const Duration(milliseconds: 150),
//                     margin: const EdgeInsets.symmetric(horizontal: 3),
//                     width: active ? 18 : 6,
//                     height: 6,
//                     decoration: BoxDecoration(
//                       color: active ? colors.buttonColor : Colors.white38,
//                       borderRadius: BorderRadius.circular(3),
//                     ),
//                   );
//                 }),
//               ),
//             ),
//           SafeArea(
//             top: false,
//             child: Padding(
//               padding: const EdgeInsets.all(16),
//               child: Row(
//                 children: [
//                   Expanded(
//                     child: OutlinedButton(
//                       style: OutlinedButton.styleFrom(
//                         foregroundColor: Colors.white,
//                         side: const BorderSide(color: Colors.white54),
//                         padding: const EdgeInsets.symmetric(vertical: 14),
//                       ),
//                       onPressed: () => _discard(context),
//                       child: const Text('Discard'),
//                     ),
//                   ),
//                   const SizedBox(width: 12),
//                   Expanded(
//                     child: ElevatedButton(
//                       style: ElevatedButton.styleFrom(
//                         backgroundColor: colors.buttonColor,
//                         foregroundColor: Colors.white,
//                         padding: const EdgeInsets.symmetric(vertical: 14),
//                       ),
//                       onPressed: () => _save(context),
//                       child: Text(pageCount > 1 ? 'Save $pageCount Pages' : 'Save Document'),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }