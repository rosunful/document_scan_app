import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scan_documnet_app/theme/app_theme.dart';

class BottomNavProvider extends ChangeNotifier {
  int _selectedIndex = 0;

  int get selectedIndex => _selectedIndex;

  void setIndex(int index) {
    if (_selectedIndex == index) return;
    _selectedIndex = index;
    notifyListeners();
  }
}

class CustomBottomNav extends StatelessWidget {
  const CustomBottomNav({super.key});

  @override
  Widget build(BuildContext context) {
    //THIS IS FOR THE PASSING THE INDEX TO THE BOTTOM NAVIGATION
    final vm = context.watch<BottomNavProvider>();
    final colors = context.myAppColors;

    return SafeArea(
      child: Container(
        height: 70,
        decoration: BoxDecoration(
          color: colors.searchbarColor,
          border: Border(
            top: BorderSide(
              color: colors.headingTextColor.withValues(alpha: 0.5),
              style: BorderStyle.solid,
              width: 0.2,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: _navitem(
                context,
                icon: Icons.home_filled,
                index: 0,
                vm: vm,
                label: 'home',
              ),
            ),
            SizedBox(width: 40,),
            Expanded(
              child: _navitem(
                context,
                icon: Icons.description_sharp,
                index: 1,
                vm: vm,
                label: 'document',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _navitem(
  BuildContext context, {
  required int index,
  required BottomNavProvider vm,
  required IconData icon,
  required String label,
}) {
  final isActive = index == vm._selectedIndex;
  return GestureDetector(
    onTap: () => vm.setIndex(index),
    behavior: HitTestBehavior.opaque,
    child: SizedBox(
      height: 70,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 26, color: isActive ? Colors.red : Colors.blue),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isActive ? Colors.red : Colors.blue,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
