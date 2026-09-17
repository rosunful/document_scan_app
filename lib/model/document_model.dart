import '../controller/fileType.dart';

/// A single scanned/converted file shown in a list row.
class DocumentItem {
  final String name;
  final FileType type;
  final int pages;

  /// Human-friendly recency label, e.g. "Today", "Yesterday", "Aug 28, 2025".
  final String dateLabel;

  const DocumentItem({
    required this.name,
    required this.type,
    required this.pages,
    required this.dateLabel,
  });

  String get subtitle => '${type.label} · $pages ${pages == 1 ? 'page' : 'pages'} · $dateLabel';
}

/// A month section on the Documents screen, e.g. "September 2025" with its files.
class MonthGroup {
  final String month;
  final List<DocumentItem> documents;

  const MonthGroup(this.month, this.documents);

  int get fileCount => documents.length;
}