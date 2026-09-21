import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

enum EnhanceFilter { original, magic, clean, grayscale, blackWhite }

extension EnhanceFilterLabel on EnhanceFilter {
  String get label => switch (this) {
        EnhanceFilter.original => 'Original',
        EnhanceFilter.magic => 'Magic Color',
        EnhanceFilter.clean => 'Clean',
        EnhanceFilter.grayscale => 'Grayscale',
        EnhanceFilter.blackWhite => 'B&W',
      };
}

class EnhanceSettings {
  final EnhanceFilter filter;
  final int quarterTurns;
  final int brightness; // -100..100, 0 = unchanged
  final int contrast;   // -100..100, 0 = unchanged
  final int saturation; // -100..100, 0 = unchanged

  const EnhanceSettings({
    this.filter = EnhanceFilter.magic,
    this.quarterTurns = 0,
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
  });

  EnhanceSettings copyWith({
    EnhanceFilter? filter,
    int? quarterTurns,
    int? brightness,
    int? contrast,
    int? saturation,
  }) {
    return EnhanceSettings(
      filter: filter ?? this.filter,
      quarterTurns: quarterTurns ?? this.quarterTurns,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
    );
  }

  bool get isUntouched =>
      filter == EnhanceFilter.original &&
      quarterTurns == 0 &&
      brightness == 0 &&
      contrast == 0 &&
      saturation == 0;
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

  cv.Mat result;
  switch (settings.filter) {
    case EnhanceFilter.original:
      result = working;
      break;
    case EnhanceFilter.magic:
      result = _magicColor(working);
      working.dispose();
      break;
    case EnhanceFilter.clean:
      result = _cleanPaper(working);
      working.dispose();
      break;
    case EnhanceFilter.grayscale:
      result = _grayscaleEnhanced(working);
      working.dispose();
      break;
    case EnhanceFilter.blackWhite:
      result = _blackWhite(working);
      working.dispose();
      break;
  }

  final adjusted = _applyAdjustments(result, settings);
  if (!identical(adjusted, result)) result.dispose();
  return adjusted;
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

/// "Clean" — the flat, shadow-free scanner look. Paper background is
/// whitened by dividing out a heavily blurred per-channel background
/// estimate (kills shadows and uneven lighting), luminance is flattened with
/// CLAHE, then a mild saturation lift and an unsharp mask make text pop.
cv.Mat _cleanPaper(cv.Mat bgr) {
  final channels = cv.split(bgr);
  final normalized = <cv.Mat>[];
  for (final ch in channels) {
    final bg = cv.gaussianBlur(ch, (0, 0), 30.0);
    final n = cv.divide(ch, bg, scale: 255);
    normalized.add(n);
    bg.dispose();
    ch.dispose();
  }
  final flat = cv.merge(cv.VecMat.fromList(normalized));
  for (final n in normalized) {
    n.dispose();
  }

  final lab = cv.cvtColor(flat, cv.COLOR_BGR2Lab);
  flat.dispose();
  final lChannels = cv.split(lab);
  final l = lChannels[0], a = lChannels[1], b = lChannels[2];
  final clahe = cv.CLAHE(1.8, (8, 8));
  final clahedL = clahe.apply(l);
  l.dispose();
  final mergedLab = cv.merge(cv.VecMat.fromList([clahedL, a, b]));
  clahedL.dispose();
  a.dispose();
  b.dispose();
  lab.dispose();
  final colorFlat = cv.cvtColor(mergedLab, cv.COLOR_Lab2BGR);
  mergedLab.dispose();

  final hsv = cv.cvtColor(colorFlat, cv.COLOR_BGR2HSV);
  colorFlat.dispose();
  final hChannels = cv.split(hsv);
  final h = hChannels[0], s = hChannels[1], v = hChannels[2];
  final sBoosted = cv.convertScaleAbs(s, alpha: 1.08);
  s.dispose();
  final mergedHsv = cv.merge(cv.VecMat.fromList([h, sBoosted, v]));
  h.dispose();
  sBoosted.dispose();
  v.dispose();
  hsv.dispose();
  final finalColor = cv.cvtColor(mergedHsv, cv.COLOR_HSV2BGR);
  mergedHsv.dispose();

  final blurred = cv.gaussianBlur(finalColor, (0, 0), 1.2);
  final sharp = cv.addWeighted(finalColor, 1.45, blurred, -0.45, 0);
  blurred.dispose();
  finalColor.dispose();
  return sharp;
}

/// Applies the user's Brightness / Contrast / Saturation tuning on top of
/// the chosen filter. Returns [bgr] unchanged when nothing needs adjusting.
cv.Mat _applyAdjustments(cv.Mat bgr, EnhanceSettings settings) {
  if (settings.brightness == 0 && settings.contrast == 0 && settings.saturation == 0) {
    return bgr;
  }

  final contrast = settings.contrast;
  final alphaC = contrast >= 0
      ? (255 + contrast) / 255
      : 255 / (255 - contrast);
  final beta = settings.brightness * 128 / 100;

  var out = cv.convertScaleAbs(bgr, alpha: alphaC, beta: beta);

  final wantsSaturation = settings.saturation != 0 &&
      settings.filter != EnhanceFilter.grayscale &&
      settings.filter != EnhanceFilter.blackWhite;
  if (wantsSaturation) {
    final hsv = cv.cvtColor(out, cv.COLOR_BGR2HSV);
    final ch = cv.split(hsv);
    final h = ch[0], sM = ch[1], v = ch[2];
    final sB = cv.convertScaleAbs(sM, alpha: 1 + settings.saturation / 100);
    final merged = cv.merge(cv.VecMat.fromList([h, sB, v]));
    final back = cv.cvtColor(merged, cv.COLOR_HSV2BGR);
    out.dispose();
    hsv.dispose();
    h.dispose();
    sM.dispose();
    v.dispose();
    sB.dispose();
    merged.dispose();
    out = back;
  }
  return out;
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