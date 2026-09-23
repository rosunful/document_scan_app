import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:scan_documnet_app/services/enchance_service.dart';

/// Pins the "what you see in the preview is exactly what gets saved" contract:
/// the full-resolution file the preview settles on is byte-identical to the
/// file saved for the same settings, rendering is deterministic, and the
/// interactive preview is a downscaled render of the same pipeline.
void main() {
  late Directory? tmp;
  late String sourcePath;

  Future<void> waitFor(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('condition was not met within $timeout');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  setUpAll(() async {
    try {
      final probe = cv.Mat.zeros(4, 4, cv.MatType.CV_8UC1);
      probe.dispose();
    } catch (_) {
      markTestSkipped(
        'OpenCV native assets unavailable in this test environment',
      );
      return;
    }
    tmp = await Directory.systemTemp.createTemp('enhance_wysiwyg_test');

    // 1600x1200 so the 1200px preview tier actually downscales while the
    // 2400px save tier keeps the source resolution.
    final img = cv.Mat.zeros(1200, 1600, cv.MatType.CV_8UC3);
    void rect(int x0, int y0, int x1, int y1, int lum) {
      cv.fillPoly(
        img,
        cv.VecVecPoint.fromList([
          [
            cv.Point(x0, y0),
            cv.Point(x1, y0),
            cv.Point(x1, y1),
            cv.Point(x0, y1),
          ]
        ]),
        cv.Scalar(lum.toDouble(), lum.toDouble(), lum.toDouble()),
      );
    }

    rect(0, 0, 1600, 1200, 235); // paper
    rect(200, 300, 600, 420, 45); // "text"
    rect(800, 620, 1200, 800, 35); // more "text"
    rect(300, 900, 550, 1050, 55); // faint ink

    sourcePath = '${tmp!.path}/source.jpg';
    expect(cv.imwrite(sourcePath, img), isTrue);
    img.dispose();
  });

  tearDownAll(() {
    try {
      tmp?.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<String> writeOut(EnhanceSettings s, String name) async {
    final target = '${tmp!.path}/$name.jpg';
    final path = await EnhanceService.writeEnhanced(
      EnhanceFileRequest(
        sourcePath: sourcePath,
        targetPath: target,
        settings: s,
      ),
    );
    expect(path, isNotNull);
    return path!;
  }

  test('writeEnhanced is deterministic for identical settings', () async {
    const settings = EnhanceSettings(
      filter: EnhanceFilter.blackWhite,
      sensitivity: 0,
    );
    final a = await writeOut(settings, 'bw_a');
    final b = await writeOut(settings, 'bw_b');
    expect(await File(a).readAsBytes(), await File(b).readAsBytes());
  });

  test('B&W sensitivity changes the rendered output', () async {
    final low = await writeOut(
      const EnhanceSettings(filter: EnhanceFilter.blackWhite, sensitivity: -100),
      'bw_low',
    );
    final high = await writeOut(
      const EnhanceSettings(filter: EnhanceFilter.blackWhite, sensitivity: 100),
      'bw_high',
    );
    expect(await File(low).readAsBytes(), isNot(await File(high).readAsBytes()));
  });

  test('colorful render is deterministic', () async {
    const settings = EnhanceSettings(
      filter: EnhanceFilter.colorful,
      saturation: 25,
      contrast: 30,
    );
    final a = await writeOut(settings, 'color_a');
    final b = await writeOut(settings, 'color_b');
    expect(await File(a).readAsBytes(), await File(b).readAsBytes());
  });

  test('the preview flush returns the exact file that would be saved',
      () async {
    const settings = EnhanceSettings(
      filter: EnhanceFilter.blackWhite,
      sensitivity: 20,
    );
    final cache = EnhancePreviewCache(
      sourcePath: sourcePath,
      fullDebounce: Duration.zero,
    );
    addTearDown(cache.dispose);

    cache.update(settings);
    final cached = await cache.flush();
    expect(cached, isNotNull);

    final direct = await writeOut(settings, 'direct');
    expect(await File(cached!).readAsBytes(), await File(direct).readAsBytes());
  });

  test('preview renders downscaled; the saved render stays full size',
      () async {
    const settings = EnhanceSettings(
      filter: EnhanceFilter.blackWhite,
      sensitivity: 20,
    );
    final cache = EnhancePreviewCache(
      sourcePath: sourcePath,
      fullDebounce: Duration.zero,
    );
    addTearDown(cache.dispose);

    cache.update(settings);
    await waitFor(() => cache.fastPath != null);

    final fastDims = cv.imread(cache.fastPath!);
    expect(
      math.max(fastDims.rows, fastDims.cols),
      EnhancePreviewCache.fastMaxDimension,
    );
    fastDims.dispose();

    final saved = await cache.flush();
    expect(saved, cache.fullPath);
    final savedImg = cv.imread(saved!);
    expect(savedImg.rows, 1200);
    expect(savedImg.cols, 1600);
    savedImg.dispose();
  });
}