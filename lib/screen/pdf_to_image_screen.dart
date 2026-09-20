import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';

import '../services/pdf_to_image_service.dart';
import '../theme/app_theme.dart';

class PdfToImageScreen extends StatefulWidget {
  const PdfToImageScreen({super.key, this.initialPages});

  /// Pages already rendered by the caller (e.g. the Home screen), so this
  /// screen can open straight to the grid instead of picking a file.
  final List<String>? initialPages;

  @override
  State<PdfToImageScreen> createState() => _PdfToImageScreenState();
}

enum _State { pickFile, rendering, done, error }

class _PdfToImageScreenState extends State<PdfToImageScreen> {
  _State _state = _State.pickFile;
  List<String> _pages = [];
  String _errorMessage = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final pages = widget.initialPages;
    if (pages != null) {
      _pages = pages;
      _state = _State.done;
    } else {
      _pickAndRender();
    }
  }

  Future<void> _pickAndRender() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final path = result.isEmpty ? null : result.single.path;
    if (path == null) {
      // Cancelled the picker. On first entry there is nothing to fall back
      // to, so leave the screen.
      if (mounted && _state == _State.pickFile) Navigator.of(context).pop();
      return;
    }
    if (!mounted) return;

    setState(() => _state = _State.rendering);
    try {
      final pages = await PdfToImageService.renderPages(path);
      if (!mounted) return;
      if (pages.isEmpty) {
        setState(() {
          _state = _State.error;
          _errorMessage = 'No pages could be rendered from this PDF.';
        });
        return;
      }
      setState(() {
        _pages = pages;
        _state = _State.done;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _state = _State.error;
        _errorMessage = 'Could not open this PDF. It may be corrupted or password-protected.';
      });
    }
  }

  Future<void> _saveAllToGallery() async {
    setState(() => _saving = true);
    try {
      var hasAccess = await Gal.hasAccess();
      if (!hasAccess) hasAccess = await Gal.requestAccess();
      if (!hasAccess) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permission needed to save to your gallery.')),
          );
        }
        return;
      }
      for (final path in _pages) {
        await Gal.putImage(path, album: 'ScanDocumentApp');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_pages.length} image${_pages.length == 1 ? '' : 's'} saved to gallery')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the images.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
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
        title: const Text('PDF to Image'),
        actions: [
          if (_state == _State.done)
            IconButton(
              tooltip: 'Save all to gallery',
              icon: const Icon(Icons.download_rounded),
              onPressed: _saving ? null : _saveAllToGallery,
            ),
        ],
      ),
      body: switch (_state) {
        _State.pickFile || _State.rendering =>
          Center(child: CircularProgressIndicator(color: colors.buttonColor)),
        _State.error => _buildError(colors),
        _State.done => _buildGrid(colors),
      },
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
              onPressed: _pickAndRender,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(CustomAppColors colors) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemCount: _pages.length,
      itemBuilder: (context, i) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(border: Border.all(color: colors.borderColor)),
            child: Image.file(File(_pages[i]), fit: BoxFit.cover),
          ),
        );
      },
    );
  }
}