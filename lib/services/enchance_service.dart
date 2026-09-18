import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

enum EnhanceFilter { original, magic, grayscale, blackWhite }

extension EnhanceFilterLabel on EnhanceFilter {
  String get label => switch (this) {
        EnhanceFilter.original => 'Original',
        EnhanceFilter.magic => 'Magic Color',
        EnhanceFilter.grayscale => 'Grayscale',
        EnhanceFilter.blackWhite => 'B&W',
      };
}

class EnhanceSettings {
  final EnhanceFilter filter;
  final int quarterTurns;

  const EnhanceSettings({this.filter = EnhanceFilter.magic, this.quarterTurns = 0});

  EnhanceSettings copyWith({EnhanceFilter? filter, int? quarterTurns}) {
    return EnhanceSettings(
      filter: filter ?? this.filter,
      quarterTurns: quarterTurns ?? this.quarterTurns,
    );
  }

  bool get isUntouched => filter == EnhanceFilter.original && quarterTurns == 0;
}

class EnhanceFileRequest {
  final String sourcePath;
  final String targetPath;
  final EnhanceSettings settings;
  final int maxDimension;

  const EnhanceFileRequest({
    required this.sourcePath,
    required this.targetPath,
    required this.settings,
    this.maxDimension = 2400,
  });
}

class EnhancePreviewRequest {
  final Uint8List bytes;
  final EnhanceSettings settings;
  final int quality;

  const EnhancePreviewRequest({required this.bytes, required this.settings, this.quality = 85});
}

class EnhanceDownscaleRequest {
  final String sourcePath;
  final int width;

  const EnhanceDownscaleRequest({required this.sourcePath, required this.width});
}

class _BytesResize {
  final Uint8List bytes;
  final int width;
  const _BytesResize(this.bytes, this.width);
}

class EnhanceService {
  EnhanceService._();

  static Future<String?> writeEnhanced(EnhanceFileRequest request) =>
      compute(_enhanceFileEntry, request);

  static Future<Uint8List?> preview(EnhancePreviewRequest request) =>
      compute(_previewEntry, request);

  static Future<Uint8List?> downscale(EnhanceDownscaleRequest request) =>
      compute(_downscaleEntry, request);

  static Future<Uint8List?> downscaleBytes(Uint8List bytes, int width) =>
      compute(_downscaleBytesEntry, _BytesResize(bytes, width));
}

// ---------------------------------------------------------------------------
// Isolate entry points
// ---------------------------------------------------------------------------

String? _enhanceFileEntry(EnhanceFileRequest request) {
  cv.Mat? source;
  cv.Mat? resized;
  cv.Mat? result;
  try {
    source = cv.imread(request.sourcePath, flags: cv.IMREAD_COLOR);
    if (source.isEmpty) return null;

    resized = _capDimension(source, request.maxDimension);
    result = _process(resized, request.settings);

    final ok = cv.imwrite(
  request.targetPath,
  result,
  params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 92]),
);
    return ok ? request.targetPath : null;
  } catch (_) {
    return null;
  } finally {
    source?.dispose();
    if (resized != null && !identical(resized, source)) resized.dispose();
    result?.dispose();
  }
}

Uint8List? _previewEntry(EnhancePreviewRequest request) {
  cv.Mat? source;
  cv.Mat? result;
  try {
    source = cv.imdecode(request.bytes, cv.IMREAD_COLOR);
    if (source.isEmpty) return null;
    result = _process(source, request.settings);
    final (ok, buf) = cv.imencode(
  '.jpg',
  result,
  params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, request.quality]),
);
    return ok ? buf : null;
  } catch (_) {
    return null;
  } finally {
    source?.dispose();
    result?.dispose();
  }
}

Uint8List? _downscaleEntry(EnhanceDownscaleRequest request) {
  cv.Mat? source;
  cv.Mat? resized;
  try {
    source = cv.imread(request.sourcePath, flags: cv.IMREAD_COLOR);
    if (source.isEmpty) return null;
    resized = _capDimension(source, request.width, matchWidthExactly: true);
    final (ok, buf) = cv.imencode(
  '.jpg',
  resized,
  params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 88]),
);

    return ok ? buf : null;
  } catch (_) {
    return null;
  } finally {
    source?.dispose();
    if (resized != null && !identical(resized, source)) resized.dispose();
  }
}

Uint8List? _downscaleBytesEntry(_BytesResize request) {
  cv.Mat? source;
  cv.Mat? resized;
  try {
    source = cv.imdecode(request.bytes, cv.IMREAD_COLOR);
    if (source.isEmpty) return null;
    resized = _capDimension(source, request.width, matchWidthExactly: true);
    final (ok, buf) = cv.imencode(
  '.jpg',
  resized,
  params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 70]),
);
    return ok ? buf : null;
  } catch (_) {
    return null;
  } finally {
    source?.dispose();
    if (resized != null && !identical(resized, source)) resized.dispose();
  }
}

// ---------------------------------------------------------------------------
// Pipeline
// ---------------------------------------------------------------------------

cv.Mat _capDimension(cv.Mat source, int limit, {bool matchWidthExactly = false}) {
  final longest = math.max(source.rows, source.cols);
  if (!matchWidthExactly && longest <= limit) return source;
  if (matchWidthExactly && source.cols <= limit) return source;

  final scale = matchWidthExactly ? limit / source.cols : limit / longest;
  if (scale >= 1.0) return source;

  return cv.resize(
    source,
    (0, 0),
    fx: scale,
    fy: scale,
    interpolation: cv.INTER_AREA,
  );
}

