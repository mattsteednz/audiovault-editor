import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiovault_editor/services/cue_writer.dart';
import 'package:audiovault_editor/widgets/chapter_editor.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Property 14: CUE frame value is always in [0, 74]
  // Validates: Requirements 10.4
  // ---------------------------------------------------------------------------
  group('Property 14: CUE frame value is always in [0, 74]', () {
    /// Extracts the frame component (last two digits) from a MM:SS:FF string.
    int extractFrames(String cueTime) {
      final parts = cueTime.split(':');
      return int.parse(parts[2]);
    }

    test('Duration.zero produces frame 00', () {
      final result = CueWriter.formatCueTime(Duration.zero);
      expect(extractFrames(result), equals(0));
    });

    test('Duration(milliseconds: 999) clamps frame from 75 to 74', () {
      // frames = round(999 * 75 / 1000) = round(74.925) = 75 → clamped to 74
      final result = CueWriter.formatCueTime(const Duration(milliseconds: 999));
      expect(extractFrames(result), equals(74));
    });

    test('Duration(milliseconds: 500) produces frame 38', () {
      // frames = round(500 * 75 / 1000) = round(37.5) = 38
      final result = CueWriter.formatCueTime(const Duration(milliseconds: 500));
      expect(extractFrames(result), equals(38));
    });

    test('Duration(minutes: 1, seconds: 23, milliseconds: 456) produces frame 34', () {
      // ms remainder = 456, frames = round(456 * 75 / 1000) = round(34.2) = 34
      final result = CueWriter.formatCueTime(
          const Duration(minutes: 1, seconds: 23, milliseconds: 456));
      expect(extractFrames(result), equals(34));
    });

    test('frame is always in [0, 74] for a range of durations', () {
      // Test every millisecond from 0 to 999 to ensure clamping works
      for (int ms = 0; ms < 1000; ms++) {
        final d = Duration(milliseconds: ms);
        final result = CueWriter.formatCueTime(d);
        final frames = extractFrames(result);
        expect(frames, inInclusiveRange(0, 74),
            reason: 'Frame out of range for ms=$ms: got $frames');
      }
    });

    test('frame is in [0, 74] for durations with hours', () {
      final durations = [
        const Duration(hours: 1, milliseconds: 999),
        const Duration(hours: 2, minutes: 30, milliseconds: 500),
        const Duration(hours: 10, minutes: 59, seconds: 59, milliseconds: 999),
      ];
      for (final d in durations) {
        final result = CueWriter.formatCueTime(d);
        final frames = extractFrames(result);
        expect(frames, inInclusiveRange(0, 74),
            reason: 'Frame out of range for $d: got $frames');
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Unit tests: formatCueTime
  // ---------------------------------------------------------------------------
  group('formatCueTime unit tests', () {
    test('Duration.zero → 00:00:00', () {
      expect(CueWriter.formatCueTime(Duration.zero), equals('00:00:00'));
    });

    test('Duration(minutes: 1, seconds: 23, milliseconds: 456) → 01:23:34', () {
      expect(
        CueWriter.formatCueTime(
            const Duration(minutes: 1, seconds: 23, milliseconds: 456)),
        equals('01:23:34'),
      );
    });

    test('Duration(milliseconds: 999) → 00:00:74 (clamped from 75)', () {
      expect(
        CueWriter.formatCueTime(const Duration(milliseconds: 999)),
        equals('00:00:74'),
      );
    });

    test('Duration(hours: 1, minutes: 5, seconds: 30) → 65:30:00', () {
      // 1h5m30s = 3930 total seconds = 65 minutes 30 seconds
      expect(
        CueWriter.formatCueTime(
            const Duration(hours: 1, minutes: 5, seconds: 30)),
        equals('65:30:00'),
      );
    });

    test('Duration(milliseconds: 0) → 00:00:00', () {
      expect(
        CueWriter.formatCueTime(const Duration()),
        equals('00:00:00'),
      );
    });

    test('Duration(seconds: 59, milliseconds: 999) → 00:59:74', () {
      expect(
        CueWriter.formatCueTime(
            const Duration(seconds: 59, milliseconds: 999)),
        equals('00:59:74'),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Property 15: CUE sheet structure matches chapter list
  // Validates: Requirements 10.3
  // ---------------------------------------------------------------------------
  group('Property 15: CUE sheet structure matches chapter list', () {
    test('generate produces exactly one FILE directive', () {
      final chapters = [
        const ChapterEntry(title: 'Intro', start: Duration.zero),
        const ChapterEntry(title: 'Chapter 1', start: Duration(minutes: 5)),
      ];
      final result = CueWriter.generate('book.mp3', 'My Book', chapters);
      final fileMatches = RegExp(r'^FILE ', multiLine: true).allMatches(result);
      expect(fileMatches.length, equals(1));
    });

    test('generate produces N TRACK blocks for N chapters', () {
      final chapters = [
        const ChapterEntry(title: 'A', start: Duration.zero),
        const ChapterEntry(title: 'B', start: Duration(minutes: 5)),
        const ChapterEntry(title: 'C', start: Duration(minutes: 10)),
      ];
      final result = CueWriter.generate('book.mp3', 'My Book', chapters);
      final trackMatches =
          RegExp(r'^\s+TRACK \d+ AUDIO', multiLine: true).allMatches(result);
      expect(trackMatches.length, equals(3));
    });

    test('generate produces N INDEX 01 lines for N chapters', () {
      final chapters = [
        const ChapterEntry(title: 'A', start: Duration.zero),
        const ChapterEntry(title: 'B', start: Duration(minutes: 5)),
        const ChapterEntry(title: 'C', start: Duration(minutes: 10)),
      ];
      final result = CueWriter.generate('book.mp3', 'My Book', chapters);
      final indexMatches =
          RegExp(r'^\s+INDEX 01 ', multiLine: true).allMatches(result);
      expect(indexMatches.length, equals(3));
    });

    test('track numbers are zero-padded: 01, 02, ..., 10, 11', () {
      final chapters = List.generate(
        11,
        (i) => ChapterEntry(
          title: 'Chapter $i',
          start: Duration(minutes: i * 5),
        ),
      );
      final result = CueWriter.generate('book.mp3', 'My Book', chapters);
      for (int i = 1; i <= 11; i++) {
        final trackNum = i.toString().padLeft(2, '0');
        expect(result, contains('TRACK $trackNum AUDIO'));
      }
    });

    test('each INDEX 01 line contains a valid MM:SS:FF timestamp', () {
      final chapters = [
        const ChapterEntry(title: 'A', start: Duration.zero),
        const ChapterEntry(title: 'B', start: Duration(minutes: 5, seconds: 30)),
        const ChapterEntry(
            title: 'C',
            start: Duration(
                minutes: 1, seconds: 23, milliseconds: 456)),
      ];
      final result = CueWriter.generate('book.mp3', 'My Book', chapters);
      final indexLines = RegExp(r'INDEX 01 (\d{2}:\d{2}:\d{2})', multiLine: true)
          .allMatches(result);
      expect(indexLines.length, equals(3));
      for (final match in indexLines) {
        final timestamp = match.group(1)!;
        final parts = timestamp.split(':');
        expect(parts.length, equals(3));
        final frames = int.parse(parts[2]);
        expect(frames, inInclusiveRange(0, 74));
      }
    });

    test('generate with varying chapter counts always has matching TRACK and INDEX counts', () {
      for (int n = 1; n <= 20; n++) {
        final chapters = List.generate(
          n,
          (i) => ChapterEntry(
            title: 'Chapter $i',
            start: Duration(minutes: i * 3),
          ),
        );
        final result = CueWriter.generate('book.mp3', 'Album', chapters);
        final trackCount =
            RegExp(r'^\s+TRACK \d+ AUDIO', multiLine: true).allMatches(result).length;
        final indexCount =
            RegExp(r'^\s+INDEX 01 ', multiLine: true).allMatches(result).length;
        expect(trackCount, equals(n), reason: 'TRACK count mismatch for n=$n');
        expect(indexCount, equals(n), reason: 'INDEX count mismatch for n=$n');
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Unit tests: generate
  // ---------------------------------------------------------------------------
  group('generate unit tests', () {
    test('generate with 3 chapters produces correct structure', () {
      final chapters = [
        const ChapterEntry(title: 'Intro', start: Duration.zero),
        const ChapterEntry(title: 'Part 1', start: Duration(minutes: 5)),
        const ChapterEntry(title: 'Part 2', start: Duration(minutes: 12, seconds: 30)),
      ];
      final result = CueWriter.generate('audiobook.mp3', 'My Audiobook', chapters);

      expect(result, contains('PERFORMER ""'));
      expect(result, contains('TITLE "My Audiobook"'));
      expect(result, contains('FILE "audiobook.mp3" MP3'));
      expect(result, contains('TRACK 01 AUDIO'));
      expect(result, contains('TITLE "Intro"'));
      expect(result, contains('INDEX 01 00:00:00'));
      expect(result, contains('TRACK 02 AUDIO'));
      expect(result, contains('TITLE "Part 1"'));
      expect(result, contains('INDEX 01 05:00:00'));
      expect(result, contains('TRACK 03 AUDIO'));
      expect(result, contains('TITLE "Part 2"'));
      expect(result, contains('INDEX 01 12:30:00'));
    });

    test('generate with empty album title uses empty string in TITLE field', () {
      final chapters = [
        const ChapterEntry(title: 'Chapter 1', start: Duration.zero),
      ];
      final result = CueWriter.generate('book.mp3', '', chapters);
      expect(result, contains('TITLE ""'));
    });

    test('generate with title containing double quotes escapes them', () {
      final chapters = [
        const ChapterEntry(title: 'He said "hello"', start: Duration.zero),
      ];
      final result = CueWriter.generate('book.mp3', 'Album "Special"', chapters);
      expect(result, contains('TITLE "Album \\"Special\\""'));
      expect(result, contains('TITLE "He said \\"hello\\""'));
    });

    test('generate with mp3 filename containing quotes escapes them', () {
      final chapters = [
        const ChapterEntry(title: 'Chapter', start: Duration.zero),
      ];
      final result = CueWriter.generate('my "book".mp3', 'Album', chapters);
      expect(result, contains('FILE "my \\"book\\".mp3" MP3'));
    });

    test('generate output starts with PERFORMER line', () {
      final chapters = [
        const ChapterEntry(title: 'Ch', start: Duration.zero),
      ];
      final result = CueWriter.generate('book.mp3', 'Album', chapters);
      expect(result.trimLeft().startsWith('PERFORMER ""'), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Integration test: file I/O
  // ---------------------------------------------------------------------------
  group('Integration: CueWriter.write', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('cue_writer_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('write creates file at bookPath/<bookTitle>.cue', () async {
      final chapters = [
        const ChapterEntry(title: 'Intro', start: Duration.zero),
        const ChapterEntry(title: 'Chapter 1', start: Duration(minutes: 5)),
      ];
      await CueWriter.write(tempDir.path, 'My Book', 'book.mp3', chapters);

      final expectedFile = File('${tempDir.path}/My Book.cue');
      expect(expectedFile.existsSync(), isTrue);
    });

    test('write file content contains FILE directive with mp3 filename', () async {
      final chapters = [
        const ChapterEntry(title: 'Intro', start: Duration.zero),
      ];
      await CueWriter.write(tempDir.path, 'My Book', 'book.mp3', chapters);

      final file = File('${tempDir.path}/My Book.cue');
      final content = file.readAsStringSync();
      expect(content, contains('FILE "book.mp3" MP3'));
    });

    test('write file content contains correct number of TRACK blocks', () async {
      final chapters = [
        const ChapterEntry(title: 'Intro', start: Duration.zero),
        const ChapterEntry(title: 'Chapter 1', start: Duration(minutes: 5)),
        const ChapterEntry(title: 'Chapter 2', start: Duration(minutes: 10)),
      ];
      await CueWriter.write(tempDir.path, 'My Book', 'book.mp3', chapters);

      final file = File('${tempDir.path}/My Book.cue');
      final content = file.readAsStringSync();
      final trackCount =
          RegExp(r'^\s+TRACK \d+ AUDIO', multiLine: true).allMatches(content).length;
      expect(trackCount, equals(3));
    });

    test('write sanitises title with special characters for filename', () async {
      final chapters = [
        const ChapterEntry(title: 'Intro', start: Duration.zero),
      ];
      // Title with characters invalid in filenames
      await CueWriter.write(
          tempDir.path, 'My: Book <Special>', 'book.mp3', chapters);

      final expectedFile = File('${tempDir.path}/My Book Special.cue');
      expect(expectedFile.existsSync(), isTrue);
    });

    test('write uses "chapters" as filename when sanitised title is empty', () async {
      final chapters = [
        const ChapterEntry(title: 'Intro', start: Duration.zero),
      ];
      // Title that becomes empty after sanitisation
      await CueWriter.write(tempDir.path, '<>:"/\\|?*', 'book.mp3', chapters);

      final expectedFile = File('${tempDir.path}/chapters.cue');
      expect(expectedFile.existsSync(), isTrue);
    });

    test('write file content contains TITLE from album title', () async {
      final chapters = [
        const ChapterEntry(title: 'Intro', start: Duration.zero),
      ];
      await CueWriter.write(tempDir.path, 'Great Book', 'audio.mp3', chapters);

      final file = File('${tempDir.path}/Great Book.cue');
      final content = file.readAsStringSync();
      expect(content, contains('TITLE "Great Book"'));
    });
  });
}
