import 'dart:io';
import 'package:flutter/material.dart';

class SavedDocumentViewerScreen extends StatelessWidget {
  final String title;
  final List<String> pagePaths;

  const SavedDocumentViewerScreen({super.key, required this.title, required this.pagePaths});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(title)),
      body: PageView.builder(
        itemCount: pagePaths.length,
        itemBuilder: (context, i) => InteractiveViewer(
          child: Center(child: Image.file(File(pagePaths[i]), fit: BoxFit.contain)),
        ),
      ),
    );
  }
}