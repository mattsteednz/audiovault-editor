import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:audiovault_editor/services/app_logger.dart';

/// Global configuration for atomic writes.
class AtomicWriteConfig {
  AtomicWriteConfig._();

  /// When true, [writeFileAtomic] preserves the original file as
  /// `<name>.bak` before its first replacement (per target). Toggled from
  /// Settings; default off.
  static bool keepBackups = false;
}

/// Describes an in-place edit of an existing file as one contiguous replaced
/// region plus optional bytes appended after the original end.
///
/// This lets huge media files be rewritten with O(replacement) memory instead
/// of O(file) — the untouched head and tail are stream-copied in chunks.
class SplicePlan {
  /// Absolute offset in the ORIGINAL file where the replacement begins.
  final int replaceStart;

  /// Absolute offset (exclusive) in the ORIGINAL file where the replaced
  /// region ends. Everything from here to EOF is copied verbatim after the
  /// replacement (before [appendix]).
  final int replaceEnd;

  final Uint8List replacement;

  /// Extra bytes written after the original EOF (e.g. M4B chapter samples).
  final Uint8List? appendix;

  SplicePlan({
    required this.replaceStart,
    required this.replaceEnd,
    required this.replacement,
    this.appendix,
  });

  bool get hasAppendix => appendix != null && appendix!.isNotEmpty;

  /// Materialises the plan against the full original bytes — used by tests
  /// and by callers that already hold the whole buffer.
  Uint8List execute(Uint8List original) {
    assert(replaceStart <= replaceEnd);
    assert(replaceEnd <= original.length);
    if (!hasAppendix) {
      return _spliceBytes(original, replaceStart, replaceEnd, replacement);
    }
    final out = BytesBuilder();
    out.add(original.sublist(0, replaceStart));
    out.add(replacement);
    out.add(original.sublist(replaceEnd));
    out.add(appendix!);
    return out.toBytes();
  }

  static Uint8List _spliceBytes(
      Uint8List src, int start, int end, Uint8List replacement) {
    final result =
        Uint8List(src.length - (end - start) + replacement.length);
    result.setRange(0, start, src.sublist(0, start));
    result.setRange(start, start + replacement.length, replacement);
    result.setRange(
        start + replacement.length, result.length, src.sublist(end));
    return result;
  }
}

const int _copyChunkSize = 1 << 20; // 1 MiB

/// Writes [plan] to [targetPath] atomically using constant memory: the
/// untouched regions are streamed from the source in [_copyChunkSize]
/// chunks into a temp file which then replaces the target.
Future<void> writeFileAtomicSplice(String targetPath, SplicePlan plan) async {
  final dir = p.dirname(targetPath);
  final name = p.basename(targetPath);
  final tmpPath = p.join(
      dir, '.$name.a.tmp${DateTime.now().microsecondsSinceEpoch}');
  final tmp = File(tmpPath);
  IOSink? sink;
  RandomAccessFile? src;
  try {
    // Optional safety net before we touch anything.
    if (AtomicWriteConfig.keepBackups) {
      final target = File(targetPath);
      if (await target.exists()) {
        final bakPath = '$targetPath.bak';
        if (!await File(bakPath).exists()) {
          await target.copy(bakPath);
        }
      }
    }

    src = await File(targetPath).open();
    sink = tmp.openWrite();

    // Head — chunked.
    var pos = 0;
    while (pos < plan.replaceStart) {
      final n = math.min(_copyChunkSize, plan.replaceStart - pos);
      sink.add(await src.read(n));
      pos += n;
    }

    // Replacement.
    sink.add(plan.replacement);

    // Tail — reposition and chunked-copy to EOF.
    await src.setPosition(plan.replaceEnd);
    while (true) {
      final chunk = await src.read(_copyChunkSize);
      if (chunk.isEmpty) break;
      sink.add(chunk);
    }

    // Appendix (e.g. chapter samples).
    if (plan.hasAppendix) {
      sink.add(plan.appendix!);
    }

    await sink.flush();
    await sink.close();
    sink = null;
    await src.close();
    src = null;
    await tmp.rename(targetPath);
  } catch (e) {
    AppLog.e('Streaming atomic write failed for $targetPath: $e');
    try {
      await sink?.close();
    } catch (_) {}
    try {
      await src?.close();
    } catch (_) {}
    try {
      if (await tmp.exists()) await tmp.delete();
    } catch (cleanupError) {
      AppLog.w('Could not clean up temp file $tmpPath: $cleanupError');
    }
    rethrow;
  }
}
///
/// The data is first written to a hidden temporary file in the same directory
/// (same filesystem, so the final rename is atomic), flushed to disk, and then
/// renamed over [targetPath]. If the process crashes at any point before the
/// rename, the original file is left untouched and only an orphaned `.tmp`
/// file remains.
///
/// On Windows, `File.rename` uses `MoveFileExW` with `MOVEFILE_REPLACE_EXISTING`,
/// so replacing an existing target is supported.
///
/// Throws the underlying [FileSystemException] on failure; in that case any
/// leftover temporary file is removed before rethrowing.
Future<void> writeFileAtomic(String targetPath, Uint8List bytes) async {
  final dir = p.dirname(targetPath);
  final name = p.basename(targetPath);
  final tmpPath = p.join(
      dir, '.$name.a.tmp${DateTime.now().microsecondsSinceEpoch}');
  final tmp = File(tmpPath);
  try {
    await tmp.writeAsBytes(bytes, flush: true);

    // Optional safety net: keep one generation of the original alongside
    // (e.g. book.m4b.bak) before the first overwrite of this session.
    if (AtomicWriteConfig.keepBackups) {
      final target = File(targetPath);
      if (await target.exists()) {
        final bakPath = '$targetPath.bak';
        if (!await File(bakPath).exists()) {
          await target.copy(bakPath);
        }
      }
    }

    await tmp.rename(targetPath);
  } catch (e) {
    AppLog.e('Atomic write failed for $targetPath: $e');
    try {
      if (await tmp.exists()) {
        await tmp.delete();
      }
    } catch (cleanupError) {
      AppLog.w('Could not clean up temp file $tmpPath: $cleanupError');
    }
    rethrow;
  }
}

/// Convenience wrapper of [writeFileAtomic] for UTF-8 string content.
Future<void> writeStringAtomic(String targetPath, String contents) async {
  await writeFileAtomic(targetPath, Uint8List.fromList(utf8.encode(contents)));
}
