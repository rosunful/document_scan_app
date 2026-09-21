import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum ReviewResultType { retake, delete }

/// What the user decided to do about a specific page while reviewing it.
class ReviewResult {
  final ReviewResultType type;
  final int index;

  const ReviewResult(this.type, this.index);
}

/// Full-screen, swipeable review of the pages captured so far. Pops with a
/// [ReviewResult] if the user chose to retake or delete a page, or with
/// nothing if they just looked and backed out.
class PageReviewScreen extends StatefulWidget {
  final List<String> imagePaths;
  final int initialIndex;

  const PageReviewScreen({super.key, required this.imagePaths, required this.initialIndex});

  @override
  State<PageReviewScreen> createState() => _PageReviewScreenState();
}

class _PageReviewScreenState extends State<PageReviewScreen> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _retake() => Navigator.of(context).pop(ReviewResult(ReviewResultType.retake, _index));

  void _delete() => Navigator.of(context).pop(ReviewResult(ReviewResultType.delete, _index));

  @override
  Widget build(BuildContext context) {
    final colors = context.myAppColors;
    final total = widget.imagePaths.length;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Page ${_index + 1} of $total'),
        actions: [
          IconButton(
            tooltip: 'Delete page',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _delete,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: total,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => InteractiveViewer(
                child: Center(
                  child: Image.file(File(widget.imagePaths[i]), fit: BoxFit.contain),
                ),
              ),
            ),
          ),
          if (total > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Done'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(                        
                        backgroundColor: colors.buttonColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _retake,
                      child: const Text('Retake'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}




