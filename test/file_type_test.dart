import 'package:flutter_test/flutter_test.dart';
import 'package:scan_documnet_app/controller/fileType.dart';
import 'package:scan_documnet_app/model/scanned_document.dart';
import 'package:scan_documnet_app/repository/document_repository.dart';

void main() {
  group('DocumentRepository.fileTypeForPath', () {
    test('detects PDFs', () {
      expect(DocumentRepository.fileTypeForPath('report.PDF'), FileType.pdf);
      expect(DocumentRepository.fileTypeForPath('/tmp/report.pdf'), FileType.pdf);
    });

    test('detects spreadsheets', () {
      expect(DocumentRepository.fileTypeForPath('budget.xlsx'), FileType.excel);
      expect(DocumentRepository.fileTypeForPath('budget.xls'), FileType.excel);
      expect(DocumentRepository.fileTypeForPath('budget.CSV'), FileType.excel);
    });

    test('detects text and notes', () {
      expect(DocumentRepository.fileTypeForPath('notes.txt'), FileType.text);
      expect(DocumentRepository.fileTypeForPath('readme.md'), FileType.text);
      expect(DocumentRepository.fileTypeForPath('dump.log'), FileType.text);
    });

    test('detects images', () {
      expect(DocumentRepository.fileTypeForPath('photo.jpg'), FileType.image);
      expect(DocumentRepository.fileTypeForPath('photo.JPEG'), FileType.image);
      expect(DocumentRepository.fileTypeForPath('drawing.png'), FileType.image);
      expect(DocumentRepository.fileTypeForPath('clip.gif'), FileType.image);
    });

    test('defaults unknown extensions to text', () {
      expect(DocumentRepository.fileTypeForPath('unknown.zzz'), FileType.text);
    });
  });

  group('ScannedDocument type (de)serialization', () {
    test('preserves type through toJson/fromJson', () {
      final real = ScannedDocument(
        id: 'a',
        title: 'budget.xlsx',
        createdAt: DateTime(2026, 1, 5),
        pagePaths: ['/data/scanned_pages/a.xlsx'],
        type: FileType.excel,
      );
      final restored = ScannedDocument.fromJson(real.toJson());
      expect(restored.type, FileType.excel);
      expect(restored.title, 'budget.xlsx');
      expect(restored.pagePaths, ['/data/scanned_pages/a.xlsx']);
    });

    test('defaults to image when type is missing (old index files)', () {
      final restored = ScannedDocument.fromJson({
        'id': 'b',
        'title': 'Scan 2026-01-01',
        'createdAt': '2026-01-01T10:00:00.000',
        'pagePaths': ['/data/scanned_pages/b_p000.jpg'],
      });
      expect(restored.type, FileType.image);
    });
  });
}