/// Caller owns and must dispose the returned Mat (it's always a new one).
cv.Mat _process(cv.Mat input, EnhanceSettings settings) {
  cv.Mat working = input.clone();

  final turns = settings.quarterTurns % 4;
  if (turns == 1) {
    final r = cv.rotate(working, cv.ROTATE_90_CLOCKWISE);
    working.dispose();
    working = r;
  } else if (turns == 2) {
    final r = cv.rotate(working, cv.ROTATE_180);
    working.dispose();
    working = r;
  } else if (turns == 3) {
    final r = cv.rotate(working, cv.ROTATE_90_COUNTERCLOCKWISE);
    working.dispose();
    working = r;
  }

  switch (settings.filter) {
    case EnhanceFilter.original:
      return working;
    case EnhanceFilter.magic:
      final r = _magicColor(working);
      working.dispose();
      return r;
    case EnhanceFilter.grayscale:
      final r = _grayscaleEnhanced(working);
      working.dispose();
      return r;
    case EnhanceFilter.blackWhite:
      final r = _blackWhite(working);
      working.dispose();
      return r;
  }
}

/// CLAHE on the L channel (LAB colour space) flattens uneven lighting while
/// leaving colour untouched, then a mild saturation/contrast lift for
/// "paper looks white, ink looks crisp" without blowing out colour photos
/// on the page.
cv.Mat _magicColor(cv.Mat bgr) {
  cv.Mat? lab, l, a, b, clahedL, merged, result, hsv, h, s, v, sBoosted, hsvMerged;
  try {
    lab = cv.cvtColor(bgr, cv.COLOR_BGR2Lab);
    final channels = cv.split(lab);
    l = channels[0];
    a = channels[1];
    b = channels[2];

    final clahe = cv.CLAHE(2.2, (8, 8));
    clahedL = clahe.apply(l);

    merged = cv.merge(cv.VecMat.fromList([clahedL, a, b]));
    result = cv.cvtColor(merged, cv.COLOR_Lab2BGR);

    hsv = cv.cvtColor(result, cv.COLOR_BGR2HSV);
    final hsvChannels = cv.split(hsv);
    h = hsvChannels[0];
    s = hsvChannels[1];
    v = hsvChannels[2];
    sBoosted = cv.convertScaleAbs(s, alpha: 1.12, beta: 0);
    hsvMerged = cv.merge(cv.VecMat.fromList([h, sBoosted, v]));

    final finalResult = cv.cvtColor(hsvMerged, cv.COLOR_HSV2BGR);
    return cv.convertScaleAbs(finalResult, alpha: 1.05, beta: 6)..let((_) => finalResult.dispose());
  } finally {
    lab?.dispose();
    l?.dispose();
    a?.dispose();
    b?.dispose();
    clahedL?.dispose();
    merged?.dispose();
    result?.dispose();
    hsv?.dispose();
    h?.dispose();
    s?.dispose();
    v?.dispose();
    sBoosted?.dispose();
    hsvMerged?.dispose();
  }
}

/// Grayscale with the same CLAHE lighting-normalization as Magic Color, so
/// pages with embedded photos/logos don't get crushed the way B&W does.
cv.Mat _grayscaleEnhanced(cv.Mat bgr) {
  cv.Mat? gray, clahed;
  try {
    gray = cv.cvtColor(bgr, cv.COLOR_BGR2GRAY);
    final clahe = cv.CLAHE(2.2, (8, 8));
    clahed = clahe.apply(gray);
    final boosted = cv.convertScaleAbs(clahed, alpha: 1.1, beta: 4);
    return cv.cvtColor(boosted, cv.COLOR_GRAY2BGR)..let((_) => boosted.dispose());
  } finally {
    gray?.dispose();
    clahed?.dispose();
  }
}

/// Median blur to kill sensor/JPEG speckle, then real adaptive threshold —
/// the crisp black-text-on-white-paper scanner look, robust to uneven
/// lighting because the threshold is computed per neighbourhood.
cv.Mat _blackWhite(cv.Mat bgr) {
  cv.Mat? gray, denoised, thresholded;
  try {
    gray = cv.cvtColor(bgr, cv.COLOR_BGR2GRAY);
    denoised = cv.medianBlur(gray, 3);

    final blockSize = _oddBlockSize(gray.rows, gray.cols);
    thresholded = cv.adaptiveThreshold(
      denoised,
      255,
      cv.ADAPTIVE_THRESH_GAUSSIAN_C,
      cv.THRESH_BINARY,
      blockSize,
      10,
    );

    return cv.cvtColor(thresholded, cv.COLOR_GRAY2BGR);
  } finally {
    gray?.dispose();
    denoised?.dispose();
  }
}

/// adaptiveThreshold's blockSize must be odd and >= 3; scale it with image
/// size so a 4000px scan doesn't get a threshold window sized for a thumbnail.
int _oddBlockSize(int rows, int cols) {
  final base = (math.min(rows, cols) / 22).round();
  final size = base.clamp(15, 61);
  return size.isOdd ? size : size + 1;
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}