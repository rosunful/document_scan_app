import 'package:flutter/services.dart';

/// Best-effort copy of a file into public phone storage (the Downloads
/// folder) so the user can find an imported PDF / spreadsheet / text file
/// in a Files or Downloads app, just like images are exported to the gallery.
class PublicFileExporter {
  static const MethodChannel _channel = MethodChannel('scan_documnet_app/public_files');

  /// Returns true when the copy landed in Downloads. Never throws: a platform
  /// that can't do it (iOS, desktop, web), a missing permission on old
  /// Android, or an IO error simply returns false.
  static Future<bool> saveToDownloads(
    String sourcePath, {
    String? fileName,
    String? mimeType,
  }) async {
    try {
      final result = await _channel.invokeMethod<String>('saveToDownloads', {
        'sourcePath': sourcePath,
        'fileName': fileName ?? basenameOf(sourcePath),
        'mimeType': mimeType,
      });
      return result != null && result.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static String basenameOf(String path) => path.split(RegExp(r'[/\\]')).last;
}