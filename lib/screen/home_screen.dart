import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controller/mock_data.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_bottom_nav.dart';
import '../widgets/home_page_widgets/card.dart';
import '../widgets/topbar_section.dart';
import 'camera_scan_preview_screen.dart';
import 'image_to_pdf_preview_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _onToolTap(BuildContext context, String title) async {
    switch (title) {
      case 'Image to PDF':
        await _startImageToPdf(context);
        break;
      case 'Scan Document':
        // Existing scan flow — leave as-is / wire to your CustomCameraScreen
        // -> ScanPreviewScreen path the same way MyApp's FAB does.
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$title tapped')),
        );
    }
  }

  /// Camera opens first; the user can capture pages there, or tap the
  /// gallery icon inside the preview screen if they'd rather pick existing
  /// photos instead of shooting new ones.
  Future<void> _startImageToPdf(BuildContext context) async {
    final captured = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(builder: (_) => const CustomCameraScreen()),
    );
    if (captured == null || captured.isEmpty || !context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImageToPdfPreviewScreen(imagePaths: captured),
      ),
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
          ],
        ),
      ),
    );
  }
}