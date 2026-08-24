import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:audiovault_editor/services/app_logger.dart';

// ---------------------------------------------------------------------------
// Progress events (sealed class hierarchy)
// ---------------------------------------------------------------------------

sealed class SilenceDetectionProgress {}

class SilenceDetectionProgressUpdate extends SilenceDetectionProgress {
  /// 0.0–1.0, or null when total duration is unknown (indeterminate).
  final double? fraction;
  SilenceDetectionProgressUpdate(this.fraction);
}

class SilenceDetectionComplete extends SilenceDetectionProgress {
  /// Timestamps of silence-end points — each becomes a chapter boundary.
  /// The first chapter always starts at Duration.zero (not included here).
  final List<Duration> boundaries;
  SilenceDetectionComplete(this.boundaries);
}

class SilenceDetectionError extends SilenceDetectionProgress {
  final String message;
  SilenceDetectionError(this.message);
}

class SilenceDetectionCancelled extends SilenceDetectionProgress {
  SilenceDetectionCancelled();
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Runs `ffmpeg silencedetect` on an audio file and reports boundaries plus
/// progress.
///
/// One service instance drives one detection run at a time; call [cancel] to
/// kill the running ffmpeg process (the stream then emits
/// [SilenceDetectionCancelled]).
class SilenceDetectionService {
  static String? _cachedPath;
  static bool _lookupDone = false;

  /// User-configured ffmpeg location (settings override). When set it wins
  /// over PATH and exe-relative probing.
  static String? _customPath;

  /// Sets the custom ffmpeg path override (null clears it) and invalidates
  /// the cached lookup.
  static void setCustomPath(String? path) {
    _customPath = (path == null || path.trim().isEmpty) ? null : path.trim();
    clearCachedFfmpegPath();
  }

  static String? get customPath => _customPath;

  /// Resolves the ffmpeg executable by checking, in order:
  ///
  ///   0. Settings override (`_customPath`)
  ///   1. System PATH — `ffmpeg` / `ffmpeg.exe`
  ///   2. `<exe_dir>/ffmpeg.exe`
  ///   3. `<exe_dir>/ffmpeg/bin/ffmpeg.exe`
  ///
  /// The result is cached after the first lookup (the probe spawns a process,
  /// so it must not run on every build). Returns the first path that resolves
  /// to an existing file, or null.
  static String? get ffmpegPath {
    if (_lookupDone) return _cachedPath;
    if (_customPath != null && File(_customPath!).existsSync()) {
      _cachedPath = _customPath;
      _lookupDone = true;
      return _cachedPath;
    }
    _cachedPath = _resolveFfmpeg();
    _lookupDone = true;
    return _cachedPath;
  }

  /// Resets the cached resolution (used by tests).
  static void clearCachedFfmpegPath() {
    _cachedPath = null;
    _lookupDone = false;
  }

  static bool get isAvailable => ffmpegPath != null;

  static String? _resolveFfmpeg() {
    // 1. System PATH — probed by actually running `ffmpeg -version`.
    try {
      final result = Process.runSync('ffmpeg', ['-version'],
          runInShell: true, stdoutEncoding: null, stderrEncoding: null);
      if (result.exitCode == 0) return 'ffmpeg';
    } catch (e) {
      AppLog.d('ffmpeg not found on PATH: $e');
    }

    // Resolve exe directory
    final exeDir = p.dirname(Platform.resolvedExecutable);

    // 2. <exe_dir>/ffmpeg.exe
    final adjacent = p.join(exeDir, 'ffmpeg.exe');
    if (File(adjacent).existsSync()) return adjacent;

    // 3. <exe_dir>/ffmpeg/bin/ffmpeg.exe
    final binSubfolder = p.join(exeDir, 'ffmpeg', 'bin', 'ffmpeg.exe');
    if (File(binSubfolder).existsSync()) return binSubfolder;

    return null;
  }

  Process? _process;
  bool _cancelled = false;

  /// Kills any running ffmpeg process. The [detect] stream will emit
  /// [SilenceDetectionCancelled] as its terminal event.
  void cancel() {
    _cancelled = true;
    try {
      _process?.kill();
    } catch (e) {
      AppLog.w('Failed to kill ffmpeg process: $e');
    }
  }

