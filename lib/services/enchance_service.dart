import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

enum EnhanceFilter { original, colorful, blackWhite }

extension EnhanceFilterLabel on EnhanceFilter {
  String get label => switch (this) {
    EnhanceFilter.original => 'Original',
    EnhanceFilter.colorful => 'Colorful',
    EnhanceFilter.blackWhite => 'B&W',
  };
}

class EnhanceSettings {
  final EnhanceFilter filter;
  final int quarterTurns;
  final int brightness; // -100..100, 0 = unchanged
  final int contrast; // -100..100, 0 = unchanged
  final int saturation; // -100..100, 0 = unchanged
  final int sensitivity; // -100..100, B&W ink sensitivity, 0 = default

  const EnhanceSettings({
    this.filter = EnhanceFilter.colorful,
    this.quarterTurns = 0,
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.sensitivity = 0,
  });

  EnhanceSettings copyWith({
    EnhanceFilter? filter,
    int? quarterTurns,
    int? brightness,
    int? contrast,
    int? saturation,
    int? sensitivity,
  }) {
    return EnhanceSettings(
      filter: filter ?? this.filter,
      quarterTurns: quarterTurns ?? this.quarterTurns,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      sensitivity: sensitivity ?? this.sensitivity,
    );
  }

  bool get isUntouched =>
      filter == EnhanceFilter.original &&
      quarterTurns == 0 &&
      brightness == 0 &&
      contrast == 0 &&
      saturation == 0 &&
      sensitivity == 0;

  @override
  bool operator ==(Object other) =>
      other is EnhanceSettings &&
      other.filter == filter &&
      other.quarterTurns == quarterTurns &&
      other.brightness == brightness &&
      other.contrast == contrast &&
      other.saturation == saturation &&
      other.sensitivity == sensitivity;

  @override
  int get hashCode =>
      Object.hash(filter, quarterTurns, brightness, contrast, saturation, sensitivity);
}

class EnhanceFileRequest {
  final String sourcePath;
  final String targetPath;
  final EnhanceSettings settings;
  final int maxDimension;

  /// JPEG encode quality. The interactive preview tier uses a low value
  /// (~65) to swap frames fast; the save tier always uses 92.
  final int jpegQuality;

  const EnhanceFileRequest({
    required this.sourcePath,
    required this.targetPath,
    required this.settings,
    this.maxDimension = 2400,
    this.jpegQuality = 92,
  });
}

/// Asks [EnhanceService.writeFastSource] to decode the (large) source once and
/// cache a small working copy for the interactive fast tier.
class EnhanceFastSourceRequest {
  final String sourcePath;
  final String targetPath;
  final int maxDimension;

  const EnhanceFastSourceRequest({
    required this.sourcePath,
    required this.targetPath,
    this.maxDimension = 512,
  });
}

class EnhanceService {
  EnhanceService._();

  static Future<String?> writeEnhanced(EnhanceFileRequest request) =>
      compute(enhanceFileEntry, request);

  /// Decodes [r.sourcePath] at full quality once, downscales it, and writes a
  /// small JPEG that the fast preview tier can read cheaply on every change.
  static Future<String?> writeFastSource(EnhanceFastSourceRequest request) =>
      compute(fastSourceEntry, request);
}

// ---------------------------------------------------------------------------
// Isolate entry points
// ---------------------------------------------------------------------------

/// Runs a single [EnhanceFileRequest] in the CURRENT isolate and returns the
/// written file path (or null). Used by [EnhanceService.writeEnhanced] inside
/// `compute(...)` isolates and by the persistent worker isolates, so the OpenCV
/// native library is only loaded once per worker instead of per render.
String? enhanceFileEntry(EnhanceFileRequest request) {
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
      params:
          cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, request.jpegQuality]),
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

