import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scan_documnet_app/theme/app_theme.dart';
import '../screen/camera_scan_preview_screen.dart';
import '../screen/document_screen.dart';
import '../screen/home_screen.dart';
import '../screen/preview_screnn.dart';
import 'custom_bottom_nav.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static final _pages = [
    const HomeScreen(),
    const DocumentScreen()
  ];

  Future<void> _onScanTap(BuildContext context) async {
    final pages = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(builder: (_) => const CustomCameraScreen()),
    );
    if (pages == null || pages.isEmpty || !context.mounted) return; 
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ScanPreviewScreen(imagePaths: pages)),
    );
  }

  @override
  Widget build(BuildContext context) {

    //THIS IS FOR THE PASSING THE INDEX FOR THE STACK
    final vm = context.watch<BottomNavProvider>();
    final colors = context.myAppColors;

    return Scaffold(
      body:IndexedStack(
        index: vm.selectedIndex,
        children: _pages,
      ) ,
      bottomNavigationBar: const CustomBottomNav(),
      floatingActionButton: Container(
        height: 60,
        width: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.buttonColor,
        ),
        child: IconButton(
          onPressed: () {
           _onScanTap(context);
          },
          icon: Icon(
            Icons.camera_alt_rounded,
            color: colors.backgroundColor,
            size: 28,
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}
