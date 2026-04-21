import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:audiovault_editor/widgets/chapter_editor.dart';

/// Service for generating and writing CUE sheet files.
///
/// CUE sheets use MM:SS:FF notation at 75 frames per second.
class CueWriter {
  const CueWriter._();

  /// Converts a [Duration] to CUE MM:SS:FF notation (75 fps).
  ///
  /// Frames = round(milliseconds_remainder * 75 / 1000), clamped to [0, 74].
  static String formatCueTime(Duration d) {
    final totalMs = d.inMilliseconds;
    final minutes = totalMs ~/ 60000;
    final seconds = (totalMs % 60000) ~/ 1000;
    final msRemainder = totalMs % 1000;
    final frames = (msRemainder * 75 / 1000).round().clamp(0, 74);
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}:'
        '${frames.toString().padLeft(2, '0')}';
  }

  /// Generates CUE sheet content as a String. Pure function — no I/O.
  ///
  /// Format:
  /// ```
  /// PERFORMER ""
  /// TITLE "<albumTitle>"
  /// FILE "<mp3Filename>" MP3
  ///   TRACK 01 AUDIO
  ///     TITLE "<chapter title>"
  ///     INDEX 01 MM:SS:FF
  ///   TRACK 02 AUDIO
  ///     ...
  /// ```
  static String generate(
    String mp3Filename,
    String albumTitle,
    List<ChapterEntry> chapters,
  ) {
    final buf = StringBuffer();
    buf.writeln('PERFORMER ""');
    buf.writeln('TITLE "${_escapeCue(albumTitle)}"');
    buf.writeln('FILE "${_escapeCue(mp3Filename)}" MP3');
    for (int i = 0; i < chapters.length; i++) {
      final trackNum = (i + 1).toString().padLeft(2, '0');
      buf.writeln('  TRACK $trackNum AUDIO');
      buf.writeln('    TITLE "${_escapeCue(chapters[i].title)}"');
      buf.writeln('    INDEX 01 ${formatCueTime(chapters[i].start)}');
    }
    return buf.toString();
  }

  /// Writes a CUE file to `bookPath/bookTitle.cue`.
  ///
  /// Throws [FileSystemException] on failure.
  static Future<void> write(
    String bookPath,
    String bookTitle,
    String mp3Filename,
    List<ChapterEntry> chapters,
  ) async {
    final content = generate(mp3Filename, bookTitle, chapters);
    // Sanitise bookTitle for use as a filename
    final safeTitle = bookTitle
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final filename = safeTitle.isEmpty ? 'chapters' : safeTitle;
    final filePath = p.join(bookPath, '$filename.cue');
    await File(filePath).writeAsString(content, flush: true);
  }

  static String _escapeCue(String s) => s.replaceAll('"', '\\"');
}
