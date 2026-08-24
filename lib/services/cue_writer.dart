import 'package:path/path.dart' as p;
import 'package:audiovault_editor/models/chapter_entry.dart';
import 'package:audiovault_editor/services/writers/atomic_file_writer.dart';

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
  /// FILE "<audioFilename>" <audioType>
  ///   TRACK 01 AUDIO
  ///     TITLE "<chapter title>"
  ///     INDEX 01 MM:SS:FF
  ///   TRACK 02 AUDIO
  ///     ...
  /// ```
  static String generate(
    String audioFilename,
    String albumTitle,
    List<ChapterEntry> chapters,
  ) {
    final buf = StringBuffer();
    buf.writeln('PERFORMER ""');
    buf.writeln('TITLE "${_escapeCue(albumTitle)}"');
    
    // Determine audio type from file extension
    final audioType = _getAudioType(audioFilename);
    buf.writeln('FILE "${_escapeCue(audioFilename)}" $audioType');
    
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
    String audioFilename,
    List<ChapterEntry> chapters,
  ) async {
    final content = generate(audioFilename, bookTitle, chapters);
    // Sanitise bookTitle for use as a filename
    final safeTitle = bookTitle
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final filename = safeTitle.isEmpty ? 'chapters' : safeTitle;
    final filePath = p.join(bookPath, '$filename.cue');
    await writeStringAtomic(filePath, content);
  }

  static String _escapeCue(String s) => s.replaceAll('"', '\\"');

  /// Returns the CUE sheet audio type based on file extension.
  static String _getAudioType(String filename) {
    final ext = p.extension(filename).toLowerCase();
    switch (ext) {
      case '.mp3':
        return 'MP3';
      case '.wav':
        return 'WAVE';
      case '.flac':
        return 'FLAC';
      case '.ogg':
        return 'OGG';
      case '.m4a':
      case '.m4b':
      case '.mp4':
        return 'MP4';
      case '.aiff':
      case '.aif':
        return 'AIFF';
      default:
        return 'BINARY';
    }
  }
}
