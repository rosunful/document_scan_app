import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

class PdfToImageService {
  PdfToImageService._();

  /// Renders every page of the PDF at [pdfPath] to a JPEG, saved into a
  /// temp working folder. Returns the resulting image paths, in page order.
  static Future<List<String>> renderPages(String pdfPath, {double scale = 2.0}) async {
    final document = await PdfDocument.openFile(pdfPath);
    final tempDir = await getTemporaryDirectory();
    final outDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}pdf_render_${DateTime.now().microsecondsSinceEpoch}',
    );
    await outDir.create(recursive: true);

    final paths = <String>[];
    try {
      for (var i = 1; i <= document.pagesCount; i++) {
        final page = await document.getPage(i);
        try {
          final rendered = await page.render(
            width: page.width * scale,
            height: page.height * scale,
            format: PdfPageImageFormat.jpeg,
            backgroundColor: '#FFFFFF',
          );
          if (rendered == null) continue;

          final file = File(
            '${outDir.path}${Platform.pathSeparator}page_${i.toString().padLeft(3, '0')}.jpg',
          );
          await file.writeAsBytes(rendered as Uint8List);
          paths.add(file.path);
        } finally {
          await page.close();
        }
      }
    } finally {
      await document.close();
    }
    return paths;
  }
}