import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/enchance_service.dart';
import '../theme/app_theme.dart';

class EnhanceScreen extends StatefulWidget {
  final List<String> imagePaths;

  const EnhanceScreen({super.key, required this.imagePaths});

  @override
  State<EnhanceScreen> createState() => _EnhanceScreenState();
}

class _EnhancePage {
  final String sourcePath;
  EnhanceSettings settings;
  Uint8List? previewSource;
  Uint8List? preview;
  Map<EnhanceFilter, Uint8List> thumbs = {};
  int token = 0;

  _EnhancePage(this.sourcePath, {this.settings = const EnhanceSettings()});
}

const _presetDescriptions = {
  EnhanceFilter.magic: 'Removes shadows, keeps colour — best for most documents',
  EnhanceFilter.clean: 'Whitens the paper and sharpens text — a fresh, scanned look',
  EnhanceFilter.blackWhite: 'High contrast — best for text-only pages',
  EnhanceFilter.grayscale: 'Softer than B&W — good for printed docs with images',
  EnhanceFilter.original: 'No enhancement, just your crop',
};

class _EnhanceScreenState extends State<EnhanceScreen> {
  static const _previewWidth = 900;
  static const _thumbWidth = 220;

  final PageController _controller = PageController();
  late final List<_EnhancePage> _pages;

  int _index = 0;
  bool _rendering = false;
  bool _saving = false;
  int _savedCount = 0;
  bool _tuning = false;

  @override
  void initState() {
    super.initState();
    _pages = widget.imagePaths.map(_EnhancePage.new).toList();
    _prepare(0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  _EnhancePage get _page => _pages[_index];

  Future<void> _prepare(int index) async {
    final page = _pages[index];
    if (page.previewSource == null) {
      if (mounted) setState(() => _rendering = true);
      final bytes = await EnhanceService.downscale(
        EnhanceDownscaleRequest(sourcePath: page.sourcePath, width: _previewWidth),
      );
      if (!mounted) return;
      if (bytes == null) {
        setState(() => _rendering = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't read this page.")),
        );
        return;
      }
      page.previewSource = bytes;
    }
    await _render(index);
    unawaited(_buildThumbs(index));
  }

  Future<void> _render(int index) async {
    final page = _pages[index];
    final source = page.previewSource;
    if (source == null) return;

    final token = ++page.token;
    if (mounted && index == _index) setState(() => _rendering = true);

    final bytes = await EnhanceService.preview(
      EnhancePreviewRequest(bytes: source, settings: page.settings),
    );

    if (!mounted || token != page.token) return;
    setState(() {
      if (bytes != null) page.preview = bytes;
      if (index == _index) _rendering = false;
    });
  }

  Future<void> _buildThumbs(int index) async {
    final page = _pages[index];
    if (page.thumbs.isNotEmpty || page.previewSource == null) return;

    final tiny = await EnhanceService.downscaleBytes(page.previewSource!, _thumbWidth);
    final source = tiny ?? page.previewSource!;

    for (final filter in EnhanceFilter.values) {
      final bytes = await EnhanceService.preview(
        EnhancePreviewRequest(bytes: source, settings: EnhanceSettings(filter: filter), quality: 75),
      );
      if (!mounted) return;
      if (bytes != null) setState(() => page.thumbs[filter] = bytes);
    }
  }

  void _choosePreset(EnhanceFilter filter) {
    setState(() => _page.settings = _page.settings.copyWith(filter: filter));
    _render(_index);
  }

  void _rotate() {
    setState(() {
      _page.settings = _page.settings.copyWith(quarterTurns: (_page.settings.quarterTurns + 1) % 4);
    });
    _render(_index);
  }

  void _applyToAll() {
    final settings = _page.settings;
    for (var i = 0; i < _pages.length; i++) {
      if (i == _index) continue;
      _pages[i].settings = _pages[i].settings.copyWith(
            filter: settings.filter,
            brightness: settings.brightness,
            contrast: settings.contrast,
            saturation: settings.saturation,
          );
    }
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Applied to every page')),
    );
    for (var i = 0; i < _pages.length; i++) {
      if (i != _index && _pages[i].previewSource != null) unawaited(_render(i));
    }
  }

  void _setAdjustment(EnhanceSettings Function(EnhanceSettings) builder) {
    setState(() => _page.settings = builder(_page.settings));
  }

  void _resetAdjustments() {
    final s = _page.settings;
    setState(() {
      _page.settings = s.copyWith(brightness: 0, contrast: 0, saturation: 0);
    });
    _render(_index);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Adjustments reset')),
    );
  }

