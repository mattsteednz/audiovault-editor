import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiovault_editor/models/audiobook.dart';
import 'package:audiovault_editor/widgets/chapter_editor.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Property 1: Population round-trip for single-file books
  // Validates: Requirements 1.1
  // ---------------------------------------------------------------------------
  group('Property 1: Population round-trip for single-file books', () {
    test('single chapter preserves title and start', () {
      final chapters = [
        const ChapterEntry(title: 'Intro', start: Duration.zero),
      ];
      final ctrl = ChapterEditorController(entries: List.of(chapters));
      expect(ctrl.entries.length, equals(1));
      expect(ctrl.entries[0].title, equals('Intro'));
      expect(ctrl.entries[0].start, equals(Duration.zero));
    });

    test('multiple chapters preserve all titles and starts', () {
      final chapters = [
        const ChapterEntry(title: 'Chapter 1', start: Duration.zero),
        const ChapterEntry(title: 'Chapter 2', start: Duration(minutes: 5)),
        const ChapterEntry(title: 'Chapter 3', start: Duration(minutes: 12, seconds: 30)),
      ];
      final ctrl = ChapterEditorController(entries: List.of(chapters));
      expect(ctrl.entries.length, equals(3));
      for (int i = 0; i < chapters.length; i++) {
        expect(ctrl.entries[i].title, equals(chapters[i].title));
        expect(ctrl.entries[i].start, equals(chapters[i].start));
      }
    });

    test('empty title is preserved', () {
      final chapters = [
        const ChapterEntry(title: '', start: Duration.zero),
        const ChapterEntry(title: 'Named', start: Duration(seconds: 60)),
      ];
      final ctrl = ChapterEditorController(entries: List.of(chapters));
      expect(ctrl.entries[0].title, equals(''));
      expect(ctrl.entries[1].title, equals('Named'));
    });

    test('large chapter list preserves all entries', () {
      final chapters = List.generate(
        50,
        (i) => ChapterEntry(
          title: 'Chapter ',
          start: Duration(minutes: i * 3),
        ),
      );
      final ctrl = ChapterEditorController(entries: List.of(chapters));
      expect(ctrl.entries.length, equals(50));
      for (int i = 0; i < 50; i++) {
        expect(ctrl.entries[i].title, equals(chapters[i].title));
        expect(ctrl.entries[i].start, equals(chapters[i].start));
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Property 2: Population round-trip for multi-file books
  // Validates: Requirements 1.2
  // ---------------------------------------------------------------------------
  group('Property 2: Population round-trip for multi-file books', () {
    test('n audio files produce n entries with matching titles', () {
      final chapterNames = ['File 1', 'File 2', 'File 3'];
      final entries = List.generate(
        chapterNames.length,
        (i) => ChapterEntry(title: chapterNames[i], start: Duration.zero),
      );
      final ctrl = ChapterEditorController(entries: entries);
      expect(ctrl.entries.length, equals(3));
      for (int i = 0; i < chapterNames.length; i++) {
        expect(ctrl.entries[i].title, equals(chapterNames[i]));
      }
    });

    test('single audio file produces one entry', () {
      final entries = [
        const ChapterEntry(title: 'Only File', start: Duration.zero),
      ];
      final ctrl = ChapterEditorController(entries: entries);
      expect(ctrl.entries.length, equals(1));
      expect(ctrl.entries[0].title, equals('Only File'));
    });
  });

  // ---------------------------------------------------------------------------
  // Property 3: Derived duration correctness
  // Validates: Requirements 1.4, 3.6
  // ---------------------------------------------------------------------------
  group('Property 3: Derived duration correctness', () {
    test('derived duration between entries equals start difference', () {
      final entries = [
        const ChapterEntry(title: 'A', start: Duration.zero),
        const ChapterEntry(title: 'B', start: Duration(minutes: 5)),
        const ChapterEntry(title: 'C', start: Duration(minutes: 12)),
      ];
      final ctrl = ChapterEditorController(entries: entries);
      const bookDuration = Duration(minutes: 20);

      expect(ctrl.derivedDuration(0, bookDuration), equals(const Duration(minutes: 5)));
      expect(ctrl.derivedDuration(1, bookDuration), equals(const Duration(minutes: 7)));
      expect(ctrl.derivedDuration(2, bookDuration), equals(const Duration(minutes: 8)));
    });

    test('last entry derived duration uses bookDuration', () {
      final entries = [
        const ChapterEntry(title: 'A', start: Duration.zero),
        const ChapterEntry(title: 'B', start: Duration(minutes: 10)),
      ];
      final ctrl = ChapterEditorController(entries: entries);
      const bookDuration = Duration(minutes: 30);

      expect(ctrl.derivedDuration(1, bookDuration), equals(const Duration(minutes: 20)));
    });

    test('last entry derived duration is null when bookDuration is null', () {
      final entries = [
        const ChapterEntry(title: 'A', start: Duration.zero),
        const ChapterEntry(title: 'B', start: Duration(minutes: 10)),
      ];
      final ctrl = ChapterEditorController(entries: entries);

      expect(ctrl.derivedDuration(1, null), isNull);
    });

    test('single entry derived duration uses bookDuration', () {
      final entries = [
        const ChapterEntry(title: 'Only', start: Duration.zero),
      ];
      final ctrl = ChapterEditorController(entries: entries);
      const bookDuration = Duration(hours: 1);

      expect(ctrl.derivedDuration(0, bookDuration), equals(const Duration(hours: 1)));
    });

    test('derived duration for all indices with multiple entries', () {
      final starts = [0, 300, 720, 1200, 1800]; // seconds
      final entries = starts
          .map((s) => ChapterEntry(title: 'Ch', start: Duration(seconds: s)))
          .toList();
      const bookDuration = Duration(seconds: 2400);
      final ctrl = ChapterEditorController(entries: entries);

      for (int i = 0; i < entries.length - 1; i++) {
        final expected = entries[i + 1].start - entries[i].start;
        expect(ctrl.derivedDuration(i, bookDuration), equals(expected));
      }
      expect(
        ctrl.derivedDuration(entries.length - 1, bookDuration),
        equals(bookDuration - entries.last.start),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Property 4: First chapter start is always zero
  // Validates: Requirements 3.3
  // ---------------------------------------------------------------------------
  group('Property 4: First chapter start is always zero', () {
    test('updateStart(0, ...) clamps to Duration.zero', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
        const ChapterEntry(title: 'B', start: Duration(minutes: 5)),
      ]);
      ctrl.updateStart(0, const Duration(minutes: 3));
      expect(ctrl.entries[0].start, equals(Duration.zero));
    });

    test('updateStart(0, Duration.zero) keeps Duration.zero', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
      ]);
      ctrl.updateStart(0, Duration.zero);
      expect(ctrl.entries[0].start, equals(Duration.zero));
    });

    test('updateStart(0, large duration) still clamps to zero', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
        const ChapterEntry(title: 'B', start: Duration(hours: 2)),
      ]);
      ctrl.updateStart(0, const Duration(hours: 1, minutes: 30));
      expect(ctrl.entries[0].start, equals(Duration.zero));
    });

    test('updateStart on non-zero index is not clamped', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
        const ChapterEntry(title: 'B', start: Duration(minutes: 5)),
      ]);
      ctrl.updateStart(1, const Duration(minutes: 10));
      expect(ctrl.entries[1].start, equals(const Duration(minutes: 10)));
    });
  });

  // ---------------------------------------------------------------------------
  // Property 5: Timestamp parsing canonical round-trip
  // Validates: Requirements 3.4
  // ---------------------------------------------------------------------------
  group('Property 5: Timestamp parsing canonical round-trip', () {
    test('formatTimestamp then parseTimestamp round-trips', () {
      final durations = [
        Duration.zero,
        const Duration(seconds: 30),
        const Duration(minutes: 5, seconds: 30),
        const Duration(hours: 1, minutes: 5, seconds: 30),
        const Duration(hours: 10, minutes: 59, seconds: 59),
        const Duration(hours: 99, minutes: 59, seconds: 59),
      ];
      for (final d in durations) {
        final formatted = ChapterEditorController.formatTimestamp(d);
        final parsed = ChapterEditorController.parseTimestamp(formatted);
        expect(parsed, isNotNull, reason: 'Failed to parse: ');
        expect(parsed!.inSeconds, equals(d.inSeconds),
            reason: 'Round-trip failed for  ->  -> ');
      }
    });

    test('parseTimestamp then formatTimestamp produces same total seconds', () {
      final timestamps = [
        '00:00:00',
        '00:05:30',
        '01:05:30',
        '10:30:00',
        '99:59:59',
      ];
      for (final ts in timestamps) {
        final parsed = ChapterEditorController.parseTimestamp(ts);
        expect(parsed, isNotNull, reason: 'Failed to parse: ');
        final reformatted = ChapterEditorController.formatTimestamp(parsed!);
        final reparsed = ChapterEditorController.parseTimestamp(reformatted);
        expect(reparsed!.inSeconds, equals(parsed.inSeconds),
            reason: 'Round-trip failed for ');
      }
    });

    test('MM:SS format parses correctly', () {
      expect(ChapterEditorController.parseTimestamp('5:30'),
          equals(const Duration(minutes: 5, seconds: 30)));
      expect(ChapterEditorController.parseTimestamp('0:00'), equals(Duration.zero));
      expect(ChapterEditorController.parseTimestamp('99:59'),
          equals(const Duration(minutes: 99, seconds: 59)));
    });

    test('MMM:SS format (minutes > 99) parses correctly', () {
      expect(ChapterEditorController.parseTimestamp('125:30'),
          equals(const Duration(minutes: 125, seconds: 30)));
      expect(ChapterEditorController.parseTimestamp('100:00'),
          equals(const Duration(minutes: 100)));
    });

    test('HH:MM:SS format parses correctly', () {
      expect(ChapterEditorController.parseTimestamp('1:05:30'),
          equals(const Duration(hours: 1, minutes: 5, seconds: 30)));
      expect(ChapterEditorController.parseTimestamp('01:05:30'),
          equals(const Duration(hours: 1, minutes: 5, seconds: 30)));
      expect(ChapterEditorController.parseTimestamp('00:00:00'), equals(Duration.zero));
    });

    test('invalid timestamps return null', () {
      expect(ChapterEditorController.parseTimestamp('invalid'), isNull);
      expect(ChapterEditorController.parseTimestamp(''), isNull);
      expect(ChapterEditorController.parseTimestamp('abc:def'), isNull);
      expect(ChapterEditorController.parseTimestamp('1:2:3:4'), isNull);
    });

    test('seconds out of range returns null', () {
      expect(ChapterEditorController.parseTimestamp('5:60'), isNull);
      expect(ChapterEditorController.parseTimestamp('1:00:60'), isNull);
      // 60:00 is valid: 60 minutes, 0 seconds
      expect(ChapterEditorController.parseTimestamp('60:00'), equals(const Duration(minutes: 60)));
    });

    test('formatTimestamp always produces HH:MM:SS', () {
      expect(ChapterEditorController.formatTimestamp(Duration.zero), equals('00:00:00'));
      expect(ChapterEditorController.formatTimestamp(const Duration(hours: 1, minutes: 5, seconds: 30)),
          equals('01:05:30'));
      expect(ChapterEditorController.formatTimestamp(const Duration(minutes: 5, seconds: 30)),
          equals('00:05:30'));
    });
  });

  // ---------------------------------------------------------------------------
  // Property 6: Conflict detection matches strictly-ascending invariant
  // Validates: Requirements 4.1, 4.2, 4.3
  // ---------------------------------------------------------------------------
  group('Property 6: Conflict detection', () {
    test('no conflicts when starts are strictly ascending', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
        const ChapterEntry(title: 'B', start: Duration(minutes: 5)),
        const ChapterEntry(title: 'C', start: Duration(minutes: 10)),
      ]);
      expect(ctrl.hasConflicts, isFalse);
    });

    test('conflict when two entries have same start', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
        const ChapterEntry(title: 'B', start: Duration(minutes: 5)),
        const ChapterEntry(title: 'C', start: Duration(minutes: 5)),
      ]);
      expect(ctrl.hasConflicts, isTrue);
    });

    test('conflict when entry start is greater than next', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
        const ChapterEntry(title: 'B', start: Duration(minutes: 10)),
        const ChapterEntry(title: 'C', start: Duration(minutes: 5)),
      ]);
      expect(ctrl.hasConflicts, isTrue);
    });

    test('single entry has no conflicts', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
      ]);
      expect(ctrl.hasConflicts, isFalse);
    });

    test('empty list has no conflicts', () {
      final ctrl = ChapterEditorController(entries: []);
      expect(ctrl.hasConflicts, isFalse);
    });

    test('hasConflicts iff any entries[i].start >= entries[i+1].start', () {
      final configs = [
        [0, 1, 2, 3],
        [0, 5, 3, 10],
        [0, 0, 5, 10],
        [0, 5, 10, 10],
      ];
      final expected = [false, true, true, true];

      for (int c = 0; c < configs.length; c++) {
        final entries = configs[c]
            .map((s) => ChapterEntry(title: 'Ch', start: Duration(minutes: s)))
            .toList();
        final ctrl = ChapterEditorController(entries: entries);
        expect(ctrl.hasConflicts, equals(expected[c]),
            reason: 'Config  should have conflicts=');
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Property 7: addChapter places new row at correct start time
  // Validates: Requirements 5.2
  // ---------------------------------------------------------------------------
  group('Property 7: addChapter places new row at correct start', () {
    test('addChapter appends at last start + derived duration', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
        const ChapterEntry(title: 'B', start: Duration(minutes: 10)),
      ]);
      const bookDuration = Duration(minutes: 30);
      ctrl.addChapter(bookDuration);
      expect(ctrl.entries.length, equals(3));
      expect(ctrl.entries[2].start, equals(const Duration(minutes: 30)));
    });

    test('addChapter on empty list creates entry at Duration.zero', () {
      final ctrl = ChapterEditorController(entries: []);
      ctrl.addChapter(null);
      expect(ctrl.entries.length, equals(1));
      expect(ctrl.entries[0].start, equals(Duration.zero));
    });

    test('addChapter with null bookDuration uses last start when no next entry', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
        const ChapterEntry(title: 'B', start: Duration(minutes: 10)),
      ]);
      ctrl.addChapter(null);
      expect(ctrl.entries.length, equals(3));
      expect(ctrl.entries[2].start, equals(const Duration(minutes: 10)));
    });

    test('addChapter new entry has empty title', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
      ]);
      ctrl.addChapter(const Duration(hours: 1));
      expect(ctrl.entries.last.title, equals(''));
    });
  });

  // ---------------------------------------------------------------------------
  // Property 8: insertChapter places new row at midpoint
  // Validates: Requirements 6.2
  // ---------------------------------------------------------------------------
  group('Property 8: insertChapter places new row at midpoint', () {
    test('inserted entry start is midpoint of surrounding entries', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
        const ChapterEntry(title: 'B', start: Duration(minutes: 10)),
      ]);
      ctrl.insertChapter(0);
      expect(ctrl.entries.length, equals(3));
      expect(ctrl.entries[1].start, equals(const Duration(minutes: 5)));
    });

    test('midpoint uses integer division of microseconds', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration()),
        const ChapterEntry(title: 'B', start: Duration(microseconds: 11)),
      ]);
      ctrl.insertChapter(0);
      expect(ctrl.entries[1].start, equals(const Duration(microseconds: 5)));
    });

    test('insertChapter between second and third entries', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
        const ChapterEntry(title: 'B', start: Duration(minutes: 10)),
        const ChapterEntry(title: 'C', start: Duration(minutes: 20)),
      ]);
      ctrl.insertChapter(1);
      expect(ctrl.entries.length, equals(4));
      expect(ctrl.entries[2].start, equals(const Duration(minutes: 15)));
    });

    test('inserted entry has empty title', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
        const ChapterEntry(title: 'B', start: Duration(minutes: 10)),
      ]);
      ctrl.insertChapter(0);
      expect(ctrl.entries[1].title, equals(''));
    });
  });

  // ---------------------------------------------------------------------------
  // Property 9: Row indices are always sequential after any mutation
  // Validates: Requirements 6.3, 7.2
  // ---------------------------------------------------------------------------
  group('Property 9: Sequential indices after mutations', () {
    test('indices are 0..n-1 after add', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
      ]);
      ctrl.addChapter(const Duration(hours: 1));
      for (int i = 0; i < ctrl.entries.length; i++) {
        expect(ctrl.entries[i], isNotNull);
      }
      expect(ctrl.entries.length, equals(2));
    });

    test('indices are 0..n-1 after insert', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
        const ChapterEntry(title: 'B', start: Duration(minutes: 10)),
      ]);
      ctrl.insertChapter(0);
      expect(ctrl.entries.length, equals(3));
      for (int i = 0; i < ctrl.entries.length; i++) {
        expect(ctrl.entries[i], isNotNull);
      }
    });

    test('indices are 0..n-1 after delete', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
        const ChapterEntry(title: 'B', start: Duration(minutes: 5)),
        const ChapterEntry(title: 'C', start: Duration(minutes: 10)),
      ]);
      ctrl.deleteChapter(1);
      expect(ctrl.entries.length, equals(2));
      for (int i = 0; i < ctrl.entries.length; i++) {
        expect(ctrl.entries[i], isNotNull);
      }
    });

    test('indices sequential after multiple mutations', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
        const ChapterEntry(title: 'B', start: Duration(minutes: 10)),
        const ChapterEntry(title: 'C', start: Duration(minutes: 20)),
      ]);
      ctrl.addChapter(const Duration(minutes: 40));
      ctrl.insertChapter(1);
      ctrl.deleteChapter(2);
      expect(ctrl.entries.length, equals(4));
      for (int i = 0; i < ctrl.entries.length; i++) {
        expect(ctrl.entries[i], isNotNull);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Property 10: deleteChapter reduces count by 1 (when n > 1)
  // Validates: Requirements 7.2
  // ---------------------------------------------------------------------------
  group('Property 10: deleteChapter reduces count by 1', () {
    test('delete middle entry reduces count and preserves order', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
        const ChapterEntry(title: 'B', start: Duration(minutes: 5)),
        const ChapterEntry(title: 'C', start: Duration(minutes: 10)),
      ]);
      ctrl.deleteChapter(1);
      expect(ctrl.entries.length, equals(2));
      expect(ctrl.entries[0].title, equals('A'));
      expect(ctrl.entries[1].title, equals('C'));
    });

    test('delete first entry reduces count and preserves order', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
        const ChapterEntry(title: 'B', start: Duration(minutes: 5)),
        const ChapterEntry(title: 'C', start: Duration(minutes: 10)),
      ]);
      ctrl.deleteChapter(0);
      expect(ctrl.entries.length, equals(2));
      expect(ctrl.entries[0].title, equals('B'));
      expect(ctrl.entries[1].title, equals('C'));
    });

    test('delete last entry reduces count and preserves order', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
        const ChapterEntry(title: 'B', start: Duration(minutes: 5)),
        const ChapterEntry(title: 'C', start: Duration(minutes: 10)),
      ]);
      ctrl.deleteChapter(2);
      expect(ctrl.entries.length, equals(2));
      expect(ctrl.entries[0].title, equals('A'));
      expect(ctrl.entries[1].title, equals('B'));
    });

    test('deleteChapter on single-entry list is a no-op', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'Only', start: Duration.zero),
      ]);
      ctrl.deleteChapter(0);
      expect(ctrl.entries.length, equals(1));
      expect(ctrl.entries[0].title, equals('Only'));
    });
  });

  // ---------------------------------------------------------------------------
  // Property 11: Quick Edit serialisation round-trip
  // Validates: Requirements 8.2, 8.3, 8.7, 9.1, 9.2
  // ---------------------------------------------------------------------------
  group('Property 11: Quick Edit serialisation round-trip', () {
    test('round-trip with timestamps preserves titles and starts', () {
      final entries = [
        const ChapterEntry(title: 'Intro', start: Duration.zero),
        const ChapterEntry(title: 'Chapter 1', start: Duration(minutes: 5)),
        const ChapterEntry(title: 'Chapter 2', start: Duration(minutes: 12, seconds: 30)),
      ];
      final ctrl = ChapterEditorController(entries: entries);
      final text = ctrl.toQuickEditText(true);
      final result = ChapterEditorController.parseQuickEditText(text, true);
      expect(result.errorLines, isEmpty);
      expect(result.entries.length, equals(3));
      for (int i = 0; i < entries.length; i++) {
        expect(result.entries[i].title, equals(entries[i].title));
        expect(result.entries[i].start.inSeconds, equals(entries[i].start.inSeconds));
      }
    });

    test('round-trip without timestamps preserves titles', () {
      final entries = [
        const ChapterEntry(title: 'Intro', start: Duration.zero),
        const ChapterEntry(title: 'Chapter 1', start: Duration(minutes: 5)),
      ];
      final ctrl = ChapterEditorController(entries: entries);
      final text = ctrl.toQuickEditText(false);
      final result = ChapterEditorController.parseQuickEditText(text, false);
      expect(result.errorLines, isEmpty);
      expect(result.entries.length, equals(2));
      expect(result.entries[0].title, equals('Intro'));
      expect(result.entries[1].title, equals('Chapter 1'));
    });

    test('empty entries produce empty text and parse back to empty', () {
      final ctrl = ChapterEditorController(entries: []);
      final text = ctrl.toQuickEditText(true);
      final result = ChapterEditorController.parseQuickEditText(text, true);
      expect(result.entries, isEmpty);
      expect(result.errorLines, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Property 12: Quick Edit rightmost-comma parsing
  // Validates: Requirements 8.4
  // ---------------------------------------------------------------------------
  group('Property 12: Quick Edit rightmost-comma parsing', () {
    test('title with comma survives round-trip', () {
      final entries = [
        const ChapterEntry(title: 'Hello, World', start: Duration(minutes: 5)),
      ];
      final ctrl = ChapterEditorController(entries: entries);
      final text = ctrl.toQuickEditText(true);
      final result = ChapterEditorController.parseQuickEditText(text, true);
      expect(result.errorLines, isEmpty);
      expect(result.entries[0].title, equals('Hello, World'));
      expect(result.entries[0].start.inSeconds, equals(const Duration(minutes: 5).inSeconds));
    });

    test('title with multiple commas survives round-trip', () {
      final entries = [
        const ChapterEntry(title: 'One, Two, Three', start: Duration(minutes: 10)),
      ];
      final ctrl = ChapterEditorController(entries: entries);
      final text = ctrl.toQuickEditText(true);
      final result = ChapterEditorController.parseQuickEditText(text, true);
      expect(result.errorLines, isEmpty);
      expect(result.entries[0].title, equals('One, Two, Three'));
    });

    test('rightmost comma is used as separator', () {
      const line = '"Title, with comma", 00:05:00';
      final result = ChapterEditorController.parseQuickEditText(line, true);
      expect(result.errorLines, isEmpty);
      expect(result.entries[0].title, equals('Title, with comma'));
      expect(result.entries[0].start, equals(const Duration(minutes: 5)));
    });

    test('quoted title without comma also works', () {
      const line = '"Simple Title", 00:01:00';
      final result = ChapterEditorController.parseQuickEditText(line, true);
      expect(result.errorLines, isEmpty);
      expect(result.entries[0].title, equals('Simple Title'));
    });
  });

  // ---------------------------------------------------------------------------
  // Property 13: Quick Edit error lines identify exactly the invalid lines
  // Validates: Requirements 8.5
  // ---------------------------------------------------------------------------
  group('Property 13: Quick Edit error lines', () {
    test('malformed timestamp line is in errorLines', () {
      const text = 'Good Chapter, 00:05:00\nBad Line, notatime\nAnother Good, 00:10:00';
      final result = ChapterEditorController.parseQuickEditText(text, true);
      expect(result.errorLines, equals([1]));
      expect(result.entries.length, equals(3));
    });

    test('multiple malformed lines are all in errorLines', () {
      const text = 'Good, 00:01:00\nBad1, xyz\nBad2, abc\nGood2, 00:05:00';
      final result = ChapterEditorController.parseQuickEditText(text, true);
      expect(result.errorLines, containsAll([1, 2]));
      expect(result.errorLines.length, equals(2));
    });

    test('no malformed lines means empty errorLines', () {
      const text = 'Chapter 1, 00:00:00\nChapter 2, 00:05:00';
      final result = ChapterEditorController.parseQuickEditText(text, true);
      expect(result.errorLines, isEmpty);
    });

    test('line without comma when timestamps expected is an error', () {
      const text = 'No comma here\nGood, 00:05:00';
      final result = ChapterEditorController.parseQuickEditText(text, true);
      expect(result.errorLines, contains(0));
    });

    test('blank lines produce placeholder entries and do not affect line indices', () {
      const text = 'Good, 00:01:00\n\nBad, notatime\nGood2, 00:05:00';
      final result = ChapterEditorController.parseQuickEditText(text, true);
      expect(result.errorLines, contains(2));
      // blank line at index 1 produces a placeholder entry → 4 entries total
      expect(result.entries.length, equals(4));
      expect(result.entries[1].title, equals(''));
      expect(result.entries[1].start, equals(Duration.zero));
    });
  });

  // ---------------------------------------------------------------------------
  // Property 16: Undo/redo stack discipline
  // Validates: Requirements 11.2, 11.4, 11.5
  // ---------------------------------------------------------------------------
  group('Property 16: Undo/redo stack discipline', () {
    test('undo after one mutation restores previous state', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
      ]);
      ctrl.addChapter(const Duration(hours: 1));
      expect(ctrl.entries.length, equals(2));
      ctrl.undo();
      expect(ctrl.entries.length, equals(1));
      expect(ctrl.entries[0].title, equals('A'));
    });

    test('redo after undo restores post-mutation state', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
      ]);
      ctrl.addChapter(const Duration(hours: 1));
      ctrl.undo();
      ctrl.redo();
      expect(ctrl.entries.length, equals(2));
    });

    test('k undos after k mutations restores pre-mutation state', () {
      final initial = [
        const ChapterEntry(title: 'A', start: Duration.zero),
        const ChapterEntry(title: 'B', start: Duration(minutes: 10)),
      ];
      final ctrl = ChapterEditorController(entries: List.of(initial));

      ctrl.updateTitle(0, 'A modified');
      ctrl.updateTitle(1, 'B modified');
      ctrl.addChapter(const Duration(hours: 1));

      ctrl.undo();
      ctrl.undo();
      ctrl.undo();

      expect(ctrl.entries.length, equals(2));
      expect(ctrl.entries[0].title, equals('A'));
      expect(ctrl.entries[1].title, equals('B'));
    });

    test('k redos after k undos restores post-mutation state', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
      ]);
      ctrl.updateTitle(0, 'Modified');
      ctrl.addChapter(const Duration(hours: 1));

      ctrl.undo();
      ctrl.undo();

      ctrl.redo();
      ctrl.redo();

      expect(ctrl.entries.length, equals(2));
      expect(ctrl.entries[0].title, equals('Modified'));
    });

    test('undo when stack is empty is a no-op', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
      ]);
      expect(ctrl.canUndo, isFalse);
      ctrl.undo();
      expect(ctrl.entries.length, equals(1));
    });

    test('redo when stack is empty is a no-op', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
      ]);
      expect(ctrl.canRedo, isFalse);
      ctrl.redo();
      expect(ctrl.entries.length, equals(1));
    });

    test('mutation after undo clears redo stack', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
      ]);
      ctrl.addChapter(const Duration(hours: 1));
      ctrl.undo();
      expect(ctrl.canRedo, isTrue);
      ctrl.updateTitle(0, 'Changed');
      expect(ctrl.canRedo, isFalse);
    });

    test('canUndo and canRedo reflect stack state', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
      ]);
      expect(ctrl.canUndo, isFalse);
      expect(ctrl.canRedo, isFalse);

      ctrl.addChapter(const Duration(hours: 1));
      expect(ctrl.canUndo, isTrue);
      expect(ctrl.canRedo, isFalse);

      ctrl.undo();
      expect(ctrl.canUndo, isFalse);
      expect(ctrl.canRedo, isTrue);

      ctrl.redo();
      expect(ctrl.canUndo, isTrue);
      expect(ctrl.canRedo, isFalse);
    });

    test('clearHistory empties both stacks', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
      ]);
      ctrl.addChapter(const Duration(hours: 1));
      ctrl.undo();
      expect(ctrl.canUndo, isFalse);
      expect(ctrl.canRedo, isTrue);
      ctrl.clearHistory();
      expect(ctrl.canUndo, isFalse);
      expect(ctrl.canRedo, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Edge cases
  // ---------------------------------------------------------------------------
  group('Edge cases', () {
    test('deleteChapter on single-entry list is a no-op', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'Only', start: Duration.zero),
      ]);
      ctrl.deleteChapter(0);
      expect(ctrl.entries.length, equals(1));
      expect(ctrl.entries[0].title, equals('Only'));
    });

    test('undo when stack is empty is a no-op', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
      ]);
      ctrl.undo();
      expect(ctrl.entries.length, equals(1));
    });

    test('redo when stack is empty is a no-op', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
      ]);
      ctrl.redo();
      expect(ctrl.entries.length, equals(1));
    });

    test('parseTimestamp("invalid") returns null', () {
      expect(ChapterEditorController.parseTimestamp('invalid'), isNull);
    });

    test('parseTimestamp("60:00") returns Duration(minutes: 60) - 60 min 0 sec is valid', () {
      expect(ChapterEditorController.parseTimestamp('60:00'), equals(const Duration(minutes: 60)));
    });

    test('parseTimestamp("5:30") returns Duration(minutes: 5, seconds: 30)', () {
      expect(
        ChapterEditorController.parseTimestamp('5:30'),
        equals(const Duration(minutes: 5, seconds: 30)),
      );
    });

    test('parseTimestamp("125:30") returns Duration(minutes: 125, seconds: 30)', () {
      expect(
        ChapterEditorController.parseTimestamp('125:30'),
        equals(const Duration(minutes: 125, seconds: 30)),
      );
    });

    test('parseTimestamp("1:05:30") returns Duration(hours: 1, minutes: 5, seconds: 30)', () {
      expect(
        ChapterEditorController.parseTimestamp('1:05:30'),
        equals(const Duration(hours: 1, minutes: 5, seconds: 30)),
      );
    });

    test('replaceAll replaces entire list', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'Old', start: Duration.zero),
      ]);
      final newEntries = [
        const ChapterEntry(title: 'New 1', start: Duration.zero),
        const ChapterEntry(title: 'New 2', start: Duration(minutes: 5)),
      ];
      ctrl.replaceAll(newEntries);
      expect(ctrl.entries.length, equals(2));
      expect(ctrl.entries[0].title, equals('New 1'));
      expect(ctrl.entries[1].title, equals('New 2'));
    });

    test('ChapterEntry copyWith works correctly', () {
      const entry = ChapterEntry(title: 'Original', start: Duration.zero);
      final copy = entry.copyWith(title: 'Modified');
      expect(copy.title, equals('Modified'));
      expect(copy.start, equals(Duration.zero));

      final copy2 = entry.copyWith(start: const Duration(minutes: 5));
      expect(copy2.title, equals('Original'));
      expect(copy2.start, equals(const Duration(minutes: 5)));
    });

    test('undo stack is capped at 100', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
        const ChapterEntry(title: 'B', start: Duration(minutes: 10)),
      ]);
      for (int i = 0; i < 110; i++) {
        ctrl.updateTitle(0, 'Title $i');
      }
      int undoCount = 0;
      while (ctrl.canUndo) {
        ctrl.undo();
        undoCount++;
      }
      expect(undoCount, equals(100));
    });
  });

  // ---------------------------------------------------------------------------
  // Widget tests — Task 3.1: Toolbar and column visibility
  // Requirements: 3.1, 3.2, 10.1, 10.7
  // ---------------------------------------------------------------------------

  /// Helper: builds a minimal single-file M4B Audiobook.
  Audiobook makeSingleFileM4bBook({List<Chapter> chapters = const []}) {
    return Audiobook(
      path: '/books/test',
      audioFiles: ['/books/test/book.m4b'],
      chapters: chapters,
      duration: const Duration(hours: 1),
    );
  }

  /// Helper: builds a minimal single-file MP3 Audiobook.
  Audiobook makeSingleFileMp3Book({List<Chapter> chapters = const []}) {
    return Audiobook(
      path: '/books/test',
      audioFiles: ['/books/test/book.mp3'],
      chapters: chapters,
      duration: const Duration(hours: 1),
    );
  }

  /// Helper: builds a minimal multi-file Audiobook.
  Audiobook makeMultiFileBook() {
    return const Audiobook(
      path: '/books/test',
      audioFiles: [
        '/books/test/part1.mp3',
        '/books/test/part2.mp3',
      ],
      chapterNames: ['Part 1', 'Part 2'],
      chapterDurations: [
        Duration(minutes: 30),
        Duration(minutes: 30),
      ],
    );
  }

  group('Widget test 3.1: Toolbar and column visibility', () {
    testWidgets('toolbar contains Undo, Redo, Quick Edit buttons',
        (tester) async {
      final book = makeSingleFileM4bBook(chapters: [
        const Chapter(title: 'Intro', start: Duration.zero),
      ]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChapterEditor(
            book: book,
            onChanged: (_) {},
          ),
        ),
      ));

      expect(find.byTooltip('Undo'), findsOneWidget);
      expect(find.byTooltip('Redo'), findsOneWidget);
      expect(find.text('Quick Edit'), findsOneWidget);
    });

    testWidgets('Export CUE button absent for M4B single-file book',
        (tester) async {
      final book = makeSingleFileM4bBook(chapters: [
        const Chapter(title: 'Intro', start: Duration.zero),
      ]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChapterEditor(
            book: book,
            onChanged: (_) {},
          ),
        ),
      ));

      expect(find.text('Export CUE'), findsNothing);
    });

    testWidgets('Export CUE button absent for multi-file book',
        (tester) async {
      final book = makeMultiFileBook();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChapterEditor(
            book: book,
            onChanged: (_) {},
          ),
        ),
      ));

      expect(find.text('Export CUE'), findsNothing);
    });

    testWidgets('Start time column header present for single-file book',
        (tester) async {
      final book = makeSingleFileM4bBook(chapters: [
        const Chapter(title: 'Intro', start: Duration.zero),
      ]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChapterEditor(
            book: book,
            onChanged: (_) {},
          ),
        ),
      ));

      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('Start time column header absent for multi-file book',
        (tester) async {
      final book = makeMultiFileBook();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChapterEditor(
            book: book,
            onChanged: (_) {},
          ),
        ),
      ));

      expect(find.text('Start'), findsNothing);
    });

    testWidgets('File column header present for multi-file book',
        (tester) async {
      final book = makeMultiFileBook();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChapterEditor(
            book: book,
            onChanged: (_) {},
          ),
        ),
      ));

      expect(find.text('File'), findsOneWidget);
    });

    testWidgets('File column header absent for single-file book',
        (tester) async {
      final book = makeSingleFileM4bBook(chapters: [
        const Chapter(title: 'Intro', start: Duration.zero),
      ]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChapterEditor(
            book: book,
            onChanged: (_) {},
          ),
        ),
      ));

      expect(find.text('File'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Widget tests — Task 3.2: Row interactions
  // Requirements: 3.3, 3.5, 4.4, 7.3
  // ---------------------------------------------------------------------------
  group('Widget test 3.2: Row interactions', () {
    testWidgets('delete button disabled on the only remaining row',
        (tester) async {
      final book = makeSingleFileM4bBook(chapters: [
        const Chapter(title: 'Only Chapter', start: Duration.zero),
      ]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChapterEditor(
            book: book,
            onChanged: (_) {},
          ),
        ),
      ));

      // The delete button should be visible (since it's the only row) but disabled
      final closeButtons = find.byIcon(Icons.close);
      expect(closeButtons, findsOneWidget);
      final iconButton = tester.widget<IconButton>(
        find.ancestor(
          of: closeButtons,
          matching: find.byType(IconButton),
        ),
      );
      expect(iconButton.onPressed, isNull);
    });

    testWidgets('delete button tooltip says at least one chapter required',
        (tester) async {
      final book = makeSingleFileM4bBook(chapters: [
        const Chapter(title: 'Only Chapter', start: Duration.zero),
      ]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChapterEditor(
            book: book,
            onChanged: (_) {},
          ),
        ),
      ));

      expect(
        find.byTooltip('At least one chapter is required'),
        findsOneWidget,
      );
    });

    testWidgets('first row start time field is read-only (shows text, not TextField)',
        (tester) async {
      final book = makeSingleFileM4bBook(chapters: [
        const Chapter(title: 'Intro', start: Duration.zero),
        const Chapter(title: 'Chapter 1', start: Duration(minutes: 5)),
      ]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChapterEditor(
            book: book,
            onChanged: (_) {},
          ),
        ),
      ));

      // Row 0 start time is shown as plain text '00:00:00', not a TextField
      expect(find.text('00:00:00'), findsOneWidget);
      // Row 1 has an editable TextField for start time
      // There should be exactly 2 TextFields: one for each title + one for row 1 start
      // (row 0 start is read-only text)
      final textFields = tester.widgetList<TextField>(find.byType(TextField));
      // 2 title fields + 1 start field for row 1 = 3 total
      expect(textFields.length, equals(3));
    });

    testWidgets('inline timestamp error appears after blur, not during typing',
        (tester) async {
      final book = makeSingleFileM4bBook(chapters: [
        const Chapter(title: 'Intro', start: Duration.zero),
        const Chapter(title: 'Chapter 1', start: Duration(minutes: 5)),
      ]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChapterEditor(
            book: book,
            onChanged: (_) {},
          ),
        ),
      ));

      // Find the start time TextField for row 1 (index 1)
      // It should be the last TextField (after the 2 title fields)
      final textFields = find.byType(TextField);
      final startField = textFields.last;

      // Tap to focus
      await tester.tap(startField);
      await tester.pump();

      // Type invalid text
      await tester.enterText(startField, 'notavalidtime');
      await tester.pump();

      // Error should NOT appear while typing
      expect(find.text('Invalid format (e.g. 1:05:30)'), findsNothing);

      // Unfocus by tapping the first title field
      await tester.tap(textFields.first);
      await tester.pump();

      // Error should appear after blur
      expect(find.text('Invalid format (e.g. 1:05:30)'), findsOneWidget);
    });

    testWidgets('add chapter button is present below the list', (tester) async {
      final book = makeSingleFileM4bBook(chapters: [
        const Chapter(title: 'Intro', start: Duration.zero),
      ]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChapterEditor(
            book: book,
            onChanged: (_) {},
          ),
        ),
      ));

      expect(find.text('Add chapter'), findsOneWidget);
    });

    testWidgets('add chapter button adds a new row', (tester) async {
      final book = makeSingleFileM4bBook(chapters: [
        const Chapter(title: 'Intro', start: Duration.zero),
      ]);
      List<ChapterEntry>? lastChapters;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChapterEditor(
            book: book,
            onChanged: (chapters) => lastChapters = chapters,
          ),
        ),
      ));

      await tester.tap(find.text('Add chapter'));
      await tester.pump();

      expect(lastChapters, isNotNull);
      expect(lastChapters!.length, equals(2));
    });

    testWidgets('conflict banner shown when timestamps conflict', (tester) async {
      final book = makeSingleFileM4bBook(chapters: [
        const Chapter(title: 'A', start: Duration.zero),
        const Chapter(title: 'B', start: Duration(minutes: 5)),
      ]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChapterEditor(
            book: book,
            onChanged: (_) {},
          ),
        ),
      ));

      // No conflict initially
      expect(
        find.text('Fix timestamp conflicts before applying'),
        findsNothing,
      );
    });

    testWidgets('MP3 single-file book shows same toolbar as M4B', (tester) async {
      final book = makeSingleFileMp3Book(chapters: [
        const Chapter(title: 'Intro', start: Duration.zero),
      ]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChapterEditor(
            book: book,
            onChanged: (_) {},
          ),
        ),
      ));

      expect(find.byTooltip('Undo'), findsOneWidget);
      expect(find.byTooltip('Redo'), findsOneWidget);
      expect(find.text('Quick Edit'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Widget tests — Task 4.1: QuickEditDialog
  // Requirements: 8.1, 8.2, 8.8, 8.9, 9.1
  // ---------------------------------------------------------------------------
  group('Widget test 4.1: QuickEditDialog', () {
    testWidgets('dialog opens pre-populated with current chapter text',
        (tester) async {
      final book = makeSingleFileM4bBook(chapters: [
        const Chapter(title: 'Intro', start: Duration.zero),
        const Chapter(title: 'Chapter 1', start: Duration(minutes: 5)),
      ]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChapterEditor(
            book: book,
            onChanged: (_) {},
          ),
        ),
      ));

      // Open the Quick Edit dialog
      await tester.tap(find.text('Quick Edit'));
      await tester.pumpAndSettle();

      // Dialog should be open
      expect(find.text('Quick Edit'), findsWidgets);

      // The text field should contain the serialised chapter list
      final textField = find.byType(TextField).last;
      final widget = tester.widget<TextField>(textField);
      final text = widget.controller?.text ?? '';
      expect(text, contains('Intro'));
      expect(text, contains('Chapter 1'));
      expect(text, contains('00:00:00'));
      expect(text, contains('00:05:00'));
    });

    testWidgets('Save button is enabled when text is valid', (tester) async {
      final book = makeSingleFileM4bBook(chapters: [
        const Chapter(title: 'Intro', start: Duration.zero),
      ]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChapterEditor(
            book: book,
            onChanged: (_) {},
          ),
        ),
      ));

      await tester.tap(find.text('Quick Edit'));
      await tester.pumpAndSettle();

      // Save button should be enabled (valid initial text)
      final saveButton = find.widgetWithText(FilledButton, 'Save');
      expect(saveButton, findsOneWidget);
      final btn = tester.widget<FilledButton>(saveButton);
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('Save button is disabled when parse errors exist',
        (tester) async {
      final book = makeSingleFileM4bBook(chapters: [
        const Chapter(title: 'Intro', start: Duration.zero),
      ]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChapterEditor(
            book: book,
            onChanged: (_) {},
          ),
        ),
      ));

      await tester.tap(find.text('Quick Edit'));
      await tester.pumpAndSettle();

      // Enter invalid text
      final textField = find.byType(TextField).last;
      await tester.enterText(textField, 'Bad line, notavalidtime');
      // Wait for debounce
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      // Save button should be disabled
      final saveButton = find.widgetWithText(FilledButton, 'Save');
      expect(saveButton, findsOneWidget);
      final btn = tester.widget<FilledButton>(saveButton);
      expect(btn.onPressed, isNull);
    });

    testWidgets('error count is shown when parse errors exist', (tester) async {
      final book = makeSingleFileM4bBook(chapters: [
        const Chapter(title: 'Intro', start: Duration.zero),
      ]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChapterEditor(
            book: book,
            onChanged: (_) {},
          ),
        ),
      ));

      await tester.tap(find.text('Quick Edit'));
      await tester.pumpAndSettle();

      // Enter two invalid lines
      final textField = find.byType(TextField).last;
      await tester.enterText(
          textField, 'Bad1, notavalidtime\nBad2, alsonotvalid');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      // Error count text should be shown
      expect(find.text('2 errors'), findsOneWidget);
    });

    testWidgets('Cancel closes dialog without calling onSave', (tester) async {
      final book = makeSingleFileM4bBook(chapters: [
        const Chapter(title: 'Intro', start: Duration.zero),
      ]);
      bool saveCalled = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChapterEditor(
            book: book,
            onChanged: (_) {},
          ),
        ),
      ));

      await tester.tap(find.text('Quick Edit'));
      await tester.pumpAndSettle();

      // Modify the text
      final textField = find.byType(TextField).last;
      await tester.enterText(textField, 'New Chapter, 00:00:00');
      await tester.pump(const Duration(milliseconds: 400));

      // Tap Cancel
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      // Dialog should be closed
      expect(find.text('Save'), findsNothing);
      expect(saveCalled, isFalse);
    });

    testWidgets('Save calls onSave and closes dialog when valid', (tester) async {
      final book = makeSingleFileM4bBook(chapters: [
        const Chapter(title: 'Intro', start: Duration.zero),
      ]);
      List<ChapterEntry>? savedEntries;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChapterEditor(
            book: book,
            onChanged: (chapters) => savedEntries = chapters,
          ),
        ),
      ));

      await tester.tap(find.text('Quick Edit'));
      await tester.pumpAndSettle();

      // Enter valid text with two chapters
      final textField = find.byType(TextField).last;
      await tester.enterText(
          textField, 'Intro, 00:00:00\nChapter 1, 00:05:00');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      // Tap Save
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      // Dialog should be closed
      expect(find.text('Save'), findsNothing);

      // onChanged should have been called with the new entries
      expect(savedEntries, isNotNull);
      expect(savedEntries!.length, equals(2));
      expect(savedEntries![0].title, equals('Intro'));
      expect(savedEntries![1].title, equals('Chapter 1'));
    });

    testWidgets('hint text shows timestamp format for single-file book',
        (tester) async {
      final book = makeSingleFileM4bBook(chapters: [
        const Chapter(title: 'Intro', start: Duration.zero),
      ]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChapterEditor(
            book: book,
            onChanged: (_) {},
          ),
        ),
      ));

      await tester.tap(find.text('Quick Edit'));
      await tester.pumpAndSettle();

      expect(
        find.text(
            'One chapter per line: Title, HH:MM:SS  (blank lines = placeholder rows)'),
        findsOneWidget,
      );
    });

    testWidgets('hint text shows title-only format for multi-file book',
        (tester) async {
      final book = makeMultiFileBook();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChapterEditor(
            book: book,
            onChanged: (_) {},
          ),
        ),
      ));

      await tester.tap(find.text('Quick Edit'));
      await tester.pumpAndSettle();

      expect(
        find.text(
            'One chapter per line: Title  (blank lines = placeholder rows)'),
        findsOneWidget,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Blank-line / placeholder behaviour
  // ---------------------------------------------------------------------------
  group('Blank-line placeholder behaviour', () {
    test('parseQuickEditText: blank line produces placeholder entry', () {
      const text = 'Chapter 1, 00:00:00\n\nChapter 3, 00:10:00';
      final result =
          ChapterEditorController.parseQuickEditText(text, true);
      expect(result.errorLines, isEmpty);
      expect(result.entries.length, equals(3));
      expect(result.entries[1].title, equals(''));
      expect(result.entries[1].start, equals(Duration.zero));
    });

    test('parseQuickEditText: blank line without timestamps produces placeholder', () {
      const text = 'Chapter 1\n\nChapter 3';
      final result =
          ChapterEditorController.parseQuickEditText(text, false);
      expect(result.errorLines, isEmpty);
      expect(result.entries.length, equals(3));
      expect(result.entries[1].title, equals(''));
      expect(result.entries[1].start, equals(Duration.zero));
    });

    test('toQuickEditText: placeholder entry produces blank line', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'Chapter 1', start: Duration.zero),
        const ChapterEntry(title: '', start: Duration.zero),
        const ChapterEntry(title: 'Chapter 3', start: Duration(minutes: 10)),
      ]);
      final text = ctrl.toQuickEditText(true);
      final lines = text.split('\n');
      expect(lines.length, equals(3));
      expect(lines[1], equals(''));
    });

    test('toQuickEditText without timestamps: placeholder entry produces blank line', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'Chapter 1', start: Duration.zero),
        const ChapterEntry(title: '', start: Duration.zero),
        const ChapterEntry(title: 'Chapter 3', start: Duration.zero),
      ]);
      final text = ctrl.toQuickEditText(false);
      final lines = text.split('\n');
      expect(lines.length, equals(3));
      expect(lines[1], equals(''));
    });

    test('round-trip: list with placeholder entries → text → parse → same list', () {
      final entries = [
        const ChapterEntry(title: 'Intro', start: Duration.zero),
        const ChapterEntry(title: '', start: Duration.zero), // placeholder
        const ChapterEntry(
            title: 'Chapter 2', start: Duration(minutes: 10)),
      ];
      final ctrl = ChapterEditorController(entries: entries);
      final text = ctrl.toQuickEditText(true);
      final result =
          ChapterEditorController.parseQuickEditText(text, true);
      expect(result.errorLines, isEmpty);
      expect(result.entries.length, equals(3));
      expect(result.entries[0].title, equals('Intro'));
      expect(result.entries[1].title, equals(''));
      expect(result.entries[1].start, equals(Duration.zero));
      expect(result.entries[2].title, equals('Chapter 2'));
    });

    test('round-trip without timestamps: placeholder entries preserved', () {
      final entries = [
        const ChapterEntry(title: 'Part 1', start: Duration.zero),
        const ChapterEntry(title: '', start: Duration.zero), // placeholder
        const ChapterEntry(title: 'Part 3', start: Duration.zero),
      ];
      final ctrl = ChapterEditorController(entries: entries);
      final text = ctrl.toQuickEditText(false);
      final result =
          ChapterEditorController.parseQuickEditText(text, false);
      expect(result.errorLines, isEmpty);
      expect(result.entries.length, equals(3));
      expect(result.entries[1].title, equals(''));
    });

    test('first entry as placeholder: toQuickEditText starts with blank line', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: '', start: Duration.zero), // placeholder first
        const ChapterEntry(
            title: 'Chapter 2', start: Duration(minutes: 5)),
      ]);
      final text = ctrl.toQuickEditText(true);
      expect(text.startsWith('\n'), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // hasIncompleteEntries
  // ---------------------------------------------------------------------------
  group('hasIncompleteEntries', () {
    test('returns false for fully populated list', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'Chapter 1', start: Duration.zero),
        const ChapterEntry(
            title: 'Chapter 2', start: Duration(minutes: 5)),
      ]);
      expect(ctrl.hasIncompleteEntries(), isFalse);
      expect(ctrl.hasIncompleteEntries(requireTimestamps: true), isFalse);
    });

    test('returns true when any entry has empty title', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'Chapter 1', start: Duration.zero),
        const ChapterEntry(title: '', start: Duration.zero),
      ]);
      expect(ctrl.hasIncompleteEntries(), isTrue);
      expect(ctrl.hasIncompleteEntries(), isTrue);
    });

    test('returns true when title is whitespace-only', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: '   ', start: Duration.zero),
      ]);
      expect(ctrl.hasIncompleteEntries(), isTrue);
    });

    test('requireTimestamps: returns true when non-first entry has zero start', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'Chapter 1', start: Duration.zero),
        const ChapterEntry(title: 'Chapter 2', start: Duration.zero),
      ]);
      expect(ctrl.hasIncompleteEntries(), isFalse);
      expect(ctrl.hasIncompleteEntries(requireTimestamps: true), isTrue);
    });

    test('requireTimestamps: first entry zero start is not an error', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'Chapter 1', start: Duration.zero),
        const ChapterEntry(
            title: 'Chapter 2', start: Duration(minutes: 5)),
      ]);
      expect(ctrl.hasIncompleteEntries(requireTimestamps: true), isFalse);
    });

    test('returns false for empty list', () {
      final ctrl = ChapterEditorController(entries: []);
      expect(ctrl.hasIncompleteEntries(), isFalse);
      expect(ctrl.hasIncompleteEntries(requireTimestamps: true), isFalse);
    });

    test('returns false for single entry with non-empty title', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'Only Chapter', start: Duration.zero),
      ]);
      expect(ctrl.hasIncompleteEntries(), isFalse);
      expect(ctrl.hasIncompleteEntries(requireTimestamps: true), isFalse);
    });
  });
}
