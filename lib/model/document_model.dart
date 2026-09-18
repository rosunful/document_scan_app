import '../controller/fileType.dart';

/// A single scanned/converted file shown in a list row.
class DocumentItem {
  final String id;
  final String name;
  final FileType type;
  final int pages;
  final String dateLabel;
  final List<String> pagePaths;

  const DocumentItem({
    required this.id,
    required this.name,
    required this.type,
    required this.pages,
    required this.dateLabel,
    required this.pagePaths,
  });

  String get subtitle => '${type.label} · $pages ${pages == 1 ? 'page' : 'pages'} · $dateLabel';
  String get coverPath => pagePaths.first;
}

/// A month section on the Documents screen, e.g. "September 2025" with its files.
class MonthGroup {
  final String month;
  final List<DocumentItem> documents;

  const MonthGroup(this.month, this.documents);

  int get fileCount => documents.length;
}