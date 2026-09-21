import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import '../theme/app_theme.dart';

/// Views an imported PDF document with page scrolling and pinch-to-zoom.
class SavedPdfViewerScreen extends StatefulWidget {
  final String path;
  final String title;

  const SavedPdfViewerScreen({super.key, required this.path, required this.title});

  @override
  State<SavedPdfViewerScreen> createState() => _SavedPdfViewerScreenState();
}

class _SavedPdfViewerScreenState extends State<SavedPdfViewerScreen> {
  late final PdfControllerPinch _controller;

  @override
  void initState() {
    super.initState();
    _controller = PdfControllerPinch(
      document: PdfDocument.openFile(widget.path),
      initialPage: 1,
      viewportFraction: 0.95,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.myAppColors;

    return Scaffold(
      backgroundColor: colors.backgroundColor,
      appBar: AppBar(
        backgroundColor: colors.backgroundColor,
        foregroundColor: colors.headingTextColor,
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: PdfViewPinch(
        controller: _controller,
        backgroundDecoration: BoxDecoration(color: colors.backgroundColor),
        builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
          options: const DefaultBuilderOptions(),
          documentLoaderBuilder: (_) =>
              Center(child: CircularProgressIndicator(color: colors.buttonColor)),
          pageLoaderBuilder: (_) =>
              Center(child: CircularProgressIndicator(color: colors.buttonColor)),
        ),
      ),
    );
  }
}