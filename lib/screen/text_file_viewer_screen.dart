import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Reads an imported text/note file and shows its contents. Decoding happens
/// off the UI thread so a large file doesn't freeze the screen.
class TextFileViewerScreen extends StatefulWidget {
  final String path;
  final String title;

  const TextFileViewerScreen({super.key, required this.path, required this.title});

  @override
  State<TextFileViewerScreen> createState() => _TextFileViewerScreenState();
}

class _TextFileViewerScreenState extends State<TextFileViewerScreen> {
  String _content = '';
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await File(widget.path).readAsBytes();
      final text = await compute(_decode, bytes);
      if (!mounted) return;
      setState(() {
        _content = text;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  static String _decode(Uint8List bytes) =>
      utf8.decode(bytes, allowMalformed: true);

  @override
  Widget build(BuildContext context) {
    final colors = context.myAppColors;

    return Scaffold(
      backgroundColor: colors.backgroundColor,
      appBar: AppBar(
        backgroundColor: colors.backgroundColor,
        foregroundColor: colors.headingTextColor,
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: colors.buttonColor))
          : _failed
              ? Center(
                  child: Text(
                    'Could not read this text file.',
                    style: TextStyle(color: colors.descriptionColor),
                  ),
                )
              : Scrollbar(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      _content,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.5,
                        color: colors.headingTextColor,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
    );
  }
}