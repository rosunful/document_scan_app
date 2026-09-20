import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/excel_service.dart';
import '../theme/app_theme.dart';

class ExcelViewerScreen extends StatefulWidget {
  const ExcelViewerScreen({super.key});

  @override
  State<ExcelViewerScreen> createState() => _ExcelViewerScreenState();
}

enum _State { pickFile, loading, done, error }

/// One-step undo record: a full snapshot of a sheet's rows before an edit.
class _UndoSnapshot {
  final int sheetIndex;
  final List<List<String>> rows;
  const _UndoSnapshot(this.sheetIndex, this.rows);
}

class _ExcelViewerScreenState extends State<ExcelViewerScreen> {
  _State _state = _State.pickFile;
  List<ParsedSheet> _sheets = [];
  int _sheetIndex = 0;
  String _errorMessage = '';
  String? _fileName;
  bool _dirty = false;
  bool _saving = false;
  _UndoSnapshot? _undo;

  Future<void> _pickAndParse() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv'],
    );
    final path = result.isEmpty ? null : result.single.path;
    if (path == null || !mounted) return;

    setState(() {
      _state = _State.loading;
      _fileName = result.single.name;
    });

    try {
      final workbook = await ExcelService.parse(ExcelParseRequest(filePath: path));
      if (!mounted) return;
      if (workbook.sheets.isEmpty) {
        setState(() {
          _state = _State.error;
          _errorMessage = 'No readable sheets found in this file.';
        });
        return;
      }
      setState(() {
        _sheets = workbook.sheets;
        _sheetIndex = 0;
        _dirty = false;
        _undo = null;
        _state = _State.done;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _state = _State.error;
        _errorMessage = 'Could not open this file. It may be corrupted or in an unsupported format.';
      });
    }
  }

  ParsedSheet get _sheet => _sheets[_sheetIndex];

  void _snapshotForUndo() {
    _undo = _UndoSnapshot(_sheetIndex, _sheet.rows.map((r) => List<String>.of(r)).toList());
  }

  void _undoLast() {
    final snapshot = _undo;
    if (snapshot == null) return;
    setState(() {
      _sheets[snapshot.sheetIndex] = ParsedSheet(name: _sheets[snapshot.sheetIndex].name, rows: snapshot.rows);
      _undo = null;
      _dirty = true;
    });
  }

  void _editCell(int row, int col, String newValue) {
    _snapshotForUndo();
    setState(() {
      final rows = _sheet.rows;
      while (row >= rows.length) rows.add([]);
      final targetRow = rows[row];
      while (col >= targetRow.length) targetRow.add('');
      targetRow[col] = newValue;
      _dirty = true;
    });
  }

  void _addRow() {
    _snapshotForUndo();
    setState(() {
      _sheet.rows.add(List.filled(_sheet.columnCount, ''));
      _dirty = true;
    });
  }

  void _deleteRow(int row) {
    _snapshotForUndo();
    setState(() {
      _sheet.rows.removeAt(row);
      _dirty = true;
    });
  }

  void _addColumn() {
    _snapshotForUndo();
    setState(() {
      for (final row in _sheet.rows) {
        row.add('');
      }
      _dirty = true;
    });
  }

  void _deleteColumn(int col) {
    _snapshotForUndo();
    setState(() {
      for (final row in _sheet.rows) {
        if (col < row.length) row.removeAt(col);
      }
      _dirty = true;
    });
  }

