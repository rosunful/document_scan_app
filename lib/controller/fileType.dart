import 'package:flutter/material.dart';

/// The kind of file a [DocumentItem] represents. Drives the icon and the
/// tinted badge color shown in document list rows across the app.
enum FileType { pdf, image, excel, text }

extension FileTypeStyle on FileType {
  IconData get icon {
    switch (this) {
      case FileType.pdf:
        return Icons.picture_as_pdf_rounded;
      case FileType.image:
        return Icons.image_rounded;
      case FileType.excel:
        return Icons.grid_on_rounded;
      case FileType.text:
        return Icons.description_rounded;
    }
  }

  /// Soft badge background behind the icon.
  Color get background {
    switch (this) {
      case FileType.pdf:
        return const Color(0xFFFCE7E6);
      case FileType.image:
        return const Color(0xFFE1EDFF);
      case FileType.excel:
        return const Color(0xFFDEF3E6);
      case FileType.text:
        return const Color(0xFFEBE2FB);
    }
  }

  /// Icon / accent color drawn on top of [background].
  Color get foreground {
    switch (this) {
      case FileType.pdf:
        return const Color(0xFFE5473E);
      case FileType.image:
        return const Color(0xFF3B82F6);
      case FileType.excel:
        return const Color(0xFF1E9254);
      case FileType.text:
        return const Color(0xFF8B5CF6);
    }
  }

  /// Label shown in the row subtitle, e.g. "PDF · 4 pages · Today".
  String get label {
    switch (this) {
      case FileType.pdf:
        return 'PDF';
      case FileType.image:
        return 'Image';
      case FileType.excel:
        return 'Excel';
      case FileType.text:
        return 'Text';
    }
  }
}