  String _targetPath(String source) {
    final file = File(source);
    final name = file.uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    final base = dot == -1 ? name : name.substring(0, dot);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return '${file.parent.path}${Platform.pathSeparator}${base}_enh_$stamp.jpg';
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _savedCount = 0;
    });

    final results = <String>[];
    for (final page in _pages) {
      if (page.settings.isUntouched) {
        results.add(page.sourcePath);
      } else {
        final path = await EnhanceService.writeEnhanced(
          EnhanceFileRequest(
            sourcePath: page.sourcePath,
            targetPath: _targetPath(page.sourcePath),
            settings: page.settings,
          ),
        );
        results.add(path ?? page.sourcePath);
      }
      if (!mounted) return;
      setState(() => _savedCount++);
    }

    if (!mounted) return;
    Navigator.of(context).pop(results);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.myAppColors;
    final total = _pages.length;

    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        backgroundColor: colors.backgroundColor,
        appBar: AppBar(
          backgroundColor: colors.backgroundColor,
          foregroundColor: colors.headingTextColor,
          title: Text(
            total > 1 ? 'Enhance — page ${_index + 1} of $total' : 'Enhance',
            style: const TextStyle(fontSize: 16),
          ),
          actions: [
            IconButton(
              tooltip: 'Tune',
              icon: Icon(
                _tuning ? Icons.tune_rounded : Icons.tune_outlined,
                color: _tuning ? colors.buttonColor : colors.headingTextColor,
              ),
              onPressed: _saving ? null : () => setState(() => _tuning = !_tuning),
            ),
            IconButton(
              tooltip: 'Rotate',
              icon: const Icon(Icons.rotate_right_rounded),
              onPressed: _saving ? null : _rotate,
            ),
            if (total > 1)
              IconButton(
                tooltip: 'Apply to all pages',
                icon: const Icon(Icons.done_all_rounded),
                onPressed: _saving ? null : _applyToAll,
              ),
          ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: total,
                    onPageChanged: (i) {
                      setState(() => _index = i);
                      _prepare(i);
                    },
                    itemBuilder: (context, i) {
                      final page = _pages[i];
                      final bytes = page.preview;
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          if (bytes != null)
                            InteractiveViewer(
                              child: Center(
                                child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
                              ),
                            )
                          else
                            Center(child: CircularProgressIndicator(color: colors.buttonColor)),
                          if (i == _index && _rendering && bytes != null)
                            Positioned(
                              top: 12,
                              right: 12,
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colors.headingTextColor.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                _buildPresetPicker(colors),
                if (_tuning) _buildTuning(colors),
                _buildActions(colors, total),
              ],
            ),
            if (_saving)
              Container(
                color: colors.backgroundColor.withValues(alpha: 0.92),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: colors.buttonColor),
                    const SizedBox(height: 16),
                    Text(
                      'Enhancing page ${_savedCount + 1} of $total…',
                      style: TextStyle(
                        color: colors.headingTextColor.withValues(alpha: 0.75),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetPicker(CustomAppColors colors) {
    final page = _page;
    final selected = page.settings.filter;

    return SizedBox(
      height: 148,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        itemCount: EnhanceFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final filter = EnhanceFilter.values[i];
          final isSelected = selected == filter;
          final thumb = page.thumbs[filter];

          return GestureDetector(
            onTap: _saving ? null : () => _choosePreset(filter),
            child: SizedBox(
              width: 96,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? colors.buttonColor : colors.borderColor,
                          width: isSelected ? 2.5 : 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          thumb != null
                              ? Image.memory(thumb, fit: BoxFit.cover, gaplessPlayback: true)
                              : ColoredBox(color: colors.cardColor),
                          if (isSelected)
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: colors.buttonColor,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.check_rounded, size: 12, color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    filter.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected
                          ? colors.buttonColor
                          : colors.headingTextColor.withValues(alpha: 0.75),
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTuning(CustomAppColors colors) {
    final s = _page.settings;
    return Container(
      color: colors.searchbarColor,
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _tuneSlider(
            colors,
            'Brightness',
            s.brightness,
            (v) => _setAdjustment((x) => x.copyWith(brightness: v)),
            () => _render(_index),
          ),
          _tuneSlider(
            colors,
            'Contrast',
            s.contrast,
            (v) => _setAdjustment((x) => x.copyWith(contrast: v)),
            () => _render(_index),
          ),
          _tuneSlider(
            colors,
            'Saturation',
            s.saturation,
            (v) => _setAdjustment((x) => x.copyWith(saturation: v)),
            () => _render(_index),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _saving ? null : _resetAdjustments,
              icon: const Icon(Icons.restart_alt_rounded, size: 16),
              label: const Text('Reset'),
              style: TextButton.styleFrom(
                foregroundColor: colors.headingTextColor.withValues(alpha: 0.75),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tuneSlider(
    CustomAppColors colors,
    String label,
    int value,
    ValueChanged<int> onChanged,
    VoidCallback onCommit,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: TextStyle(
              color: colors.headingTextColor.withValues(alpha: 0.7),
              fontSize: 12.5,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: -100,
            max: 100,
            divisions: 200,
            activeColor: colors.buttonColor,
            inactiveColor: colors.borderColor,
            onChanged: _saving ? null : (v) => onChanged(v.round()),
            onChangeEnd: _saving ? null : (_) => onCommit(),
          ),
        ),
        SizedBox(
          width: 42,
          child: Text(
            value == 0 ? '0' : value > 0 ? '+$value' : '$value',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: value == 0
                  ? colors.headingTextColor.withValues(alpha: 0.55)
                  : colors.buttonColor,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActions(CustomAppColors colors, int total) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                _presetDescriptions[_page.settings.filter] ?? '',
                style: TextStyle(
                  color: colors.headingTextColor.withValues(alpha: 0.55),
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.headingTextColor,
                      side: BorderSide(color: colors.borderColor),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Back'),
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
                    onPressed: _saving ? null : _save,
                    child: Text(total > 1 ? 'Save $total Pages' : 'Save Document'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}