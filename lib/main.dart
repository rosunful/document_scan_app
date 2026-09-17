import 'package:flutter/material.dart';
import 'package:scan_documnet_app/theme/app_theme.dart';
import 'package:scan_documnet_app/widgets/home.dart';

void main(){
  runApp(Home());
}


class Home extends StatelessWidget{
  const Home({super.key});

  @override
  Widget build (BuildContext context){
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

