import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../controller/fileType.dart' as docTypes;
import '../model/document_model.dart';
import '../model/tool_model.dart';
import '../repository/document_repository.dart';
import '../services/excel_service.dart';
import '../services/public_file_exporter.dart';
import '../theme/app_theme.dart';
import '../widgets/document_pages_widgets/month_section.dart';
import '../widgets/document_pages_widgets/month_chips.dart';
import '../widgets/topbar_section.dart';
import 'excel_viewer_screen.dart';
import 'profile_screen.dart';
import 'saved_document_viewer_screen.dart';
import 'saved_pdf_viewer_screen.dart';
import 'text_file_viewer_screen.dart';

class DocumentScreen extends StatefulWidget {
  const DocumentScreen({super.key});

  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<DocumentScreen> {
  // Sentinel meaning "user explicitly collapsed the list" — month names are
  // always letters/digits, so this can never collide with a real group.
  static const String _noneGroup = '\u0000';
  static const List<docTypes.FileType> _typeOrder = [
    docTypes.FileType.pdf,
    docTypes.FileType.excel,
    docTypes.FileType.text,
    docTypes.FileType.image,
  ];

  String _selectedFilter = 'All';
  docTypes.FileType? _selectedType;
  String? _expandedGroup;
  final ImagePicker _picker = ImagePicker();

  Future<void> _importImages() async {
    try {
      final picked = await _picker.pickMultiImage(imageQuality: 95);
      if (picked.isEmpty || !mounted) return;
      await _saveImported(picked.map((x) => x.path).toList());
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't access your photos.")),
      );
    }
  }

  Future<void> _importFiles() async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      final paths = files.map((f) => f.path).whereType<String>().toList();
      if (paths.isEmpty || !mounted) return;