/// Decodes the large source once, downscales to [request.maxDimension], and
/// writes a small JPEG for the fast preview tier to read.
String? fastSourceEntry(EnhanceFastSourceRequest request) {
  cv.Mat? source;
  cv.Mat? resized;
  try {
    source = cv.imread(request.sourcePath, flags: cv.IMREAD_COLOR);
    if (source.isEmpty) return null;
    resized = _capDimension(source, request.maxDimension);
    final ok = cv.imwrite(
      request.targetPath,
      resized,
      params: cv.VecI32.fromList([
        cv.IMWRITE_JPEG_QUALITY,
        EnhancePreviewCache.fastJpegQuality,
      ]),
    );
    return ok ? request.targetPath : null;
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

cv.Mat _capDimension(
  cv.Mat source,
  int limit, {
  bool matchWidthExactly = false,
}) {
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
    case EnhanceFilter.colorful:
      result = _magicColor(working);
      working.dispose();
      break;
    case EnhanceFilter.blackWhite:
      result = _blackWhite(working, settings);
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
  cv.Mat? lab,
      l,
      a,
      b,
      clahedL,
      merged,
      result,
      hsv,
      h,
      s,
      v,
      sBoosted,
      hsvMerged;
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
    return cv.convertScaleAbs(finalResult, alpha: 1.05, beta: 6)
      ..let((_) => finalResult.dispose());
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

/// Applies the user's Brightness / Contrast / Saturation tuning on top of
/// the chosen filter. Returns [bgr] unchanged when nothing needs adjusting.
cv.Mat _applyAdjustments(cv.Mat bgr, EnhanceSettings settings) {
  if (settings.brightness == 0 &&
      settings.contrast == 0 &&
      settings.saturation == 0) {
    return bgr;
  }

  final contrast = settings.contrast;
  final alphaC = contrast >= 0
      ? (255 + contrast) / 255
      : 255 / (255 - contrast);
  final beta = settings.brightness * 128 / 100;

  var out = cv.convertScaleAbs(bgr, alpha: alphaC, beta: beta);

  final wantsSaturation =
      settings.saturation != 0 && settings.filter != EnhanceFilter.blackWhite;
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

/// Median blur to kill sensor/JPEG speckle, then real adaptive threshold —
/// the crisp black-text-on-white-paper scanner look, robust to uneven
/// lighting because the threshold is computed per neighbourhood. The user's
/// Sensitivity setting shifts the threshold offset so more/less content is
/// kept as ink.
cv.Mat _blackWhite(cv.Mat bgr, EnhanceSettings settings) {
  cv.Mat? gray, denoised, thresholded;
  try {
    gray = cv.cvtColor(bgr, cv.COLOR_BGR2GRAY);
    denoised = cv.medianBlur(gray, 3);

    final blockSize = _oddBlockSize(gray.rows, gray.cols);
    final c = 10 + (settings.sensitivity / 100) * 12;
    thresholded = cv.adaptiveThreshold(
      denoised,
      255,
      cv.ADAPTIVE_THRESH_GAUSSIAN_C,
      cv.THRESH_BINARY,
      blockSize,
      c.clamp(-5.0, 22.0),
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

/// Debounced per-page coordinator that renders [EnhanceSettings] with the same
/// pipeline the saved file uses. Two tiers, running the identical algorithm at
/// different sizes:
///
///  * a *fast* tier ([fastMaxDimension], low [EnhanceFileRequest.jpegQuality])
///    — starts immediately on every change so slider feedback feels live;
///  * a *full* tier ([fullMaxDimension]) on a longer [fullDebounce] — rendered
///    quietly once the user pauses, then substituted in via [displayPath] and
///    reused directly by [_save] through [flush] (saved == shown, byte-for-byte).
///
/// What you see is always the real OpenCV output — never a GPU approximation.
class EnhancePreviewCache {
  EnhancePreviewCache({
    required this.sourcePath,
    this.fullDebounce = const Duration(milliseconds: 450),
    Future<String?> Function(EnhanceFileRequest request)? writer,
    Future<String?> Function(String sourcePath, String targetPath)?
        fastSourceWriter,
  })  : _writer = writer ?? EnhanceService.writeEnhanced,
        _fastSourceWriter =
            fastSourceWriter ??
            ((source, target) => EnhanceService.writeFastSource(
                  EnhanceFastSourceRequest(
                    sourcePath: source,
                    targetPath: target,
                    maxDimension: fastSourceMaxDimension,
                  ),
                ));

  /// Longest-edge for the interactive fast render — as small as we can go
  /// while the effect stays readable, because this tier drives perceived
  /// speed. Dropping from 700 to 400px is ~4x fewer pixels per frame.
  static const int fastMaxDimension = 400;

  /// JPEG quality for the fast tier (preview only). The saved full tier
  /// always encodes at 92, so preview degradation never affects the document.
  static const int fastJpegQuality = 65;

  /// Max longest-edge for the saved document render (matches the service cap).
  static const int fullMaxDimension = 2400;

  /// Max longest-edge of the one-time small working copy the fast tier reads.
  static const int fastSourceMaxDimension = 512;

  /// Untouched image this cache enhances from.
  final String sourcePath;

  /// How long after the last change before the full save render starts.
  final Duration fullDebounce;

  final Future<String?> Function(EnhanceFileRequest request) _writer;
  final Future<String?> Function(String sourcePath, String targetPath)
      _fastSourceWriter;

  EnhanceSettings? _settings;
  EnhanceSettings? _settledFast;
  EnhanceSettings? _settledFull;
  Future<void>? _fastRunning;
  Future<void>? _fullRunning;
  Timer? _fullTimer;
  bool _disposed = false;

  /// One-time downscaled copy of [sourcePath] that the fast tier reads instead
  /// of decoding the multi-megapixel original on every slider change.
  String? _sourceSmallPath;
  Future<void>? _sourcePrep;
  bool _sourcePrepFailed = false;

  /// Small, fast render — shown immediately, real algorithm.
  String? fastPath;

  /// Full-quality render — swapped in when ready, reused directly at Save.
  String? fullPath;

  /// True while any render is running. The fast tier starts immediately on
  /// every change, so a busy `isComputing` mostly means "the fast frame is on
  /// screen and full-res is still catching up in the background".
  bool get isComputing =>
      _fullTimer != null || _fastRunning != null || _fullRunning != null;

  /// Best available path to display right now.
  String? get displayPath => fullPath ?? fastPath;

  /// True when [fastPath] reflects the latest requested settings. Never-
  /// scheduled settings (`_settings == null`) are NOT settled — a default
  /// (e.g. Colorful) page must render before it can be saved as shown.
  bool get isSettled => _settings != null && _settledFast == _settings;

  /// True when [fullPath] reflects the latest requested settings.
  bool get isFullSettled => _settings != null && _settledFull == _settings;

  /// Registers a new target. Rapidly repeated calls (e.g. slider drags) start
  /// the fast render immediately; [EnhancePreviewCache._computeFast] coalesces
  /// while each frame runs and re-renders the latest settings when it finishes
  /// (converge-to-latest), so the effect tracks the slider live instead of
  /// waiting for a debounce pause.
  void update(EnhanceSettings settings) {
    if (_disposed) return;
    _settings = settings;
    _fullTimer?.cancel();
    if (settings.isUntouched) {
      _fullTimer = null;
      _clearAll();
      _settledFast = settings;
      _settledFull = settings;
      return;
    }
    _ensureFastSource();
    _computeFast();
    _fullTimer = Timer(fullDebounce, () {
      _fullTimer = null;
      _computeFull();
    });
  }

  /// Ensures the full-resolution render for the current settings exists and
  /// returns the exact file that should be saved. Typically returns instantly
  /// because the full tier was already rendering in the background.
  Future<String?> flush() async {
    if (_disposed) return null;
    _fullTimer?.cancel();
    _fullTimer = null;
    final settings = _settings;
    if (settings == null || settings.isUntouched) {
      _clearAll();
      _settledFast = settings;
      _settledFull = settings;
      return null;
    }
    if (_settledFull != settings) await _computeFull();
    return fullPath;
  }

  /// Cancels pending work and deletes the cached files. Safe to call after
  /// [flush] (the saved file was already moved to permanent storage).
  void dispose() {
    _disposed = true;
    _fullTimer?.cancel();
    _fullTimer = null;
    _clearAll();
    if (_sourceSmallPath != null) _deleteFile(_sourceSmallPath!);
    _sourceSmallPath = null;
  }

  Future<void> _computeFast() {
    if (_fastRunning != null) return _fastRunning!;
    final settings = _settings;
    if (settings == null || settings.isUntouched || _settledFast == settings) {
      return Future.value();
    }
    var stale = false;
    final chain = Future<void>.value().then((_) async {
      if (_disposed) return;
      final latest = _settings;
      if (latest == null || latest.isUntouched || _settledFast == latest) return;
      final target = _derivedEnhancePath(sourcePath, 'fast');
      final path = await _writer(
        EnhanceFileRequest(
          sourcePath: _sourceSmallPath ?? sourcePath,
          targetPath: target,
          settings: latest,
          maxDimension: fastMaxDimension,
          jpegQuality: fastJpegQuality,
        ),
      );
      if (path == null || _disposed) {
        _deleteFile(path);
        return;
      }
      // Settings moved on while rendering: discard, and let whenComplete
      // re-render the latest so a change is never silently swallowed.
      if (_settings != latest) {
        stale = true;
        _deleteFile(path);
        return;
      }
      if (fastPath != null && fastPath != path) _deleteFile(fastPath!);
      fastPath = path;
      _settledFast = latest;
    });
    _fastRunning = chain;
    return chain.whenComplete(() {
      if (identical(_fastRunning, chain)) _fastRunning = null;
      if (stale && !_disposed && !_isFastSettled()) _computeFast();
    });
  }

  Future<void> _computeFull() {
    if (_fullRunning != null) return _fullRunning!;
    final settings = _settings;
    if (settings == null || settings.isUntouched || _settledFull == settings) {
      return Future.value();
    }
    var stale = false;
    final chain = Future<void>.value().then((_) async {
      if (_disposed) return;
      final latest = _settings;
      if (latest == null || latest.isUntouched || _settledFull == latest) return;
      // Only one full-res render runs app-wide at a time so applied-to-all and
      // multi-page documents don't saturate the CPU and starve the fast tier.
      await _enqueueGlobal(() async {
        if (_disposed || _settings != latest || _settledFull == latest) return;
        final target = _derivedEnhancePath(sourcePath, 'full');
        final path = await _writer(
          EnhanceFileRequest(
            sourcePath: sourcePath,
            targetPath: target,
            settings: latest,
            maxDimension: fullMaxDimension,
          ),
        );
        if (path == null || _disposed) {
          _deleteFile(path);
          return;
        }
        if (_settings != latest) {
          stale = true;
          _deleteFile(path);
          return;
        }
        if (fullPath != null && fullPath != path) _deleteFile(fullPath!);
        fullPath = path;
        _settledFull = latest;
      });
    });
    _fullRunning = chain;
    return chain.whenComplete(() {
      if (identical(_fullRunning, chain)) _fullRunning = null;
      if (stale && !_disposed && !_isFullSettled()) _computeFull();
    });
  }

  bool _isFastSettled() {
    final s = _settings;
    return s == null || s.isUntouched || _settledFast == s;
  }

  bool _isFullSettled() {
    final s = _settings;
    return s == null || s.isUntouched || _settledFull == s;
  }

  /// Prepares (once) a small working copy of [sourcePath] so every fast render
  /// reads a small file instead of re-decoding the full photo. Best-effort: on
  /// failure the fast tier silently falls back to the big source. The first
  /// fast render in a session may happen before prep completes; subsequent
  /// ones automatically pick up the small copy via [_sourceSmallPath].
  void _ensureFastSource() {
    if (_disposed ||
        _sourceSmallPath != null ||
        _sourcePrep != null ||
        _sourcePrepFailed) {
      return;
    }
    final target = _derivedEnhancePath(sourcePath, 'src');
    _sourcePrep = Future<void>.value().then((_) async {
      final ok = await _fastSourceWriter(sourcePath, target);
      if (ok == null) {
        _sourcePrepFailed = true;
        return;
      }
      if (_disposed) {
        _deleteFile(ok);
        return;
      }
      _sourceSmallPath = ok;
    }).whenComplete(() {
      _sourcePrep = null;
    });
  }

  void _clearAll() {
    if (fastPath != null) _deleteFile(fastPath!);
    if (fullPath != null) _deleteFile(fullPath!);
    fastPath = null;
    fullPath = null;
  }

  /// Serializes full-res renders across every cache instance so the app never
  /// runs more than one heavy 2400px compute at a time.
  static Future<void>? _globalTail;

  static Future<void> _enqueueGlobal(Future<void> Function() job) {
    final prev = _globalTail ?? Future<void>.value();
    final next = prev.then((_) async {
      try {
        await job();
      } catch (_) {
        // A failed render is treated like a null write; errors must never
        // break the shared queue.
      }
    });
    _globalTail = next;
    return next;
  }

  /// A fresh temp path next to [source] so it lives in the same writable dir.
  static String _derivedEnhancePath(String source, String tag) {
    final file = File(source);
    final name = file.uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    final base = dot == -1 ? name : name.substring(0, dot);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return '${file.parent.path}${Platform.pathSeparator}${base}_${tag}_'
        '$stamp.jpg';
  }

  static void _deleteFile(String? path) {
    if (path == null) return;
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // Best-effort cleanup.
    }
  }
}
