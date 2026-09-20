import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/ocr_service.dart';
import '../theme/app_theme.dart';
import 'camera_scan_preview_screen.dart';

enum _State { pickSource, extracting, done, error }

/// Photograph or pick one or more pages, run on-device OCR on each, and
/// show the combined text — editable, so the user can fix recognition
/// mistakes before copying or sharing it.
class TextExtractionScreen extends StatefulWidget {
  const TextExtractionScreen({super.key});

  @override
  State<TextExtractionScreen> createState() => _TextExtractionScreenState();
}

class _TextExtractionScreenState extends State<TextExtractionScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _textController = TextEditingController();

  _State _state = _State.pickSource;
  String _errorMessage = '';
  int _totalPages = 0;
  int _processedPages = 0;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _useCamera() async {
    final captured = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(builder: (_) => const CustomCameraScreen()),
    );
    if (captured == null || captured.isEmpty || !mounted) return;
    await _runOcr(captured);
  }

  Future<void> _useGallery() async {
    try {
      final picked = await _picker.pickMultiImage(imageQuality: 95);
      if (picked.isEmpty || !mounted) return;
      await _runOcr(picked.map((x) => x.path).toList());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't access your photos.")),
        );
      }
    }
  }

  Future<void> _runOcr(List<String> imagePaths) async {
    setState(() {
      _state = _State.extracting;
      _totalPages = imagePaths.length;
      _processedPages = 0;
    });

    final buffer = StringBuffer();
    try {
      for (var i = 0; i < imagePaths.length; i++) {
        final text = await OcrService.extractText(imagePaths[i]);
        if (imagePaths.length > 1) {
          if (i > 0) buffer.writeln();
          buffer.writeln('--- Page ${i + 1} ---');
        }
        buffer.writeln(text.trim());
        if (!mounted) return;
        setState(() => _processedPages = i + 1);
      }

      if (!mounted) return;
      final extracted = buffer.toString().trim();
      setState(() {
        _textController.text = extracted.isEmpty
            ? 'No text was found in the image${imagePaths.length == 1 ? '' : 's'}.'
            : extracted;
        _state = _State.done;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _state = _State.error;
        _errorMessage = 'Could not extract text. Try a clearer, well-lit photo.';
      });
    }
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: _textController.text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied to clipboard')),
      );
    }
  }

  Future<void> _shareAsTextFile() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final fileName =
          'Extracted_Text_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}.txt';
      final file = File('${tempDir.path}${Platform.pathSeparator}$fileName');
      await file.writeAsString(_textController.text);

      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], fileNameOverrides: [fileName]),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not share the text file.')),
        );
      }
    }
  }

  void _startOver() {
    setState(() {
      _state = _State.pickSource;
      _textController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.myAppColors;

    return Scaffold(
      backgroundColor: colors.backgroundColor,
      appBar: AppBar(
        backgroundColor: colors.backgroundColor,
        foregroundColor: colors.headingTextColor,
        elevation: 0,
        title: const Text('Extract Text'),
        actions: [
          if (_state == _State.done)
            IconButton(
              tooltip: 'Start over',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _startOver,
            ),
        ],
      ),
      body: switch (_state) {
        _State.pickSource => _buildSourcePicker(colors),
        _State.extracting => _buildProgress(colors),
        _State.error => _buildError(colors),
        _State.done => _buildResult(colors),
      },
    );
  }

  Widget _buildSourcePicker(CustomAppColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.text_snippet_outlined, size: 56, color: colors.descriptionColor),
            const SizedBox(height: 16),
            Text(
              'Capture or choose a photo to extract text from',
              style: TextStyle(color: colors.headingTextColor, fontSize: 15),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.buttonColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                minimumSize: const Size(220, 0),
              ),
              onPressed: _useCamera,
              icon: const Icon(Icons.camera_alt_rounded),
              label: const Text('Use Camera'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.headingTextColor,
                side: BorderSide(color: colors.borderColor),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                minimumSize: const Size(220, 0),
              ),
              onPressed: _useGallery,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Choose from Gallery'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress(CustomAppColors colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: colors.buttonColor),
          const SizedBox(height: 16),
          Text(
            _totalPages > 1
                ? 'Reading page $_processedPages of $_totalPages…'
                : 'Reading text…',
            style: TextStyle(color: colors.descriptionColor),
          ),
        ],
      ),
    );
  }

  Widget _buildError(CustomAppColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: colors.descriptionColor),
            const SizedBox(height: 16),
            Text(_errorMessage, textAlign: TextAlign.center, style: TextStyle(color: colors.headingTextColor)),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: colors.buttonColor, foregroundColor: Colors.white),
              onPressed: _startOver,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(CustomAppColors colors) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(
                color: colors.cardColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.borderColor),
              ),
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _textController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: TextStyle(fontSize: 14, color: colors.headingTextColor, height: 1.5),
                decoration: const InputDecoration(border: InputBorder.none),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.headingTextColor,
                      side: BorderSide(color: colors.borderColor),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _copyAll,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copy'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.buttonColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _shareAsTextFile,
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text('Share'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}