import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scan_documnet_app/theme/app_theme.dart';
import '../screen/document_screen.dart';
import '../screen/home_screen.dart';
import 'custom_bottom_nav.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static final _pages = [
    const HomeScreen(),
    const DocumentScreen()
  ];

  @override
  Widget build(BuildContext context) {

    //THIS IS FOR THE PASSING THE INDEX FOR THE STACK
    final vm = context.watch<BottomNavProvider>();
    final colors = context.myAppColors;

    return SafeArea(
      child: Scaffold(
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
            color: colors.bottomnaveColor,
            border: Border.all(
              style: BorderStyle.solid,
              width: 1.5,
              color: const Color(0xFFE3EBE8),
            ),
          ),
          child: IconButton(
            onPressed: () {
              //do something here
            },
            icon: Icon(
              Icons.camera_alt_rounded,
              color: colors.buttonColor,
              size: 28,
            ),
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      ),
    );
  }
}
