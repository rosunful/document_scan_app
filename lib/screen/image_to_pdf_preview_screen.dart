import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';

import '../services/pdf_service.dart';
import '../theme/app_theme.dart';
import 'camera_scan_preview_screen.dart';

/// Confirm-and-convert step for the "Image to PDF" tool. Accepts image
/// paths captured via the camera or picked from the gallery, lets the user
/// reorder / remove / add more, then builds a single PDF from them.
class ImageToPdfPreviewScreen extends StatefulWidget {
  final List<String> imagePaths;

  const ImageToPdfPreviewScreen({super.key, required this.imagePaths});

  @override
  State<ImageToPdfPreviewScreen> createState() =>
      _ImageToPdfPreviewScreenState();
}

class _ImageToPdfPreviewScreenState extends State<ImageToPdfPreviewScreen> {
  late final List<String> _pages;
  final ImagePicker _picker = ImagePicker();
  bool _converting = false;

  @override
  void initState() {
    super.initState();
    _pages = List.of(widget.imagePaths);
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final page = _pages.removeAt(oldIndex);
      _pages.insert(newIndex, page);
    });
  }

  void _remove(int index) => setState(() => _pages.removeAt(index));

  Future<void> _addFromCamera() async {
    final set = await Navigator.of(context).push<ScanPageSet>(
      MaterialPageRoute(builder: (_) => const CustomCameraScreen()),
    );
    if (set == null || set.crops.isEmpty || !mounted) return;
    setState(() => _pages.addAll(set.crops));
    for (final path in set.origins) {
      _deleteQuietly(path);
    }
  }

  void _deleteQuietly(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // Best-effort cleanup.
    }
  }

  /// Multi-select straight from the gallery — the "instead of the camera"
  /// path. No cropper here since these are picked as final images already.
  Future<void> _addFromGallery() async {
    try {
      final picked = await _picker.pickMultiImage(imageQuality: 95);
      if (picked.isEmpty || !mounted) return;
      setState(() => _pages.addAll(picked.map((x) => x.path)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't access your photos.")),
        );
      }
    }
  }

  String _fileName() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Document_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}.pdf';
  }

  Future<void> _convert() async {
    if (_pages.isEmpty) return;
    setState(() => _converting = true);

    try {
      final bytes = await PdfService.buildPdf(
        PdfBuildRequest(imagePaths: _pages),
      );
      final fileName = _fileName();

      // Keep a private copy so the app can list/reopen it later if you wire
      // that in; the share sheet below is what lets the user put it
      // somewhere they can find in a file browser (Downloads, Drive, etc.).
      await PdfService.writeToAppStorage(bytes, fileName);

      if (!mounted) return;
      await Printing.sharePdf(bytes: bytes, filename: fileName);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not create the PDF. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _converting = false);
    }
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
        title: Text(
          '${_pages.length} page${_pages.length == 1 ? '' : 's'} selected',
        ),
        actions: [
          IconButton(
            tooltip: 'Add from camera',
            icon: const Icon(Icons.camera_alt_outlined),
            onPressed: _converting ? null : _addFromCamera,
          ),
          IconButton(
            tooltip: 'Add from gallery',
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: _converting ? null : _addFromGallery,
          ),
        ],
      ),
      body: Stack(
        children: [
          _pages.isEmpty
              ? Center(
                  child: Text(
                    'No pages yet — add photos to convert',
                    style: TextStyle(color: colors.descriptionColor),
                  ),
                )
              : ReorderableGridView(
                  pages: _pages,
                  onReorder: _reorder,
                  onRemove: _remove,
                  colors: colors,
                ),
          if (_converting)
            Container(
              color: Colors.black45,
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: colors.buttonColor),
                  const SizedBox(height: 14),
                  const Text(
                    'Creating PDF…',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.buttonColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: (_pages.isEmpty || _converting) ? null : _convert,
            child: Text(
              _pages.length > 1
                  ? 'Convert ${_pages.length} Pages to PDF'
                  : 'Convert to PDF',
            ),
          ),
        ),
      ),
    );
  }
}

/// Thumbnail grid with drag-to-reorder and a remove button per tile.
class ReorderableGridView extends StatelessWidget {
  final List<String> pages;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(int index) onRemove;
  final CustomAppColors colors;

  const ReorderableGridView({
    super.key,
    required this.pages,
    required this.onReorder,
    required this.onRemove,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(16),
      onReorder: onReorder,
      itemCount: pages.length,
      itemBuilder: (context, index) {
        final path = pages[index];
        return Padding(
          key: ValueKey(path),
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            decoration: BoxDecoration(
              color: colors.cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.borderColor),
            ),
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: colors.descriptionColor,
                  ),
                ),
                const SizedBox(width: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(path),
                    width: 52,
                    height: 68,
                    fit: BoxFit.cover,
                  ),
                ),
                const Spacer(),
                Icon(Icons.drag_handle_rounded, color: colors.descriptionColor),
                IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    color: colors.descriptionColor,
                  ),
                  onPressed: () => onRemove(index),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