      final repository = context.read<DocumentRepository>();
      await repository.saveImported(paths);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${paths.length} file${paths.length == 1 ? '' : 's'} imported'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't access your files.")),
      );
    }
  }

  Future<void> _saveImported(List<String> paths) async {
    final repository = context.read<DocumentRepository>();
    await repository.saveDocument(sourcePaths: paths);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${paths.length} image${paths.length == 1 ? '' : 's'} imported'),
      ),
    );
  }

  void _onDocumentTap(DocumentItem doc) {
    final firstPath = doc.pagePaths.first;
    switch (doc.type) {
      case docTypes.FileType.pdf:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SavedPdfViewerScreen(path: firstPath, title: doc.name),
          ),
        );
      case docTypes.FileType.excel:
        _openExcel(doc);
      case docTypes.FileType.text:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TextFileViewerScreen(path: firstPath, title: doc.name),
          ),
        );
      case docTypes.FileType.image:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SavedDocumentViewerScreen(title: doc.name, pagePaths: doc.pagePaths),
          ),
        );
    }
  }

  Future<void> _openExcel(DocumentItem doc) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Dialog(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Opening spreadsheet…'),
            ],
          ),
        ),
      ),
    );
    try {
      final workbook = await ExcelService.parse(
        ExcelParseRequest(filePath: doc.pagePaths.first),
      );
      if (!mounted) return;
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      if (workbook.sheets.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No readable sheets found in this file.')),
        );
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ExcelViewerScreen(
            initialSheets: workbook.sheets,
            initialFileName: doc.name,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this spreadsheet.')),
      );
    }
  }

  void _onDocumentMoreTap(DocumentItem doc) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share_rounded),
              title: const Text('Share'),
              onTap: () {
                Navigator.pop(sheetContext);
                _shareDocument(doc);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmDelete(doc);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareDocument(DocumentItem doc) async {
    try {
      final names = [
        for (final path in doc.pagePaths)
          _safeFileName(PublicFileExporter.basenameOf(path)),
      ];
      await SharePlus.instance.share(
        ShareParams(
          files: [for (final path in doc.pagePaths) XFile(path)],
          fileNameOverrides: names,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not share the document.')),
      );
    }
  }

  String _safeFileName(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

  Future<void> _confirmDelete(DocumentItem doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete document?'),
        content: Text('"${doc.name}" and all of its pages will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final repository = context.read<DocumentRepository>();
      await repository.delete(doc.id);
    }
  }

  /// Bottom sheet listing every month/year that has documents. Picking one
  /// narrows the list; "All" clears the month filter. Never hidden — it's
  /// the pinned button at the end of the type-chip row.
  Future<void> _openMonthFilter() async {
    final repository = context.read<DocumentRepository>();
    final options = repository.monthFilters;
    final colors = context.myAppColors;

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: colors.cardColor,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Filter by month',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colors.headingTextColor,
                ),
              ),
            ),
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0) Divider(height: 1, color: colors.borderColor),
              ListTile(
                leading: Icon(
                  options[i] == 'All'
                      ? Icons.clear_all_rounded
                      : Icons.calendar_month_rounded,
                  color: _selectedFilter == options[i]
                      ? colors.buttonColor
                      : colors.descriptionColor,
                ),
                title: Text(
                  options[i],
                  style: TextStyle(color: colors.headingTextColor),
                ),
                trailing: _selectedFilter == options[i]
                    ? Icon(Icons.check_rounded, color: colors.buttonColor)
                    : null,
                onTap: () => Navigator.pop(sheetContext, options[i]),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (selected == null || !mounted) return;
    setState(() => _selectedFilter = selected);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.myAppColors;
    final repository = context.watch<DocumentRepository>();

    if (!repository.isLoaded) {
      return Scaffold(
        backgroundColor: colors.backgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final filters = repository.monthFilters;
    if (!filters.contains(_selectedFilter)) _selectedFilter = 'All';

    final typeOptions = <MapEntry<String, docTypes.FileType?>>[
      const MapEntry('All', null),
      for (final t in _typeOrder) MapEntry(t.label, t),
    ];

    final groups = repository.monthGroups(_selectedFilter, type: _selectedType);

    // Accordion: one month open at a time. Null state means "open the newest
    // group by default"; the sentinel means "user collapsed everything".
    String? expanded;
    if (groups.isNotEmpty) {
      if (_expandedGroup == _noneGroup) {
        expanded = null;
      } else if (_expandedGroup == null) {
        expanded = groups.first.month;
      } else {
        expanded =
            groups.any((g) => g.month == _expandedGroup) ? _expandedGroup : groups.first.month;
      }
    }

    return Scaffold(
      backgroundColor: colors.backgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Pinned header: profile, search, theme toggle.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: AppTopBar(
                onAvatarTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                ),
                onSearchChanged: (_) {},
              ),
            ),
            const SizedBox(height: 10,),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  _buildImportGrid(colors),
                  const SizedBox(height: 18),
                  Text(
                    'All Documents',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: colors.headingTextColor),
                  ),
                  const SizedBox(height: 6),
                  // Type chips scroll horizontally; the month filter button
                  // sits outside the scroller so it's always on screen.
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 42,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: typeOptions.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final choice = typeOptions[index];
                              final selected = _selectedType == choice.value;
                              return MonthFilterChip(
                                label: choice.key,
                                selected: selected,
                                onTap: () => setState(() {
                                  _selectedType = choice.value;
                                  _expandedGroup = null;
                                }),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _openMonthFilter,
                        child: Container(
                          height: 42,
                          width: 42,
                          decoration: BoxDecoration(
                            color: _selectedFilter == 'All'
                                ? colors.cardColor
                                : colors.buttonColor,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _selectedFilter == 'All'
                                  ? colors.borderColor
                                  : colors.buttonColor,
                            ),
                          ),
                          child: Icon(
                            Icons.filter_alt_rounded,
                            size: 20,
                            color: _selectedFilter == 'All'
                                ? colors.headingTextColor
                                : Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (groups.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 48),
                      child: Center(
                        child: Text(
                          (_selectedType != null || _selectedFilter != 'All')
                              ? 'No documents match this filter'
                              : 'No scanned documents yet',
                          style: TextStyle(color: colors.descriptionColor),
                        ),
                      ),
                    )
                  else
                    for (var i = 0; i < groups.length; i++) ...[
                      MonthSection(
                        group: groups[i],
                        expanded: expanded == groups[i].month,
                        onToggle: () => setState(() {
                          if (expanded == groups[i].month) {
                            _expandedGroup = _noneGroup;
                          } else {
                            _expandedGroup = groups[i].month;
                          }
                        }),
                        onTapDocument: _onDocumentTap,
                        onMoreTapDocument: _onDocumentMoreTap,
                      ),
                      if (i < groups.length - 1) const SizedBox(height: 16),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Big import options, matching the Home screen's tool cards but a touch
  /// smaller and sized to their own content so they never overflow.
  Widget _buildImportGrid(CustomAppColors colors) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _ImportToolCard(
            tool: const ToolItem(
              icon: Icons.image_rounded,
              title: 'Import Image',
              subtitle: 'Pick photos from gallery',
              iconBackground: Color(0xFFE1EDFF),
              iconColor: Color(0xFF3B82F6),
            ),
            onTap: _importImages,
            colors: colors,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ImportToolCard(
            tool: const ToolItem(
              icon: Icons.insert_drive_file_rounded,
              title: 'Import File',
              subtitle: 'PDF, Excel, text, images',
              iconBackground: Color(0xFFDEF3E6),
              iconColor: Color(0xFF1E9254),
            ),
            onTap: _importFiles,
            colors: colors,
          ),
        ),
      ],
    );
  }
}

class _ImportToolCard extends StatelessWidget {
  final ToolItem tool;
  final VoidCallback? onTap;
  final CustomAppColors colors;

  const _ImportToolCard({
    required this.tool,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.cardColor,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: tool.iconBackground,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(tool.icon, color: tool.iconColor, size: 18),
              ),
              const SizedBox(height: 10),
              Text(
                tool.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: colors.headingTextColor),
              ),
              const SizedBox(height: 3),
              Text(
                tool.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: colors.descriptionColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}