  /// Runs `ffmpeg silencedetect` on [filePath], streaming progress and result.
  ///
  /// [noiseFloorDb]   — e.g. -45.0
  /// [minSilenceSecs] — e.g. 1.5
  /// [totalDuration]  — used to compute progress percentage; null → indeterminate
  ///
  /// The returned stream emits:
  ///   - Zero or more [SilenceDetectionProgressUpdate]
  ///   - Exactly one terminal event: [SilenceDetectionComplete],
  ///     [SilenceDetectionError], or [SilenceDetectionCancelled]
  Stream<SilenceDetectionProgress> detect({
    required String filePath,
    required double noiseFloorDb,
    required double minSilenceSecs,
    Duration? totalDuration,
  }) {
    _cancelled = false;
    final controller = StreamController<SilenceDetectionProgress>();

    Future<void> runDetection() async {
      Process? process;
      try {
        final exe = ffmpegPath;
        if (exe == null) {
          controller.add(SilenceDetectionError(
              'ffmpeg not found. Add ffmpeg to your PATH, or place ffmpeg.exe '
              '(or ffmpeg/bin/ffmpeg.exe) next to audiovault_editor.exe.'));
          return;
        }

        final noiseArg = '${noiseFloorDb.toStringAsFixed(1)}dB';
        final durationArg = minSilenceSecs.toStringAsFixed(2);
        final filter = 'silencedetect=noise=$noiseArg:d=$durationArg';

        process = await Process.start(exe, [
          '-nostats',
          '-i', filePath,
          '-af', filter,
          '-f', 'null',
          '-',
          '-progress', 'pipe:1',
        ]);
        _process = process;

        final boundaries = <Duration>[];
        final stderrDone = Completer<void>();
        final stdoutDone = Completer<void>();
        int? lastEmittedMicros;

        // Silence boundaries arrive on stderr.
        process.stderr
            .transform(const SystemEncoding().decoder)
            .transform(const LineSplitter())
            .listen(
          (line) {
            // "[silencedetect @ ...] silence_end: 874.123 | ..."
            final silenceMatch =
                RegExp(r'silence_end:\s*([\d.]+)').firstMatch(line);
            if (silenceMatch != null) {
              final secs = double.tryParse(silenceMatch.group(1)!);
              if (secs != null) {
                boundaries
                    .add(Duration(microseconds: (secs * 1e6).round()));
              }
            }
          },
          onDone: stderrDone.complete,
          onError: (_) => stderrDone.complete(),
          cancelOnError: false,
        );

        // Machine-readable progress arrives on stdout (`-progress pipe:1`):
        // lines like `out_time_us=1234567890`. Note ffmpeg's `out_time_ms`
        // historically carries microseconds too, so it is used as a fallback
        // with the same unit interpretation.
        process.stdout
            .transform(const SystemEncoding().decoder)
            .transform(const LineSplitter())
            .listen(
          (line) {
            final dur = totalDuration;
            if (dur == null || dur.inMicroseconds <= 0) return;
            final t = line.trim();
            int? micros;
            if (t.startsWith('out_time_us=')) {
              micros = int.tryParse(t.substring('out_time_us='.length));
            } else if (t.startsWith('out_time_ms=')) {
              micros = int.tryParse(t.substring('out_time_ms='.length));
            }
            if (micros == null || micros < 0) return;
            // Throttle: emit at most every ~0.5% of progress change.
            if (lastEmittedMicros != null &&
                (micros - lastEmittedMicros!).abs() <
                    dur.inMicroseconds * 0.005) {
              return;
            }
            lastEmittedMicros = micros;
            final fraction =
                (micros / dur.inMicroseconds).clamp(0.0, 1.0);
            controller.add(SilenceDetectionProgressUpdate(fraction));
          },
          onDone: stdoutDone.complete,
          onError: (_) => stdoutDone.complete(),
          cancelOnError: false,
        );

        // Wait for both pipes to drain, then the process to exit.
        await stderrDone.future;
        await stdoutDone.future;
        final exitCode = await process.exitCode;

        if (_cancelled) {
          controller.add(SilenceDetectionCancelled());
        } else if (exitCode == 0 || exitCode == 255) {
          // exitCode 255 is normal for `-f null -` on some ffmpeg builds
          controller.add(SilenceDetectionComplete(boundaries));
        } else {
          controller
              .add(SilenceDetectionError('ffmpeg exited with code $exitCode'));
        }
      } catch (e) {
        AppLog.e('ffmpeg silencedetect failed: $e');
        if (_cancelled) {
          controller.add(SilenceDetectionCancelled());
        } else {
          controller.add(SilenceDetectionError('ffmpeg error: $e'));
        }
      } finally {
        _process = null;
        // Guarantee no zombie process even if the consumer stopped listening.
        try {
          process?.kill();
        } catch (_) {}
        await controller.close();
      }
    }

    unawaited(runDetection());
    return controller.stream;
  }
}
