import 'package:flutter/material.dart';
import '../model/document_model.dart';
import '../model/tool_model.dart';
import 'fileType.dart';

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

  static const List<DocumentItem> recentDocuments = [
    DocumentItem(name: 'Invoice_September.pdf', type: FileType.pdf, pages: 4, dateLabel: 'Today'),
    DocumentItem(name: 'Project Notes', type: FileType.image, pages: 2, dateLabel: 'Yesterday'),
    DocumentItem(name: 'Budget.xlsx', type: FileType.excel, pages: 1, dateLabel: '2 days ago'),
    DocumentItem(name: 'Meeting Minutes', type: FileType.text, pages: 3, dateLabel: '3 days ago'),
    DocumentItem(name: 'Receipt_001.pdf', type: FileType.pdf, pages: 1, dateLabel: '4 days ago'),
  ];

  static const List<String> monthFilters = ['All', 'Sep 2025', 'Aug 2025', 'Jul 2025', 'Jun 2025'];

  static const List<MonthGroup> documentGroups = [
    MonthGroup('September 2025', [
      DocumentItem(name: 'Invoice_September.pdf', type: FileType.pdf, pages: 4, dateLabel: 'Today'),
      DocumentItem(name: 'Receipt_001.jpg', type: FileType.image, pages: 1, dateLabel: 'Today'),
      DocumentItem(name: 'Budget.xlsx', type: FileType.excel, pages: 1, dateLabel: 'Yesterday'),
      DocumentItem(name: 'Meeting Notes.txt', type: FileType.text, pages: 3, dateLabel: '2 days ago'),
    ]),
    MonthGroup('August 2025', [
      DocumentItem(name: 'Report.pdf', type: FileType.pdf, pages: 2, dateLabel: 'Aug 28, 2025'),
      DocumentItem(name: 'ID Card.jpg', type: FileType.image, pages: 1, dateLabel: 'Aug 25, 2025'),
      DocumentItem(name: 'Sales Data.xlsx', type: FileType.excel, pages: 5, dateLabel: 'Aug 20, 2025'),
    ]),
    MonthGroup('July 2025', [
      DocumentItem(name: 'Notes.txt', type: FileType.text, pages: 2, dateLabel: 'Jul 30, 2025'),
      DocumentItem(name: 'Contract.jpg', type: FileType.image, pages: 1, dateLabel: 'Jul 15, 2025'),
    ]),
  ];

  /// Filters [documentGroups] by a chip label from [monthFilters].
  static List<MonthGroup> groupsForFilter(String filter) {
    if (filter == 'All') return documentGroups;
    final monthPrefix = filter.split(' ').first; // "Sep", "Aug", ...
    return documentGroups.where((g) => g.month.startsWith(_fullMonth(monthPrefix))).toList();
  }

  static String _fullMonth(String prefix) {
    const map = {
      'Sep': 'September',
      'Aug': 'August',
      'Jul': 'July',
      'Jun': 'June',
    };
    return map[prefix] ?? prefix;
  }
}