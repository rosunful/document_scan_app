import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controller/mock_data.dart';
import '../services/excel_service.dart';
import '../services/pdf_to_image_service.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_bottom_nav.dart';
import '../widgets/home_page_widgets/card.dart';
import '../widgets/topbar_section.dart';
import 'camera_scan_preview_screen.dart';
import 'excel_viewer_screen.dart';
import 'image_to_pdf_preview_screen.dart';
import 'pdf_to_image_screen.dart';
import 'text_extraction_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoading = false;
  String _loadingMessage = '';

  Future<void> _onToolTap(BuildContext context, String title) async {
    switch (title) {
      case 'Image to PDF':
        await _startImageToPdf(context);
        break;
      case 'Scan Document':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TextExtractionScreen()),
        );
        break;
      case 'PDF to Image':
        await _openPdfToImage();
        break;
      case 'Open in Excel':
        await _openExcel();
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$title tapped')),
        );
    }
  }

  /// Picks a PDF directly, renders the pages while showing progress on the
  /// Home screen, then opens the viewer with the pages already loaded.
  Future<void> _openPdfToImage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final path = result.isEmpty ? null : result.single.path;
    if (path == null || !mounted) return;

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Rendering PDF…';
    });
    try {
      final pages = await PdfToImageService.renderPages(path);
      if (!mounted) return;
      if (pages.isEmpty) throw Exception('no pages');
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PdfToImageScreen(initialPages: pages)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this PDF. It may be corrupted or password-protected.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingMessage = '';
        });
      }
    }
  }

  /// Picks an Excel/CSV file directly, parses it while showing progress on
  /// the Home screen, then opens the viewer with the sheets already loaded.
  Future<void> _openExcel() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv'],
    );
    final path = result.isEmpty ? null : result.single.path;
    if (path == null || !mounted) return;

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Opening Excel…';
    });
    try {
      final workbook = await ExcelService.parse(ExcelParseRequest(filePath: path));
      if (!mounted) return;
      if (workbook.sheets.isEmpty) throw Exception('no sheets');
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ExcelViewerScreen(
            initialSheets: workbook.sheets,
            initialFileName: result.single.name,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this file. It may be corrupted or in an unsupported format.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingMessage = '';
        });
      }
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
        child: Stack(
          children: [
            ListView(
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
                  style: TextStyle(
                    fontSize: 13.5,
                    color: colors.descriptionColor,
                    height: 1.35,
                  ),
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
                      .map(
                        (tool) => ToolCard(
                          tool: tool,
                          onTap: () => _onToolTap(context, tool.title),
                        ),
                      )
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
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: colors.buttonColor,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
            if (_isLoading)
              Container(
                color: Colors.black38,
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: colors.buttonColor),
                    const SizedBox(height: 12),
                    Text(
                      _loadingMessage,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}