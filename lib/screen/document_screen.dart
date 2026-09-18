import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../model/document_model.dart';
import '../repository/document_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/document_pages_widgets/month_section.dart';
import '../widgets/document_pages_widgets/month_chips.dart';
import '../widgets/topbar_section.dart';
import 'saved_document_viewer_screen.dart';

class DocumentScreen extends StatefulWidget {
  const DocumentScreen({super.key});

  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<DocumentScreen> {
  String _selectedFilter = 'All';

  void _onDocumentTap(DocumentItem doc) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SavedDocumentViewerScreen(title: doc.name, pagePaths: doc.pagePaths),
      ),
    );
  }

  void _onDocumentMoreTap(DocumentItem doc) {
    final repository = context.read<DocumentRepository>();
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Delete'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await repository.delete(doc.id);
              },
            ),
          ],
        ),
      ),
    );
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
    final groups = repository.monthGroups(_selectedFilter);

    return Scaffold(
      backgroundColor: colors.backgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: AppTopBar(onSearchChanged: (_) {}),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'All Documents',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: colors.headingTextColor),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Browse and manage your scanned and converted files',
                    style: TextStyle(fontSize: 13.5, color: colors.descriptionColor),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: filters.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final label = filters[index];
                  return MonthFilterChip(
                    label: label,
                    selected: _selectedFilter == label,
                    onTap: () => setState(() => _selectedFilter = label),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: groups.isEmpty
                  ? Center(
                      child: Text(
                        'No scanned documents yet',
                        style: TextStyle(color: colors.descriptionColor),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: groups.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        final group = groups[index];
                        return MonthSection(
                          group: group,
                          onTapDocument: _onDocumentTap,
                          onMoreTapDocument: _onDocumentMoreTap,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}