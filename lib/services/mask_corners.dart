import 'package:document_scan/document_scan.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

const _minAreaFraction = 0.03;

/// Extracts the four corners of a document from a binary segmentation mask
/// (0 = background, non-zero = document).
///
/// [mask] must be a single-channel (CV_8UC1) image at the resolution whose
/// corners you want. The caller is expected to scale the model output up to the
/// source image before passing it here so the returned coordinates are
/// pixel-aligned with the original.
DocumentCorners? cornersFromMask(cv.Mat mask) {
  final height = mask.rows;
  final width = mask.cols;
  if (height <= 0 || width <= 0) return null;

  final (contours, hierarchy) = cv.findContours(
    mask,
    cv.RETR_EXTERNAL,
    cv.CHAIN_APPROX_SIMPLE,
  );
  try {
    if (contours.isEmpty) return null;

    // Largest contour first — a document is the biggest blob in the mask.
    final ranked = contours.toList()
      ..sort((a, b) => cv.contourArea(b).compareTo(cv.contourArea(a)));

    final frameArea = height * width;
    for (final contour in ranked.take(3)) {
      final area = cv.contourArea(contour);
      if (area < frameArea * _minAreaFraction) continue;

      final points = _quadPoints(contour);
      if (points == null) continue;

      final normalized = <ScanPoint>[
        for (final (x, y) in points) (x: x / width, y: y / height),
      ];
      return DocumentCorners.fromUnordered(normalized);
    }
    return null;
  } finally {
    hierarchy.dispose();
    contours.dispose();
  }
}

/// Reduces [contour] to exactly four points, or null if the contour is too
/// small/odd to yield a document quad.
List<(double, double)>? _quadPoints(cv.VecPoint contour) {
  final perimeter = cv.arcLength(contour, true);
  if (perimeter <= 0) return null;

  final approx = cv.approxPolyDP(contour, 0.03 * perimeter, true);
  List<(double, double)>? quad;
  try {
    if (approx.length == 4) {
      quad = [for (final p in approx) (p.x.toDouble(), p.y.toDouble())];
    }
  } finally {
    approx.dispose();
  }
  if (quad != null) return quad;

  // A noisy mask edge rarely reduces to four vertices; the minimum-area
  // rotated rectangle is a good stand-in for a scanned page.
  final rect = cv.minAreaRect(contour);
  final box = cv.boxPoints(rect);
  try {
    return [for (final p in box) (p.x, p.y)];
  } finally {
    box.dispose();
    rect.dispose();
  }
}
