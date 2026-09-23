import 'dart:io';
import 'dart:math' as math;

import 'package:document_scan/document_scan.dart';

import 'document_segmenter.dart';

/// Detects a document's quad in a still photo with the native detector,
/// falling back to the optional ONNX segmentation model when the native result
/// is weak or missing. Detection only — the actual crop/warp is done later on
/// the crop review.
///
/// A batch flow shares one instance so the ONNX session is lazy-loaded (and
/// left unloaded when the asset is missing) a single time.
class DocumentDetectionService {
  DocumentDetectionService();

  static const double _iosConfidenceThreshold = 0.5;
  static const double _androidConfidenceThreshold = 0.7;
  static const double _agreementThreshold = 0.08;

  final DocumentScanner _scanner = DocumentScanner();
  final DocumentSegmenter _segmenter = DocumentSegmenter();

  /// Best quad for [sourcePath], or `null` when nothing document-like was
  /// found. The native result is trusted unless it is missing or weak; only
  /// then is the ONNX model consulted, and the stronger of the two wins when
  /// they meaningfully disagree.
  Future<DocumentCorners?> detectCorners(String sourcePath) async {
    try {
      var corners = await _scanner.detectCorners(
        ScanInput.file(sourcePath),
        sensitivity: DetectionSensitivity.lenient,
      );

      final threshold = Platform.isIOS
          ? _iosConfidenceThreshold
          : _androidConfidenceThreshold;
      final weak = corners == null || (corners.confidence ?? 0) < threshold;

      if (weak) {
        if (await _segmenter.load()) {
          final bytes = await File(sourcePath).readAsBytes();
          final onnxCorners = await _segmenter.detect(bytes);

          if (onnxCorners != null) {
            if (corners == null) {
              corners = onnxCorners;
            } else {
              final distance = _cornerDistance(corners, onnxCorners);
              if (distance >= _agreementThreshold) {
                corners =
                    (onnxCorners.confidence ?? 0) > (corners.confidence ?? 0)
                    ? onnxCorners
                    : corners;
              }
            }
          }
        }
      }

      return corners;
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() async {
    await _segmenter.dispose();
  }
}

/// Mean per-corner distance between two quads in normalized units (0..1 image
/// space). Used to decide whether the ONNX corners meaningfully disagree with
/// the native ones before trusting either.
double _cornerDistance(DocumentCorners a, DocumentCorners b) {
  final pa = a.toList(), pb = b.toList();
  var sum = 0.0;
  for (var i = 0; i < 4; i++) {
    sum += math.sqrt(
      math.pow(pa[i].x - pb[i].x, 2) + math.pow(pa[i].y - pb[i].y, 2),
    );
  }
  return sum / 4;
}
