import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'perspective_crop_screen.dart';

/// Shows the result of the auto-detected crop for a just-captured still and
/// lets the user accept it ("Use this") or open the corner-dragging cropper
/// instead ("Adjust manually"). Pops with the final page file path, or `null`
/// when the user backs out to retake the photo.
class CropReviewScreen extends StatefulWidget {
  /// The original, full-frame captured still.
  final String sourcePath;

  /// The auto-detected crop, or `null` when no document rectangle was found.
  final String? autoCropPath;

  const CropReviewScreen({
    super.key,
    required this.sourcePath,
    required this.autoCropPath,
  });

  @override
  State<CropReviewScreen> createState() => _CropReviewScreenState();
}

class _CropReviewScreenState extends State<CropReviewScreen> {
  String? _selectedPath;
  bool _adjusted = false;
  bool _adjusting = false;

  /// Path that will be used if the user accepts — the manual crop if they
  /// adjusted, else the auto crop if one was found, else the original frame.
  String get _resultPath => _selectedPath ?? widget.sourcePath;

  @override
  void initState() {
    super.initState();
    _selectedPath = widget.autoCropPath;
  }

  String _derivedPath(String tag) {
    final file = File(widget.sourcePath);
    final name = file.uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    final base = dot == -1 ? name : name.substring(0, dot);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return '${file.parent.path}${Platform.pathSeparator}${base}_${tag}_$stamp.jpg';
  }

  Future<void> _adjustManually() async {
    if (_adjusting) return;
    setState(() => _adjusting = true);
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => PerspectiveCropScreen(
          sourcePath: widget.sourcePath,
          targetPath: _derivedPath('persp'),
        ),
      ),
    );
    if (!mounted) {
      _deleteQuietly(result);
      return;
    }
    setState(() => _adjusting = false);
    if (result == null) return; // they backed out of the cropper

    _deleteQuietly(_selectedPath); // the auto crop they rejected
    setState(() {
      _selectedPath = result;
      _adjusted = true;
    });
  }

  void _accept() => Navigator.of(context).pop(_resultPath);

  void _retake() => Navigator.of(context).pop();

  void _deleteQuietly(String? path) {
    if (path == null) return;
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // Best-effort cleanup.
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.myAppColors;
    final hasCrop = _selectedPath != null;

    final String status;
    if (_adjusted) {
      status = 'Manual crop applied';
    } else if (hasCrop) {
      status = 'Document detected — corners look right?';
    } else {
      status = 'No document detected — adjust manually or keep the full photo';
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Crop result', style: TextStyle(fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Retake',
          onPressed: _adjusting ? null : _retake,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: InteractiveViewer(
                  child: Center(
                    child: Image.file(
                      File(_resultPath),
                      key: ValueKey(_resultPath),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 6, 24, 6),
              child: Text(
                status,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 12.5,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _adjusting ? null : _adjustManually,
                      child: const Text('Adjust manually'),
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
                      onPressed: _adjusting ? null : _accept,
                      child: Text(hasCrop ? 'Use This' : 'Keep Original'),
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