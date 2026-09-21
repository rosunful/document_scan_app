import 'package:flutter/material.dart';
import '../model/tool_model.dart';

/// Centralized mock data. Swap this file for a real repository/API layer
/// later without touching any widget code.
class MockData {
  MockData._();

  static const List<ToolItem> tools = [
    ToolItem(
      icon: Icons.camera_alt_rounded,
      title: 'Scan Document',
      subtitle: 'Extract text from images',
      iconBackground: Color(0xFFDCF2E9),
      iconColor: Color(0xFF129D7C),
    ),
    ToolItem(
      icon: Icons.document_scanner_rounded,
      title: 'Auto Scan',
      subtitle: 'One-tap auto-crop scan',
      iconBackground: Color(0xFFFDE7D8),
      iconColor: Color(0xFFE5692B),
    ),
    ToolItem(
      icon: Icons.picture_as_pdf_rounded,
      title: 'Image to PDF',
      subtitle: 'Convert images to PDF',
      iconBackground: Color(0xFFE1EDFF),
      iconColor: Color(0xFF3B82F6),
    ),
    ToolItem(
      icon: Icons.image_rounded,
      title: 'PDF to Image',
      subtitle: 'Convert PDF to images',
      iconBackground: Color(0xFFEBE2FB),
      iconColor: Color(0xFF8B5CF6),
    ),
    ToolItem(
      icon: Icons.grid_on_rounded,
      title: 'Open in Excel',
      subtitle: 'Convert to Excel format',
      iconBackground: Color(0xFFDEF3E6),
      iconColor: Color(0xFF1E9254),
    ),
  ];
}