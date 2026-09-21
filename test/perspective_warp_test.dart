import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:scan_documnet_app/services/auto_crop_service.dart';

/// Runs only when OpenCV's native library can be loaded by the test host
/// (Flutter builds it via native assets on first run). Otherwise skipped.
void main() {
  late Directory tmp;

  setUpAll(() async {
    try {
      final probe = cv.Mat.zeros(4, 4, cv.MatType.CV_8UC1);
      probe.dispose();
    } catch (_) {
      markTestSkipped('OpenCV native assets unavailable in this test environment');
      return;
    }
    tmp = await Directory.systemTemp.createTemp('perspective_warp_test');
  });

  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  cv.Mat blankScene(int w, int h, int lum) {
    final img = cv.Mat.zeros(h, w, cv.MatType.CV_8UC3);
    cv.fillPoly(
      img,
      cv.VecVecPoint.fromList([
        [
          cv.Point(0, 0),
          cv.Point(w, 0),
          cv.Point(w, h),
          cv.Point(0, h),
        ]
      ]),
      cv.Scalar(lum.toDouble(), lum.toDouble(), lum.toDouble()),
    );
    return img;
  }

  void drawQuad(cv.Mat img, List<(double, double)> corners, int lum) {
    cv.fillPoly(
      img,
      cv.VecVecPoint.fromList([
        [for (final c in corners) cv.Point(c.$1.round(), c.$2.round())]
      ]),
      cv.Scalar(lum.toDouble(), lum.toDouble(), lum.toDouble()),
    );
  }

  double dist((double, double) a, (double, double) b) =>
      math.sqrt(math.pow(a.$1 - b.$1, 2) + math.pow(a.$2 - b.$2, 2));

  test('warps a skewed quad onto a flat, upright page', () async {
    const w = 600, h = 400;
    final img = blankScene(w, h, 25);
    // A page photographed at an angle — strongly skewed, no right angles.
    final page = <(double, double)>[
      (100.0, 130.0),
      (520.0, 70.0),
      (540.0, 350.0),
      (80.0, 320.0),
    ];
    drawQuad(img, page, 235);
    cv.Mat? noise;
    try {
      noise = cv.Mat.zeros(h, w, cv.MatType.CV_8UC3);
      cv.randn(noise, cv.Scalar(0, 0, 0), cv.Scalar(5, 5, 5));
      cv.add(img, noise, dst: img);
    } finally {
      noise?.dispose();
    }

    final sourcePath = '${tmp.path}/skewed.jpg';
    final outPath = '${tmp.path}/warped.jpg';
    expect(cv.imwrite(sourcePath, img), isTrue);

    final result = await AutoCropService.applyPerspective(
      sourcePath: sourcePath,
      targetPath: outPath,
      quad: [for (final p in page) [p.$1, p.$2]],
    );
    expect(result, outPath);

    final out = cv.imread(outPath);
    expect(out.isEmpty, isFalse);
    try {
      // Output size matches the quad's bounding box (square-ish corners ->
      // axis-aligned rectangle).
      final expectedW = math.max(dist(page[0], page[1]), dist(page[3], page[2]));
      final expectedH = math.max(dist(page[0], page[3]), dist(page[1], page[2]));
      expect(out.cols - expectedW, inInclusiveRange(-2, 2));
      expect(out.rows - expectedH, inInclusiveRange(-2, 2));

      // The whole output comes from inside the page quad, so it is uniformly
      // bright — no background leakage.
      final m = cv.mean(out).val1;
      expect(m, greaterThan(200));
    } finally {
      out.dispose();
    }
  });
}