import 'package:flutter/material.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;

  void toggle() {
    _themeMode = (_themeMode == ThemeMode.light)
        ? ThemeMode.dark
        : ThemeMode.light;
    notifyListeners();
  }
}
