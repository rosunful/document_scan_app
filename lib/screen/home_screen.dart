import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controller/mock_data.dart';
import '../model/document_model.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_bottom_nav.dart';
import '../widgets/home_page_widgets/documnet.dart';
import '../widgets/home_page_widgets/card.dart';
import '../widgets/topbar_section.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _onToolTap(BuildContext context, String title) {
    // TODO: route each card to its real flow.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$title tapped')),
    );
  }

  void _onDocumentTap(BuildContext context, DocumentItem doc) {
    // TODO: open the document viewer.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Open ${doc.name}')),
    );
  }

  void _onDocumentMoreTap(BuildContext context, DocumentItem doc) {
    // TODO: show a real actions bottom sheet (rename, share, delete...).
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('More options for ${doc.name}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.myAppColors;

    return Scaffold(
      backgroundColor: colors.backgroundColor,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            AppTopBar(onSearchChanged: (_) {}),
            const SizedBox(height: 22),
            Text(
              'Good morning,',
              style: TextStyle(fontSize: 14.5, color: colors.descriptionColor),
            ),
            const SizedBox(height: 4),
            Text(
              'Scan, convert, get things done',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: colors.headingTextColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Quick tools to manage your documents and extract text from images',
              style: TextStyle(fontSize: 13.5, color: colors.descriptionColor, height: 1.35),
            ),
            const SizedBox(height: 20),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.35,
              children: MockData.tools
                  .map((tool) => ToolCard(
                        tool: tool,
                        onTap: () => _onToolTap(context, tool.title),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Documents',
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    color: colors.headingTextColor,
                  ),
                ),
                GestureDetector(
                  // "See all" jumps to the Documents tab rather than pushing
                  // a second, duplicate screen on the nav stack.
                  onTap: () => context.read<BottomNavProvider>().setIndex(1),
                  child: Row(
                    children: [
                      Text(
                        'See all',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: colors.buttonColor,
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, size: 18, color: colors.buttonColor),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                decoration: BoxDecoration(
                  color: colors.cardColor,
                  border: Border.all(color: colors.borderColor),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < MockData.recentDocuments.length; i++) ...[
                      if (i > 0) Divider(height: 1, thickness: 1, color: colors.borderColor),
                      DocumentTile(
                        document: MockData.recentDocuments[i],
                        onTap: () => _onDocumentTap(context, MockData.recentDocuments[i]),
                        onMoreTap: () => _onDocumentMoreTap(context, MockData.recentDocuments[i]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}