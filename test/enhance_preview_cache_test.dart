import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scan_documnet_app/services/enchance_service.dart';

class _ControllableWriter {
  final _pending = <(EnhanceFileRequest, Completer<String>)>[];
  final requests = <EnhanceFileRequest>[];

  int get pendingCount => _pending.length;

  Future<String?> call(EnhanceFileRequest request) {
    requests.add(request);
    final completer = Completer<String>();
    _pending.add((request, completer));
    return completer.future;
  }

  void resolveNext() {
    final (request, completer) = _pending.removeAt(0);
    completer.complete(request.targetPath);
  }
}

void main() {
  group('EnhancePreviewCache', () {
    const source = '/tmp/scan_documnet_app/enhance_cache/source.jpg';

    EnhancePreviewCache cacheWith(
      List<EnhanceFileRequest> calls, {
      Duration fullDebounce = Duration.zero,
    }) {
      return EnhancePreviewCache(
        sourcePath: source,
        fullDebounce: fullDebounce,
        writer: (request) async {
          calls.add(request);
          return request.targetPath;
        },
        fastSourceWriter: (_, target) async => target,
      );
    }

    List<EnhanceFileRequest> callsAt(
      List<EnhanceFileRequest> calls,
      int maxDimension,
    ) =>
        calls
            .where((r) => r.maxDimension == maxDimension)
            .toList(growable: false);

    test('rapid updates converge to exactly one fast and one full render of '
        'the latest settings', () async {
      final calls = <EnhanceFileRequest>[];
      final cache = cacheWith(calls);
      addTearDown(cache.dispose);

      cache.update(
        const EnhanceSettings(
          filter: EnhanceFilter.blackWhite,
          sensitivity: -100,
        ),
      );
      cache.update(
        const EnhanceSettings(filter: EnhanceFilter.blackWhite, sensitivity: 0),
      );
      cache.update(
        const EnhanceSettings(
          filter: EnhanceFilter.blackWhite,
          sensitivity: 100,
        ),
      );

      await pumpEventQueue();

      expect(cache.isComputing, isFalse);
      expect(cache.isSettled, isTrue);
      expect(cache.fastPath, isNotNull);
      expect(cache.fullPath, isNotNull);

      const latest = EnhanceSettings(
        filter: EnhanceFilter.blackWhite,
        sensitivity: 100,
      );
      final fastReq = callsAt(calls, EnhancePreviewCache.fastMaxDimension).single;
      expect(fastReq.settings, latest);
      expect(fastReq.targetPath, cache.fastPath);
      final fullReq = callsAt(calls, EnhancePreviewCache.fullMaxDimension).single;
      expect(fullReq.settings, latest);
      expect(fullReq.targetPath, cache.fullPath);
    });

    test('displayPath prefers the settled full render over the fast one',
        () async {
      final calls = <EnhanceFileRequest>[];
      final cache = cacheWith(calls);
      addTearDown(cache.dispose);

      cache.update(const EnhanceSettings(filter: EnhanceFilter.colorful));
      await pumpEventQueue();
      expect(cache.fastPath, isNotNull);
      expect(cache.fullPath, isNotNull);
      expect(cache.displayPath, cache.fullPath);
    });

    test('flush returns the cached save file without re-rendering when settled',
        () async {
      final calls = <EnhanceFileRequest>[];
      final cache = cacheWith(calls);
      addTearDown(cache.dispose);

      const settings = EnhanceSettings(
        filter: EnhanceFilter.colorful,
        contrast: 40,
      );
      cache.update(settings);
      await pumpEventQueue();
      final path = cache.fullPath;
      expect(path, isNotNull);
      expect(cache.isFullSettled, isTrue);

      final flushed = await cache.flush();
      expect(flushed, path);
      expect(calls.length, 2); // one fast + one full, no more
    });

    test('flush forces the full render immediately while its debounce is pending',
        () async {
      final calls = <EnhanceFileRequest>[];
      final cache = cacheWith(
        calls,
        fullDebounce: const Duration(days: 1),
      );
      addTearDown(cache.dispose);

      const settings = EnhanceSettings(
        filter: EnhanceFilter.blackWhite,
        sensitivity: 50,
      );
      cache.update(settings);

      // The fast tier starts rendering right away (no debounce)...
      await pumpEventQueue();
      expect(
        callsAt(calls, EnhancePreviewCache.fastMaxDimension).single.settings,
        settings,
      );
      // ...while the full tier is still awaiting its (day-long) debounce.
      expect(cache.isFullSettled, isFalse);

      final path = await cache.flush();
      // The full render ran only on flush, with the last-changed settings.
      expect(
        callsAt(calls, EnhancePreviewCache.fullMaxDimension).single.settings,
        settings,
      );
      expect(path, isNotNull);
      expect(cache.isComputing, isFalse);
      expect(cache.isFullSettled, isTrue);
    });

    test('the fast tier renders degraded; the save tier always at full quality',
        () async {
      final calls = <EnhanceFileRequest>[];
      final cache = cacheWith(calls);
      addTearDown(cache.dispose);

      cache.update(const EnhanceSettings(filter: EnhanceFilter.colorful));
      await pumpEventQueue();

      final fastReq = callsAt(calls, EnhancePreviewCache.fastMaxDimension).single;
      expect(fastReq.maxDimension, EnhancePreviewCache.fastMaxDimension);
      expect(fastReq.jpegQuality, EnhancePreviewCache.fastJpegQuality);

      // Saving must never be degraded by the fast preview tier.
      final fullReq = callsAt(calls, EnhancePreviewCache.fullMaxDimension).single;
      expect(fullReq.maxDimension, EnhancePreviewCache.fullMaxDimension);
      expect(fullReq.jpegQuality, 92);
    });

    test('update(original) drops pending renders and clears the cache',
        () async {
      final calls = <EnhanceFileRequest>[];
      final cache = cacheWith(calls);
      addTearDown(cache.dispose);

      cache.update(const EnhanceSettings(filter: EnhanceFilter.colorful));
      await pumpEventQueue();
      expect(cache.fastPath, isNotNull);
      expect(cache.fullPath, isNotNull);

      cache.update(const EnhanceSettings(filter: EnhanceFilter.original));
      expect(cache.fastPath, isNull);
      expect(cache.fullPath, isNull);
      expect(cache.isSettled, isTrue);
      expect(await cache.flush(), isNull);
      expect(calls.length, 2); // the colorful renders only
    });

    test('a never-seeded cache does not claim to be settled', () {
      final cache = cacheWith(<EnhanceFileRequest>[]);
      addTearDown(cache.dispose);
      // Regressed when `isSettled` compared two nulls as equal, so Save
      // skipped the render and saved the raw file.
      expect(cache.isSettled, isFalse);
      expect(cache.isFullSettled, isFalse);
    });

    test('a default colorful page renders on flush instead of returning null',
        () async {
      final calls = <EnhanceFileRequest>[];
      final cache = cacheWith(calls);
      addTearDown(cache.dispose);

      // EnhanceSettings() defaults to Colorful, so isUntouched is false.
      const defaults = EnhanceSettings();
      cache.update(defaults);
      expect(cache.isSettled, isFalse);

      final path = await cache.flush();
      expect(
        callsAt(calls, EnhancePreviewCache.fullMaxDimension).single.settings,
        defaults,
      );
      expect(path, isNotNull);
      expect(cache.isFullSettled, isTrue);
    });

    test('a render in-flight when newer settings arrive converges to the '
        'latest instead of silently dropping the change', () async {
      final writer = _ControllableWriter();
      final cache = EnhancePreviewCache(
        sourcePath: source,
        fullDebounce: const Duration(days: 1), // keep the full tier out of it
        writer: writer.call,
        fastSourceWriter: (_, target) async => target,
      );
      addTearDown(cache.dispose);

      cache.update(
        const EnhanceSettings(filter: EnhanceFilter.colorful, saturation: 10),
      );
      await pumpEventQueue();
      expect(writer.pendingCount, 1); // fast render A is in-flight

      cache.update(
        const EnhanceSettings(filter: EnhanceFilter.colorful, saturation: 80),
      );
      await pumpEventQueue();
      expect(writer.pendingCount, 1); // new fire was swallowed by the in-flight render

      writer.resolveNext(); // A completes, stale → must re-render the latest
      await pumpEventQueue();
      expect(writer.requests.length, 2);
      expect(writer.pendingCount, 1); // render B is now in-flight

      writer.resolveNext(); // B completes → committed
      await pumpEventQueue();

      expect(cache.fastPath, writer.requests[1].targetPath);
      expect(cache.isSettled, isTrue);
      expect(writer.pendingCount, 0);
      expect(writer.requests, hasLength(2)); // converged, no runaway loop
    });

    test('full renders are globally serialized across cache instances',
        () async {
      var inFlight = 0;
      var maxInFlight = 0;
      final calls = <EnhanceFileRequest>[];
      Future<String?> writer(EnhanceFileRequest r) async {
        if (r.maxDimension == EnhancePreviewCache.fullMaxDimension) {
          inFlight++;
          if (inFlight > maxInFlight) maxInFlight = inFlight;
        }
        calls.add(r);
        await Future<void>.delayed(Duration.zero);
        if (r.maxDimension == EnhancePreviewCache.fullMaxDimension) inFlight--;
        return r.targetPath;
      }

      final a = EnhancePreviewCache(
        sourcePath: '${source}a.jpg',
        fullDebounce: Duration.zero,
        writer: writer,
        fastSourceWriter: (_, target) async => target,
      );
      final b = EnhancePreviewCache(
        sourcePath: '${source}b.jpg',
        fullDebounce: Duration.zero,
        writer: writer,
        fastSourceWriter: (_, target) async => target,
      );
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      a.update(const EnhanceSettings(filter: EnhanceFilter.colorful));
      b.update(const EnhanceSettings(filter: EnhanceFilter.colorful));
      await pumpEventQueue();

      expect(maxInFlight, 1); // never two 2400px renders at once
      expect(a.isFullSettled, isTrue);
      expect(b.isFullSettled, isTrue);
      expect(
        calls
            .where((r) => r.maxDimension == EnhancePreviewCache.fullMaxDimension),
        hasLength(2),
      );
    });
  });
}