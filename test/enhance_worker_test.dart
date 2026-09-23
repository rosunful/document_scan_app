import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:scan_documnet_app/services/enchance_service.dart';
import 'package:scan_documnet_app/services/enhance_worker.dart';

void main() {
  group('EnhanceWorkerSet (real pipeline, real isolates)', () {
    late Directory tempDir;
    late String sourcePath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'scan_documnet_app_worker_test',
      );
      // A 1600x1200 source so both the fast (400px) and full (2400px) tiers
      // actually downscale/keep it distinct from the input.
      final source = cv.Mat.zeros(1200, 1600, cv.MatType.CV_8UC3);
      source.setTo(cv.Scalar(90, 120, 180));
      sourcePath = '${tempDir.path}/source.jpg';
      expect(cv.imwrite(sourcePath, source), isTrue);
      source.dispose();
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {
        // Failures during worker shutdown are not under test here.
      }
    });

    test('renders fast, full, and prep files through persistent workers',
        () async {
      final workers = EnhanceWorkerSet();
      addTearDown(workers.dispose);

      await workers.ensureWarm();

      const settings = EnhanceSettings(filter: EnhanceFilter.colorful);

      final fastPath = await workers.enhance(
        EnhanceFileRequest(
          sourcePath: sourcePath,
          targetPath: '${tempDir.path}/fast.jpg',
          settings: settings,
          maxDimension: EnhancePreviewCache.fastMaxDimension,
          jpegQuality: EnhancePreviewCache.fastJpegQuality,
        ),
      );
      expect(fastPath, isNotNull);
      expect(File(fastPath!).existsSync(), isTrue);
      final fastImg = cv.imread(fastPath);
      expect(
        math.max(fastImg.rows, fastImg.cols),
        EnhancePreviewCache.fastMaxDimension,
      );
      fastImg.dispose();

      final fullPath = await workers.enhance(
        EnhanceFileRequest(
          sourcePath: sourcePath,
          targetPath: '${tempDir.path}/full.jpg',
          settings: settings,
          maxDimension: EnhancePreviewCache.fullMaxDimension,
        ),
      );
      expect(fullPath, isNotNull);
      final fullImg = cv.imread(fullPath!);
      expect(fullImg.rows, 1200); // unchanged — source is below the cap
      expect(fullImg.cols, 1600);
      fullImg.dispose();

      final smallPath = await workers.prep(
        sourcePath,
        '${tempDir.path}/src.jpg',
      );
      expect(smallPath, isNotNull);
      final smallImg = cv.imread(smallPath!);
      expect(
        math.max(smallImg.rows, smallImg.cols),
        EnhancePreviewCache.fastSourceMaxDimension,
      );
      smallImg.dispose();
    });

    test('a worker is reused for later renders (no per-render spawn)',
        () async {
      final workers = EnhanceWorkerSet();
      addTearDown(workers.dispose);

      await workers.ensureWarm();
      final before = ProcessInfo.currentRss;

      const settings = EnhanceSettings(
        filter: EnhanceFilter.blackWhite,
        sensitivity: 30,
      );
      for (var i = 0; i < 3; i++) {
        final path = await workers.enhance(
          EnhanceFileRequest(
            sourcePath: sourcePath,
            targetPath: '${tempDir.path}/again_$i.jpg',
            settings: settings,
            maxDimension: EnhancePreviewCache.fastMaxDimension,
            jpegQuality: EnhancePreviewCache.fastJpegQuality,
          ),
        );
        expect(path, isNotNull);
        expect(File(path!).existsSync(), isTrue);
      }

      // Rendering again on ready workers must not balloon memory with new
      // per-call isolates / duplicate native libraries.
      final after = ProcessInfo.currentRss;
      expect(after - before, lessThan(60 * 1024 * 1024));
    });

    test('ensureWarm is idempotent', () async {
      final workers = EnhanceWorkerSet();
      addTearDown(workers.dispose);

      await workers.ensureWarm();
      await workers.ensureWarm(); // must not spawn a second pair
      final path = await workers.enhance(
        EnhanceFileRequest(
          sourcePath: sourcePath,
          targetPath: '${tempDir.path}/idempotent.jpg',
          settings: const EnhanceSettings(
            filter: EnhanceFilter.blackWhite,
            sensitivity: 0,
          ),
          maxDimension: EnhancePreviewCache.fastMaxDimension,
          jpegQuality: EnhancePreviewCache.fastJpegQuality,
        ),
      );
      expect(path, isNotNull);
    });
  });
}