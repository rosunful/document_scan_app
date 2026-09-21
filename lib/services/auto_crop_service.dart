import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'image_orientation.dart';

class _PerspectiveRequest {
  final String sourcePath;
  final String targetPath;
  final List<List<double>> quad;

  const _PerspectiveRequest(this.sourcePath, this.targetPath, this.quad);
}

class AutoCropService {
  AutoCropService._();

  /// Warps the image so the given quad (top-left, top-right, bottom-right,
  /// bottom-left in upright image coordinates) becomes an axis-aligned
  /// rectangle. Returns the written file path, or null on failure.
  static Future<String?> applyPerspective({
    required String sourcePath,
    required String targetPath,
    required List<List<double>> quad,
  }) =>
      compute(_applyPerspectiveEntry, _PerspectiveRequest(sourcePath, targetPath, quad));
}

String? _applyPerspectiveEntry(_PerspectiveRequest request) {
  cv.Mat? source;
  cv.Mat? warped;
  try {
    source = _readImage(request.sourcePath);
    if (source.isEmpty) return null;

    final quad = cv.VecPoint2f.fromList([
      for (final p in request.quad) cv.Point2f(p[0], p[1]),
    ]);
    warped = _warpPerspective(source, quad);
    final ok = cv.imwrite(
      request.targetPath,
      warped,
      params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 92]),
    );
    return ok ? request.targetPath : null;
  } finally {
    source?.dispose();
    warped?.dispose();
  }
}

/// Loads the image EXIF-corrected. OpenCV ignores the EXIF orientation tag,
/// but Flutter honours it when it renders `Image.file`, so a phone-shot photo
/// (typically stored rotated by the sensor) must be rotated here to the same,
/// upright orientation before warping — otherwise the output would be sideways
/// relative to the corners the user dragged on the upright image.
cv.Mat _readImage(String path) {
  final bytes = File(path).readAsBytesSync();
  final img = cv.imdecode(bytes, cv.IMREAD_COLOR);
  if (img.isEmpty) return img;

  final turns = jpegExifQuarterTurns(bytes);
  if (turns == 0) return img;

  final cv.Mat rotated = switch (turns) {
    1 => cv.rotate(img, cv.ROTATE_90_CLOCKWISE),
    2 => cv.rotate(img, cv.ROTATE_180),
    _ => cv.rotate(img, cv.ROTATE_90_COUNTERCLOCKWISE),
  };
  img.dispose();
  return rotated;
}

cv.Mat _warpPerspective(cv.Mat source, cv.VecPoint2f quad) {
  final pts = quad.toList();
  final tl = pts[0], tr = pts[1], br = pts[2], bl = pts[3];

  double dist(cv.Point2f a, cv.Point2f b) =>
      math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

  final widthTop = dist(tl, tr);
  final widthBottom = dist(bl, br);
  final heightLeft = dist(tl, bl);
  final heightRight = dist(tr, br);

  final outW = math.max(widthTop, widthBottom).round().clamp(1, 6000);
  final outH = math.max(heightLeft, heightRight).round().clamp(1, 6000);

  final destination = cv.VecPoint2f.fromList([
    cv.Point2f(0, 0),
    cv.Point2f(outW.toDouble() - 1, 0),
    cv.Point2f(outW.toDouble() - 1, outH.toDouble() - 1),
    cv.Point2f(0, outH.toDouble() - 1),
  ]);

  final transform = cv.getPerspectiveTransform2f(quad, destination);
  try {
    return cv.warpPerspective(source, transform, (outW, outH));
  } finally {
    transform.dispose();
  }
}