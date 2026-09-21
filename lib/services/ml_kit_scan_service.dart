import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

/// Thin wrapper around the Google ML Kit Document Scanner flow.
///
/// ML Kit opens its own full-screen scanner UI that auto-detects documents on
/// every page (color/lighting agnostic — no white-paper assumption), performs
/// the perspective crop and emits already-cropped JPEG files. This class exists
/// so the camera screens don't depend on the ML Kit API directly and so the
/// "not supported" case (no Google Play Services / non-Android) is a single
/// catch site.
class MlKitScanService {
  MlKitScanService._();

  /// Launches the ML Kit scanner and returns the cropped JPEG file paths, or
  /// `null` when the user cancelled. Throws for unrecoverable failures (no
  /// Google Play Services, missing plugin, etc.) — callers fall back to the
  /// custom camera.
  static Future<List<String>?> scanImages({
    int pageLimit = 0,
    bool galleryImport = true,
  }) async {
    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        mode: ScannerMode.full,
        pageLimit: pageLimit,
        documentFormats: const {DocumentFormat.jpeg},
        isGalleryImport: galleryImport,
      ),
    );
    try {
      final result = await scanner.scanDocument();
      final images = result.images;
      return (images == null || images.isEmpty) ? null : images;
    } finally {
      await scanner.close();
    }
  }
}