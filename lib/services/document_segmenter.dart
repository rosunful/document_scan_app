import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:document_scan/document_scan.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'mask_corners.dart';

const _mean = [0.485, 0.456, 0.406];
const _std = [0.229, 0.224, 0.225];
const _threshold = 0.5;

class DocumentSegmenter {
  DocumentSegmenter({
    this.inputSize = 512,
    this.assetPath = 'assets/models/document_seg.onnx',
  });

  final int inputSize;
  final String assetPath;

  OrtSession? _session;
  bool _loaded = false;
  bool _unavailable = false;

  bool get isReady => _loaded && !_unavailable;

  /// Loads the model from assets. Returns `false` (rather than throwing) when
  /// the asset is missing or the runtime is unavailable so the ONNX path can be
  /// treated as an optional fallback.
  Future<bool> load() async {
    if (_loaded) return true;
    if (_unavailable) return false;
    try {
      _session = await OnnxRuntime().createSessionFromAsset(assetPath);
      _loaded = true;
      return true;
    } catch (_) {
      _unavailable = true;
      return false;
    }
  }

  /// Runs the segmentation model on [imageBytes] and returns four document
  /// corners normalized 0..1, or null when no document is found or the model
  /// is not ready.
  Future<DocumentCorners?> detect(Uint8List imageBytes) async {
    final session = _session;
    if (session == null) return null;

    final prepared = await Isolate.run(
      () => _preprocess(imageBytes, inputSize),
    );
    if (prepared == null) return null;
    final (data, width, height) = prepared;

    final inputName = session.inputNames.first;
    final input = await OrtValue.fromList(data, [1, 3, inputSize, inputSize]);
    try {
      final outputs = await session.run({inputName: input});
      final outputName = session.outputNames.isNotEmpty
          ? session.outputNames.first
          : outputs.keys.first;
      final maskValue = outputs[outputName];
      if (maskValue == null) return null;
      final maskFlat = await maskValue.asFlattenedList();
      await maskValue.dispose();

      return Isolate.run(
        () => _postprocess(maskFlat, inputSize, width, height),
      );
    } finally {
      await input.dispose();
    }
  }

  Future<void> dispose() async {
    await _session?.close();
    _session = null;
    _loaded = false;
  }
}

/// Decodes the image bytes, resizes to [inputSize] and returns normalised
/// RGBNCHW [Float32List] plus the original dimensions.
(Float32List, int, int)? _preprocess(Uint8List imageBytes, int inputSize) {
  final bgr = cv.imdecode(imageBytes, cv.IMREAD_COLOR);
  if (bgr.isEmpty) return null;
  final width = bgr.cols;
  final height = bgr.rows;
  final rgb = cv.cvtColor(bgr, cv.COLOR_BGR2RGB);
  bgr.dispose();
  try {
    final resized = cv.resize(rgb, (inputSize, inputSize), interpolation: cv.INTER_AREA);
    try {
      final pixels = resized.data;
      final channelPixels = inputSize * inputSize;
      final out = Float32List(3 * channelPixels);
      for (var c = 0; c < 3; c++) {
        final mean = _mean[c];
        final std = _std[c];
        final offset = c * channelPixels;
        for (var i = 0; i < channelPixels; i++) {
          out[offset + i] = (pixels[i * 3 + c] / 255.0 - mean) / std;
        }
      }
      return (out, width, height);
    } finally {
      resized.dispose();
    }
  } finally {
    rgb.dispose();
  }
}

/// Upscales the model's probability map to the original image size before
/// thresholding, so small documents are not lost to a blocky nearest-neighbour
/// upscale of an already-binarized mask.
DocumentCorners? _postprocess(
  List<dynamic> maskFlat,
  int inputSize,
  int origWidth,
  int origHeight,
) {
  final w = inputSize * inputSize;
  final probs = Float32List(w);
  for (var i = 0; i < w; i++) {
    probs[i] = maskFlat[i] as double;
  }
  final smallProb = cv.Mat.fromList(
    inputSize,
    inputSize,
    cv.MatType.CV_32FC1,
    probs,
  );
  final fullProb = cv.resize(
    smallProb,
    (origWidth, origHeight),
    interpolation: cv.INTER_LINEAR,
  );
  smallProb.dispose();

  cv.Mat? thresholded;
  cv.Mat? fullMask;
  try {
    // fullProb holds 0..1 float probabilities, so threshold at _threshold (not
    // a 0..255-scaled cutoff) with maxval 1.0...
    final (_, probMask) = cv.threshold(fullProb, _threshold, 1.0, cv.THRESH_BINARY);
    thresholded = probMask;
    // ...then convert the 0/1 float mask to an 8-bit 0/255 one for contour
    // extraction (findContours requires CV_8UC1).
    fullMask = cv.convertScaleAbs(probMask, alpha: 255);
    return cornersFromMask(fullMask);
  } finally {
    fullProb.dispose();
    thresholded?.dispose();
    fullMask?.dispose();
  }
}
