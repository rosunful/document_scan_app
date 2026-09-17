import 'package:flutter/material.dart';
import '../controller/mock_data.dart';
import '../model/document_model.dart';
import '../theme/app_theme.dart';
import '../widgets/document_pages_widgets/month_section.dart';
import '../widgets/document_pages_widgets/month_chips.dart';
import '../widgets/topbar_section.dart';

class DocumentScreen extends StatefulWidget {
  const DocumentScreen({super.key});

  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<DocumentScreen> {
  String _selectedFilter = 'All';

  void _onDocumentTap(DocumentItem doc) {
    // TODO: open the document viewer.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Open ${doc.name}')),
    );
  }

  void _onDocumentMoreTap(DocumentItem doc) {
    // TODO: show a real actions bottom sheet (rename, share, delete...).
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('More options for ${doc.name}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.myAppColors;
    final groups = MockData.groupsForFilter(_selectedFilter);

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
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: colors.headingTextColor,
                    ),
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
                itemCount: MockData.monthFilters.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final label = MockData.monthFilters[index];
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
              child: ListView.separated(
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