import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scan_documnet_app/provider/theme_provider.dart';
import 'package:scan_documnet_app/theme/app_theme.dart';
import 'package:scan_documnet_app/widgets/home.dart';

import 'repository/document_repository.dart';
import 'widgets/custom_bottom_nav.dart';

void main() async {

  WidgetsFlutterBinding.ensureInitialized();
  final documentRepository = DocumentRepository();
  await documentRepository.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BottomNavProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider.value(value: documentRepository),
        ],
        
      child: RootApp(),
    ),
  );
}

class RootApp extends StatelessWidget {
  const RootApp({super.key});



  @override
  Widget build(BuildContext context) {

  //HERE LETTING THE APP NOW WHICH THEME IS CURRENT APPLYING
  final vm = context.watch<ThemeProvider>();

    return MaterialApp(
      title: 'I Scan',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: vm.themeMode,
      themeAnimationDuration: Duration.zero,
      home: MyApp(),
    );
  }
}
