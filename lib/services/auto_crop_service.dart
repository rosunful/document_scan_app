import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

class AutoCropRequest {
  final String sourcePath;
  final String targetPath;

  const AutoCropRequest({required this.sourcePath, required this.targetPath});
}

class AutoCropService {
  AutoCropService._();

  /// Runs off the UI thread. Returns the cropped+perspective-corrected file
  /// path, or null if no confident document boundary was found (caller
  /// should keep the original in that case).
  static Future<String?> crop(AutoCropRequest request) => compute(_autoCropEntry, request);
}

String? _autoCropEntry(AutoCropRequest request) {
  cv.Mat? source;
  cv.Mat? warped;
  try {
    source = cv.imread(request.sourcePath, flags: cv.IMREAD_COLOR);
    if (source.isEmpty) return null;

    final quad = _findDocumentQuad(source);
    if (quad == null) return null;

    warped = _warpPerspective(source, quad);
    final ok = cv.imwrite(
  request.targetPath,
  warped,
  params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 92]),
);
    return ok ? request.targetPath : null;
  } catch (_) {
    return null;
  } finally {
    source?.dispose();
    warped?.dispose();
  }
}

/// Finds the largest quadrilateral contour in the image, scaled back to
/// full-resolution coordinates. Returns null if nothing convincing enough.
cv.VecPoint2f? _findDocumentQuad(cv.Mat source) {
  const analysisWidth = 700.0;
  final scale = source.cols > analysisWidth ? analysisWidth / source.cols : 1.0;

  cv.Mat? small, gray, blurred, edges, dilated;
  try {
    small = scale < 1.0
        ? cv.resize(source, (0, 0), fx: scale, fy: scale, interpolation: cv.INTER_AREA)
        : source.clone();

    gray = cv.cvtColor(small, cv.COLOR_BGR2GRAY);
    blurred = cv.gaussianBlur(gray, (5, 5), 0);
    edges = cv.canny(blurred, 60, 160);
    dilated = cv.dilate(edges, cv.getStructuringElement(cv.MORPH_RECT, (3, 3)));

    final contours = cv.findContours(dilated, cv.RETR_LIST, cv.CHAIN_APPROX_SIMPLE);
    final imageArea = small.rows * small.cols;

    cv.VecPoint? bestQuad;
    double bestArea = 0;

    for (final contour in contours.$1) {
      final area = cv.contourArea(contour);
      // A real page fills a meaningful chunk of the frame; ignore specks
      // and ignore something suspiciously close to the whole frame (that's
      // usually the frame border itself, not the document).
      if (area < imageArea * 0.2 || area > imageArea * 0.98) continue;

      final perimeter = cv.arcLength(contour, true);
      final approx = cv.approxPolyDP(contour, 0.02 * perimeter, true);
      if (approx.length == 4 && area > bestArea && cv.isContourConvex(approx)) {
        bestQuad = approx;
        bestArea = area;
      }
    }

    if (bestQuad == null) return null;

    final points = bestQuad.toList();
    final ordered = _orderCorners(points.map((p) => (p.x / scale, p.y / scale)).toList());
    return cv.VecPoint2f.fromList(ordered.map((p) => cv.Point2f(p.$1, p.$2)).toList());
  } finally {
    small?.dispose();
    gray?.dispose();
    blurred?.dispose();
    edges?.dispose();
    dilated?.dispose();
  }
}

/// Orders four points as top-left, top-right, bottom-right, bottom-left —
/// required before warpPerspective, since contour point order is arbitrary.
List<(double, double)> _orderCorners(List<(double, double)> points) {
  final sums = points.map((p) => p.$1 + p.$2).toList();
  final diffs = points.map((p) => p.$2 - p.$1).toList();

  final topLeft = points[sums.indexOf(sums.reduce(math.min))];
  final bottomRight = points[sums.indexOf(sums.reduce(math.max))];
  final topRight = points[diffs.indexOf(diffs.reduce(math.min))];
  final bottomLeft = points[diffs.indexOf(diffs.reduce(math.max))];

  return [topLeft, topRight, bottomRight, bottomLeft];
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