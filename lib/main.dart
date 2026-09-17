import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scan_documnet_app/theme/app_theme.dart';
import 'package:scan_documnet_app/widgets/home.dart';

import 'widgets/custom_bottom_nav.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => BottomNavProvider())],
      child: RootApp(),
    ),
  );
}

class RootApp extends StatelessWidget {
  const RootApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'I Scan',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeAnimationDuration: Duration.zero,
      home: MyApp(),
    );
  }
}
