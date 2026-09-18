import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PdfBuildRequest {
  final List<String> imagePaths;

  const PdfBuildRequest({required this.imagePaths});
}

class PdfService {
  PdfService._();

  /// Builds a PDF, one page per image, each image fit to an A4 page.
  /// Runs off the UI thread since encoding several full-res JPEGs into a
  /// PDF is real work.
  static Future<Uint8List> buildPdf(PdfBuildRequest request) => compute(_buildPdfEntry, request);

  /// Writes the given bytes to a private app-storage file and returns its
  /// path — used as the source for sharing and as the private display copy.
  static Future<String> writeToAppStorage(Uint8List bytes, String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final pdfDir = Directory('${dir.path}${Platform.pathSeparator}pdf_documents');
    if (!await pdfDir.exists()) await pdfDir.create(recursive: true);
    final file = File('${pdfDir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}

Future<Uint8List> _buildPdfEntry(PdfBuildRequest request) {
  final document = pw.Document();

  for (final path in request.imagePaths) {
    final bytes = File(path).readAsBytesSync();
    final image = pw.MemoryImage(bytes);
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(18),
        build: (context) => pw.Center(
          child: pw.Image(image, fit: pw.BoxFit.contain),
        ),
      ),
    );
  }

  return document.save();
}