import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../controller/fileType.dart';
import '../model/document_model.dart';
import '../model/scanned_document.dart';
import '../services/public_file_exporter.dart';

class DocumentRepository extends ChangeNotifier {
  static const _indexFileName = 'documents_index.json';
  static const _pagesDirName = 'scanned_pages';
  static const _galleryAlbum = 'ScanDocumentApp';

  final List<ScannedDocument> _documents = [];
  bool _loaded = false;
  bool get isLoaded => _loaded;

  List<ScannedDocument> get documents => List.unmodifiable(_documents);

  Future<Directory> _appDir() => getApplicationDocumentsDirectory();

  Future<Directory> _pagesDir() async {
    final base = await _appDir();
    final dir = Directory('${base.path}${Platform.pathSeparator}$_pagesDirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _indexFile() async {
    final base = await _appDir();
    return File('${base.path}${Platform.pathSeparator}$_indexFileName');
  }

  /// Call once at app startup, before the UI reads `documents`.
  Future<void> load() async {
    if (_loaded) return;
    try {
      final file = await _indexFile();
      if (await file.exists()) {
        final raw = jsonDecode(await file.readAsString()) as List;
        _documents
          ..clear()
          ..addAll(raw.map((e) => ScannedDocument.fromJson(e as Map<String, dynamic>)));
        _documents.removeWhere((d) => d.pagePaths.isEmpty || !File(d.pagePaths.first).existsSync());
      }
    } catch (_) {
      _documents.clear();
    }
    _documents.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persistIndex() async {
    final file = await _indexFile();
    final raw = jsonEncode(_documents.map((d) => d.toJson()).toList());
    await file.writeAsString(raw);
  }

  /// Copies [sourcePaths] into permanent private storage (for the app's own
  /// list) and, best-effort, exports the same pages into the public gallery
  /// so the user can find them in Photos/Files too.
  Future<ScannedDocument> saveDocument({
    required List<String> sourcePaths,
    String? title,
  }) async {
    final dir = await _pagesDir();
    final id = const Uuid().v4();
    final savedPaths = <String>[];

    for (var i = 0; i < sourcePaths.length; i++) {
      final target = File(
        '${dir.path}${Platform.pathSeparator}${id}_p${i.toString().padLeft(3, '0')}.jpg',
      );
      await File(sourcePaths[i]).copy(target.path);
      savedPaths.add(target.path);
    }

    final doc = ScannedDocument(
      id: id,
      title: title ?? _defaultTitle(),
      createdAt: DateTime.now(),
      pagePaths: savedPaths,
      type: FileType.image,
    );

    _documents.insert(0, doc);
    await _persistIndex();
    notifyListeners();

    unawaited(_exportToPublicGallery(savedPaths));
    return doc;
  }

  /// Imports one or more picked files (any type) as the user's own documents.
  /// Unlike [saveDocument] (which bundles a set of images into a single
  /// multi-page scan document), each file becomes its own document: it keeps
  /// its original filename as title and its original file extension, and its
  /// `type` is inferred from the extension so the list row and viewer match.
  Future<void> saveImported(List<String> sourcePaths) async {
    final dir = await _pagesDir();

    for (final source in sourcePaths) {
      final id = const Uuid().v4();
      final type = fileTypeForPath(source);
      final target = File(
        '${dir.path}${Platform.pathSeparator}$id${_suffixFor(type)}',
      );
      await File(source).copy(target.path);

      final doc = ScannedDocument(
        id: id,
        title: PublicFileExporter.basenameOf(source),
        createdAt: DateTime.now(),
        pagePaths: [target.path],
        type: type,
      );
      _documents.insert(0, doc);
      await _persistIndex();
      notifyListeners();

      unawaited(_exportPublicCopy(target.path, type, fileName: doc.title));
    }
  }

  /// Infers what kind of document a picked file is from its file extension.
  static FileType fileTypeForPath(String path) {
    final ext = path.contains('.')
        ? path.split('.').last.toLowerCase()
        : '';
    switch (ext) {
      case 'pdf':
        return FileType.pdf;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return FileType.excel;
      case 'txt':
      case 'md':
      case 'rtf':
      case 'log':
      case 'json':
      case 'xml':
      case 'html':
        return FileType.text;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'bmp':
      case 'heic':
      case 'heif':
        return FileType.image;
      default:
        return FileType.text;
    }
  }

  /// The file extension to keep for the stored copy of an imported file —
  /// the original one for known images, a sensible one for everything else.
  String _suffixFor(FileType type) {
    switch (type) {
      case FileType.pdf:
        return '.pdf';
      case FileType.excel:
        return '.xlsx';
      case FileType.text:
        return '.txt';
      case FileType.image:
        return '.jpg';
    }
  }

  String _mimeFor(FileType type) {
    switch (type) {
      case FileType.pdf:
        return 'application/pdf';
      case FileType.excel:
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case FileType.text:
        return 'text/plain';
      case FileType.image:
        return 'image/jpeg';
    }
  }

  /// Public copy: images go to the system gallery (as scans do), every other
  /// kind goes to the public Downloads folder. Both are best-effort.
  Future<void> _exportPublicCopy(
    String path,
    FileType type, {
    String? fileName,
  }) async {
    if (type == FileType.image) {
      await _exportToPublicGallery([path]);
      return;
    }
    await PublicFileExporter.saveToDownloads(
      path,
      fileName: fileName,
      mimeType: _mimeFor(type),
    );
  }

  /// Best-effort — the app's own copy above is what the UI relies on, so a
  /// gallery export failure (permission denied, no gallery on this device
  /// type, etc.) never blocks or breaks saving.
  Future<void> _exportToPublicGallery(List<String> paths) async {
    try {
      var hasAccess = await Gal.hasAccess();
      if (!hasAccess) hasAccess = await Gal.requestAccess();
      if (!hasAccess) return;

      for (final path in paths) {
        await Gal.putImage(path, album: _galleryAlbum);
      }
    } catch (_) {
      // Ignore — see doc comment above.
    }
  }

  String _defaultTitle() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Scan ${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}:${two(now.minute)}';
  }

  Future<void> rename(String id, String newTitle) async {
    final index = _documents.indexWhere((d) => d.id == id);
    if (index == -1) return;
    final old = _documents[index];
    _documents[index] = ScannedDocument(
      id: old.id,
      title: newTitle,
      createdAt: old.createdAt,
      pagePaths: old.pagePaths,
      type: old.type,
    );
    await _persistIndex();
    notifyListeners();
  }

  /// Deletes the app's private copy. Note: the exported gallery copy is not
  /// deleted here — `gal` doesn't hand back a stable file reference to it,
  /// so removing that one is left to the user via their Gallery app.
  Future<void> delete(String id) async {
    final index = _documents.indexWhere((d) => d.id == id);
    if (index == -1) return;
    final doc = _documents[index];

    for (final path in doc.pagePaths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }

    _documents.removeAt(index);
    await _persistIndex();
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // UI-facing views: converts ScannedDocument -> DocumentItem/MonthGroup
  // ---------------------------------------------------------------------

  static const _monthNames = [
    '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _monthAbbrev = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(date.year, date.month, date.day);
    final diff = today.difference(that).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return '$diff days ago';
    return '${_monthAbbrev[date.month]} ${date.day}, ${date.year}';
  }

  /// Chip labels derived from the documents that actually exist, newest first.
  List<String> get monthFilters {
    final keys = <String>{};
    for (final doc in _documents) {
      keys.add('${_monthAbbrev[doc.createdAt.month]} ${doc.createdAt.year}');
    }
    final sorted = keys.toList()
      ..sort((a, b) {
        final da = _documents.firstWhere((d) => '${_monthAbbrev[d.createdAt.month]} ${d.createdAt.year}' == a).createdAt;
        final db = _documents.firstWhere((d) => '${_monthAbbrev[d.createdAt.month]} ${d.createdAt.year}' == b).createdAt;
        return db.compareTo(da);
      });
    return ['All', ...sorted];
  }

  List<MonthGroup> monthGroups(String filter, {FileType? type}) {
    final filtered = filter == 'All'
        ? _documents
        : _documents
            .where((d) => '${_monthAbbrev[d.createdAt.month]} ${d.createdAt.year}' == filter)
            .toList();

    final typed = type == null
        ? filtered
        : filtered.where((d) => d.type == type).toList();

    final byMonth = <String, List<ScannedDocument>>{};
    for (final doc in typed) {
      final key = '${_monthNames[doc.createdAt.month]} ${doc.createdAt.year}';
      byMonth.putIfAbsent(key, () => []).add(doc);
    }

    final groups = byMonth.entries.map((entry) {
      final items = entry.value.map((doc) {
        return DocumentItem(
          id: doc.id,
          name: doc.title,
          type: doc.type,
          pages: doc.pagePaths.length,
          dateLabel: _dateLabel(doc.createdAt),
          pagePaths: doc.pagePaths,
        );
      }).toList();
      return MonthGroup(entry.key, items);
    }).toList();

    groups.sort((a, b) {
      final da = byMonth[a.month]!.first.createdAt;
      final db = byMonth[b.month]!.first.createdAt;
      return db.compareTo(da);
    });
    return groups;
  }
}