import 'dart:async';
import 'dart:isolate';

import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:scan_documnet_app/services/enchance_service.dart';

/// Warm-up job sent right after a worker spawns. Processing it forces the
/// OpenCV native library to load in the worker ONCE, so the first real render
/// the user triggers is already fast.
class _WarmJob {
  const _WarmJob();
}

/// Tells the worker to exit. Rarely needed — [EnhanceWorker.dispose] kills the
/// isolate directly — but keeps the loop explicit.
const _warmJob = _WarmJob();

@pragma('vm:entry-point')
void enhanceWorkerMain(SendPort host) {
  final commands = ReceivePort();
  host.send(commands.sendPort);
  commands.listen((message) {
    final (jobId, job) = message as (int, Object);
    try {
      host.send((jobId, _runJob(job)));
    } catch (_) {
      // A failed job must never kill the worker — reply null and stay alive
      // for the next render.
      host.send((jobId, null));
    }
  });
}

String? _runJob(Object job) {
  if (job is _WarmJob) return _warmUp();
  if (job is EnhanceFileRequest) return enhanceFileEntry(job);
  if (job is EnhanceFastSourceRequest) return fastSourceEntry(job);
  return null;
}

String? _warmUp() {
  var mat = cv.Mat.ones(8, 8, cv.MatType.CV_8UC3);
  final copy = mat.clone();
  mat.dispose();
  copy.dispose();
  return null;
}

/// A long-lived isolate that runs enhancement jobs reusing the same OpenCV
/// native binding (loaded once), instead of spawning a fresh isolate that
/// reloads the library on every `compute(...)` call.
class EnhanceWorker {
  EnhanceWorker._(this._inbox) {
    _inbox.listen((message) {
      if (message is SendPort) {
        _commands = message;
        if (!_ready.isCompleted) _ready.complete();
        return;
      }
      final (jobId, result) = message as (int, String?);
      _timers.remove(jobId)?.cancel();
      final completer = _pending.remove(jobId);
      if (completer != null && !completer.isCompleted) {
        completer.complete(result);
      }
    });
  }

  final ReceivePort _inbox;
  final _ready = Completer<void>();
  late SendPort _commands;
  late Isolate _isolate;
  final Map<int, Completer<String?>> _pending = {};
  final Map<int, Timer> _timers = {};
  int _nextJobId = 1;
  bool _disposed = false;

  /// How long a job may run before its caller gives up and treats it as
  /// failed, so a dead worker can never hang a Save.
  static const Duration _jobTimeout = Duration(seconds: 15);

  static Future<EnhanceWorker> spawn() async {
    final inbox = ReceivePort();
    final worker = EnhanceWorker._(inbox);
    final isolate = await Isolate.spawn(enhanceWorkerMain, inbox.sendPort);
    worker._isolate = isolate;
    await worker._ready.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw StateError('worker never reported its command port'),
    );
    return worker;
  }

  Future<String?> submit(Object job) {
    if (_disposed) return Future.value(null);
    final jobId = _nextJobId++;
    final completer = Completer<String?>();
    _pending[jobId] = completer;
    _timers[jobId] = Timer(_jobTimeout, () {
      _pending.remove(jobId);
      if (!completer.isCompleted) completer.complete(null);
    });
    try {
      _commands.send((jobId, job));
    } catch (_) {
      _pending.remove(jobId);
      _timers.remove(jobId)?.cancel();
      if (!completer.isCompleted) completer.complete(null);
    }
    return completer.future;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _isolate.kill(priority: Isolate.immediate);
    _inbox.close();
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.complete(null);
    }
    _pending.clear();
  }
}

/// Owns the two persistent workers the preview screen renders through: one for
/// the interactive fast tier and one for the full (save-quality) tier, so a
/// background 2400px render never blocks a slider change.
class EnhanceWorkerSet {
  EnhanceWorker? _fast;
  EnhanceWorker? _full;
  Future<void>? _warming;
  bool _disposed = false;

  /// Spawns both workers (if not already) and forces their native library to
  /// load. Called once when the preview screen opens, before the user touches
  /// any slider. Safe to call repeatedly.
  Future<void> ensureWarm() => _warming ??= _ensureWarm();

  Future<void> _ensureWarm() async {
    try {
      final spawned = await Future.wait([
        EnhanceWorker.spawn(),
        EnhanceWorker.spawn(),
      ]);
      if (_disposed) {
        spawned[0].dispose();
        spawned[1].dispose();
        return;
      }
      _fast = spawned[0];
      _full = spawned[1];
      await Future.wait([
        _fast!.submit(_warmJob),
        _full!.submit(_warmJob),
      ]);
    } catch (_) {
      // Workers unavailable (e.g. spawn failed): the workers stay null and
      // [enhance]/[prep] degrade to the one-shot `compute` path.
      _fast?.dispose();
      _full?.dispose();
      _fast = null;
      _full = null;
    }
  }

  /// Routes a [request] to the matching persistent worker. Falls back to the
  /// one-shot `compute` path if warm-up failed, so rendering still works.
  Future<String?> enhance(EnhanceFileRequest request) async {
    await ensureWarm();
    if (_disposed) return null;
    final worker = request.maxDimension == EnhancePreviewCache.fastMaxDimension
        ? _fast
        : _full;
    return worker?.submit(request) ?? EnhanceService.writeEnhanced(request);
  }

  /// Writes the fast tier's one-time small working copy through the fast
  /// worker. Falls back to `compute` if warm-up failed.
  Future<String?> prep(String sourcePath, String targetPath) async {
    await ensureWarm();
    if (_disposed) return null;
    final request = EnhanceFastSourceRequest(
      sourcePath: sourcePath,
      targetPath: targetPath,
      maxDimension: EnhancePreviewCache.fastSourceMaxDimension,
    );
    final worker = _fast;
    return worker?.submit(request) ??
        EnhanceService.writeFastSource(request);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _fast?.dispose();
    _full?.dispose();
    _fast = null;
    _full = null;
  }
}