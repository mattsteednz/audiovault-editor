import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

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

class SilenceDetectionService {
  /// Resolves the ffmpeg executable by checking three locations in order:
  ///
  ///   1. System PATH — `ffmpeg` / `ffmpeg.exe`
  ///   2. `<exe_dir>/ffmpeg.exe`
  ///   3. `<exe_dir>/ffmpeg/bin/ffmpeg.exe`
  ///
  /// Returns the first path that resolves to an existing file, or null.
  static String? get ffmpegPath {
    // 1. System PATH
    final onPath = _findOnPath();
    if (onPath != null) return onPath;

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

  static bool get isAvailable => ffmpegPath != null;

  /// Attempts to find `ffmpeg` on the system PATH by running `ffmpeg -version`.
  static String? _findOnPath() {
    try {
      final result = Process.runSync('ffmpeg', ['-version'],
          runInShell: true, stdoutEncoding: null, stderrEncoding: null);
      if (result.exitCode == 0) return 'ffmpeg';
    } catch (_) {}
    return null;
  }

  // ---------------------------------------------------------------------------
  // Detection
  // ---------------------------------------------------------------------------

  /// Runs `ffmpeg silencedetect` on [filePath] and streams progress + result.
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
  }) async* {
    final exe = ffmpegPath;
    if (exe == null) {
      yield SilenceDetectionError(
          'ffmpeg not found. Add ffmpeg to your PATH, or place ffmpeg.exe '
          '(or ffmpeg/bin/ffmpeg.exe) next to audiovault_editor.exe.');
      return;
    }

    final noiseArg = '${noiseFloorDb.toStringAsFixed(1)}dB';
    final durationArg = minSilenceSecs.toStringAsFixed(2);
    final filter = 'silencedetect=noise=$noiseArg:d=$durationArg';

    Process? process;
    try {
      process = await Process.start(exe, [
        '-i', filePath,
        '-af', filter,
        '-f', 'null',
        '-',
      ]);

      final boundaries = <Duration>[];

      // Collect stderr and parse silence boundaries
      final stderrCompleter = Completer<void>();

      process.stderr
          .transform(const SystemEncoding().decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          // Silence boundary: "[silencedetect @ ...] silence_end: 874.123 | ..."
          final silenceMatch =
              RegExp(r'silence_end:\s*([\d.]+)').firstMatch(line);
          if (silenceMatch != null) {
            final secs = double.tryParse(silenceMatch.group(1)!);
            if (secs != null) {
              boundaries.add(Duration(microseconds: (secs * 1e6).round()));
            }
          }
        },
        onDone: () => stderrCompleter.complete(),
        onError: (_) => stderrCompleter.complete(),
        cancelOnError: false,
      );

      // Wait for stderr to finish
      while (!stderrCompleter.isCompleted) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      final exitCode = await process.exitCode;

      if (exitCode == 0 || exitCode == 255) {
        // exitCode 255 is normal for `-f null -` on some ffmpeg builds
        yield SilenceDetectionComplete(boundaries);
      } else {
        yield SilenceDetectionError('ffmpeg exited with code $exitCode');
      }
    } catch (e) {
      process?.kill();
      yield SilenceDetectionError('ffmpeg error: $e');
    }
  }
}
