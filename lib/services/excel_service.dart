import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// One parsed sheet, as mutable string rows — everything gets stringified
/// (numbers, dates, formulas' cached values) so the table widget doesn't
/// need to know about cell types. This is a plain, editable in-memory copy;
/// nothing here touches the original file until an explicit save-as.
class ParsedSheet {
  final String name;
  final List<List<String>> rows;

  const ParsedSheet({required this.name, required this.rows});

  int get columnCount => rows.isEmpty ? 0 : rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);

  ParsedSheet clone() => ParsedSheet(name: name, rows: rows.map((r) => List<String>.of(r)).toList());
}

class ParsedWorkbook {
  final List<ParsedSheet> sheets;

  const ParsedWorkbook({required this.sheets});
}

class ExcelParseRequest {
  final String filePath;
  const ExcelParseRequest({required this.filePath});
}

/// Plain-data request for the write isolate — VecMat-style objects from the
/// `excel` package aren't safe to pass across isolates, so this carries
/// only primitive data and the encode happens inside the isolate itself.
class ExcelWriteRequest {
  final List<ParsedSheetData> sheets;
  const ExcelWriteRequest({required this.sheets});
}

class ParsedSheetData {
  final String name;
  final List<List<String>> rows;
  const ParsedSheetData({required this.name, required this.rows});
}

class ExcelService {
  ExcelService._();

  /// Parses off the UI thread — a large workbook is real CPU work and
  /// would otherwise freeze the UI while it decodes.
  static Future<ParsedWorkbook> parse(ExcelParseRequest request) => compute(_parseEntry, request);

  /// Encodes the given sheets into a fresh .xlsx and writes it to a new
  /// file in app storage. Never touches the original — this is always a
  /// save-as. Returns the new file's path.
  static Future<String> saveAsNewFile(List<ParsedSheet> sheets, String fileName) async {
    final data = sheets.map((s) => ParsedSheetData(name: s.name, rows: s.rows)).toList();
    final bytes = await compute(_encodeEntry, ExcelWriteRequest(sheets: data));

    final dir = await getApplicationDocumentsDirectory();
    final outDir = Directory('${dir.path}${Platform.pathSeparator}excel_documents');
    if (!await outDir.exists()) await outDir.create(recursive: true);

    final file = File('${outDir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}

ParsedWorkbook _parseEntry(ExcelParseRequest request) {
  final bytes = File(request.filePath).readAsBytesSync();
  final workbook = xl.Excel.decodeBytes(bytes);

  final sheets = <ParsedSheet>[];
  for (final name in workbook.tables.keys) {
    final table = workbook.tables[name];
    if (table == null) continue;

    final rows = <List<String>>[];
    for (final row in table.rows) {
      rows.add(row.map((cell) => _cellToString(cell)).toList(growable: true));
    }
    if (rows.any((r) => r.any((c) => c.isNotEmpty))) {
      sheets.add(ParsedSheet(name: name, rows: rows));
    }
  }

  return ParsedWorkbook(sheets: sheets);
}

String _cellToString(xl.Data? cell) {
  final value = cell?.value;
  if (value == null) return '';
  return value.toString();
}

Uint8List _encodeEntry(ExcelWriteRequest request) {
  final workbook = xl.Excel.createExcel();

  // createExcel() ships with one default sheet ("Sheet1") — drop it once
  // we've added the real ones, or you end up with a stray blank sheet.
  final defaultSheetName = workbook.getDefaultSheet();

  for (final sheetData in request.sheets) {
    final sheet = workbook[sheetData.name];
    for (var r = 0; r < sheetData.rows.length; r++) {
      final row = sheetData.rows[r];
      for (var c = 0; c < row.length; c++) {
        final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
        cell.value = xl.TextCellValue(row[c]);
      }
    }
  }

  if (defaultSheetName != null && request.sheets.every((s) => s.name != defaultSheetName)) {
    workbook.delete(defaultSheetName);
  }

  final bytes = workbook.encode();
  if (bytes == null) throw Exception('Failed to encode workbook');
  return Uint8List.fromList(bytes);
}