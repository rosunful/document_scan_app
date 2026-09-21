import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SavedDocumentViewerScreen extends StatefulWidget {
  final String title;
  final List<String> pagePaths;

  const SavedDocumentViewerScreen({super.key, required this.title, required this.pagePaths});

  @override
  State<SavedDocumentViewerScreen> createState() => _SavedDocumentViewerScreenState();
}

class _SavedDocumentViewerScreenState extends State<SavedDocumentViewerScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.myAppColors;
    final total = widget.pagePaths.length;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: total > 1 ? Text('Page ${_index + 1} of $total') : Text(widget.title),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: total,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => InteractiveViewer(
                child: Center(child: Image.file(File(widget.pagePaths[i]), fit: BoxFit.contain)),
              ),
            ),
          ),
          if (total > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(total, (i) {
                  final active = i == _index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active ? colors.buttonColor : Colors.white38,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}