Future<void> _saveAs() async {
  setState(() => _saving = true);
  try {
    final baseName = (_fileName ?? 'document.xlsx')
        .replaceAll(RegExp(r'\.(xlsx|xls|csv)$', caseSensitive: false), '');
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final newName =
        '${baseName}_edited_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}.xlsx';

    final path = await ExcelService.saveAsNewFile(_sheets, newName);
    if (!mounted) return;

    setState(() => _dirty = false);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], fileNameOverrides: [newName]),
    );
  } catch (_) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the file.')),
      );
    }
  } finally {
    if (mounted) setState(() => _saving = false);
  }
}

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved edits. Leaving now will lose them.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep Editing')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Discard')),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.myAppColors;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: colors.backgroundColor,
        appBar: AppBar(
          backgroundColor: colors.backgroundColor,
          foregroundColor: colors.headingTextColor,
          elevation: 0,
          title: Text(_fileName ?? 'Open in Excel', overflow: TextOverflow.ellipsis),
          actions: [
            if (_state == _State.done) ...[
              IconButton(
                tooltip: 'Undo',
                icon: const Icon(Icons.undo_rounded),
                onPressed: _undo == null ? null : _undoLast,
              ),
              IconButton(
                tooltip: 'Open another file',
                icon: const Icon(Icons.folder_open_rounded),
                onPressed: () async {
                  if (await _confirmDiscard()) _pickAndParse();
                },
              ),
            ],
          ],
        ),
        body: switch (_state) {
          _State.pickFile => _buildPicker(colors),
          _State.loading => Center(child: CircularProgressIndicator(color: colors.buttonColor)),
          _State.error => _buildError(colors),
          _State.done => _buildWorkbook(colors),
        },
        bottomNavigationBar: _state == _State.done
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.buttonColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: (_saving || !_dirty) ? null : _saveAs,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save_alt_rounded),
                    label: Text(_dirty ? 'Save as New File' : 'No Changes to Save'),
                  ),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildPicker(CustomAppColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.grid_on_rounded, size: 56, color: colors.descriptionColor),
            const SizedBox(height: 16),
            Text(
              'Choose an Excel or CSV file to view and edit',
              style: TextStyle(color: colors.headingTextColor, fontSize: 15),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.buttonColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
              onPressed: _pickAndParse,
              child: const Text('Choose File'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(CustomAppColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: colors.descriptionColor),
            const SizedBox(height: 16),
            Text(_errorMessage, textAlign: TextAlign.center, style: TextStyle(color: colors.headingTextColor)),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: colors.buttonColor, foregroundColor: Colors.white),
              onPressed: () => setState(() => _state = _State.pickFile),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkbook(CustomAppColors colors) {
    return Column(
      children: [
        if (_sheets.length > 1)
          SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              itemCount: _sheets.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final selected = i == _sheetIndex;
                return GestureDetector(
                  onTap: () => setState(() => _sheetIndex = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? colors.buttonColor : colors.cardColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: selected ? colors.buttonColor : colors.borderColor),
                    ),
                    child: Text(
                      _sheets[i].name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : colors.headingTextColor,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            children: [
              _ActionChip(icon: Icons.playlist_add_rounded, label: 'Add Row', onTap: _addRow, colors: colors),
              const SizedBox(width: 8),
              _ActionChip(icon: Icons.view_column_rounded, label: 'Add Column', onTap: _addColumn, colors: colors),
            ],
          ),
        ),
        Expanded(
          child: _EditableSheetTable(
            sheet: _sheet,
            colors: colors,
            onCellEdit: _editCell,
            onDeleteRow: _deleteRow,
            onDeleteColumn: _deleteColumn,
          ),
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final CustomAppColors colors;

  const _ActionChip({required this.icon, required this.label, required this.onTap, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.cardColor,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colors.borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: colors.headingTextColor),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12.5, color: colors.headingTextColor)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Editable grid: tapping a cell opens an inline text field; long-pressing
/// a row/column number offers delete. Both-axis scroll since real sheets
/// are usually bigger than the screen.
class _EditableSheetTable extends StatelessWidget {
  final ParsedSheet sheet;
  final CustomAppColors colors;
  final void Function(int row, int col, String value) onCellEdit;
  final void Function(int row) onDeleteRow;
  final void Function(int col) onDeleteColumn;

  const _EditableSheetTable({
    required this.sheet,
    required this.colors,
    required this.onCellEdit,
    required this.onDeleteRow,
    required this.onDeleteColumn,
  });

  Future<void> _openCellEditor(BuildContext context, int row, int col, String currentValue) async {
    final controller = TextEditingController(text: currentValue);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Row ${row + 1}, Column ${col + 1}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null) onCellEdit(row, col, result);
  }

  @override
  Widget build(BuildContext context) {
    if (sheet.rows.isEmpty) {
      return Center(
        child: Text('This sheet is empty', style: TextStyle(color: colors.descriptionColor)),
      );
    }

    final columnCount = sheet.columnCount;

    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          child: Table(
            border: TableBorder.all(color: colors.borderColor, width: 0.6),
            defaultColumnWidth: const IntrinsicColumnWidth(),
            children: [
              for (var r = 0; r < sheet.rows.length; r++)
                TableRow(
                  decoration: BoxDecoration(color: r == 0 ? colors.longRectangleColor : colors.cardColor),
                  children: [
                    for (var c = 0; c < columnCount; c++)
                      InkWell(
                        onTap: () => _openCellEditor(
                          context,
                          r,
                          c,
                          c < sheet.rows[r].length ? sheet.rows[r][c] : '',
                        ),
                        onLongPress: () => _showRowColumnMenu(context, r, c),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Text(
                            c < sheet.rows[r].length ? sheet.rows[r][c] : '',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: r == 0 ? FontWeight.w700 : FontWeight.w400,
                              color: colors.headingTextColor,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRowColumnMenu(BuildContext context, int row, int col) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: Text('Delete Row ${row + 1}'),
              onTap: () {
                Navigator.pop(sheetContext);
                onDeleteRow(row);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: Text('Delete Column ${col + 1}'),
              onTap: () {
                Navigator.pop(sheetContext);
                onDeleteColumn(col);
              },
            ),
          ],
        ),
      ),
    );
  }
}