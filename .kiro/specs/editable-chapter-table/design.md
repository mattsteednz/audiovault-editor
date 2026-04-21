# Design Document: Editable Chapter Table

## Overview

The Editable Chapter Table transforms the existing read-only `DataTable` in the Chapters tab into a fully interactive editing surface. The feature is scoped to the `BookDetailScreen` Chapters tab and introduces three new files: a `ChapterEditor` widget that owns all chapter editing state, a `QuickEditDialog` modal for bulk paste, and a `CueWriter` service for CUE sheet generation.

The guiding UX principle is **frictionless editing**: Tab/Enter advance focus naturally, timestamps auto-reformat on blur, errors appear only after a field is left, hover-reveal controls keep the table visually clean at rest, and undo handles mistakes so no confirmation dialogs are needed.

The design distinguishes two book modes throughout:

- **Single-file book** (`audioFiles.length == 1`, data in `book.chapters`): full editing — title, start time, add/insert/delete rows, CUE export.
- **Multi-file book** (`audioFiles.length > 1`, data in `chapterNames` + `chapterDurations`): title-only editing — start time column hidden, add/insert/delete disabled, Quick Edit available for titles only.

---

## Architecture

The feature is structured as a self-contained widget subtree. `BookDetailScreen` delegates the entire Chapters tab to `ChapterEditor`, passing the book in and receiving an updated chapter list out via a callback. All chapter-specific state (in-memory list, undo/redo stack, validation errors, hover state) lives inside `ChapterEditor` and never leaks into `_BookDetailScreenState`.

```
BookDetailScreen
└── ChapterEditor (stateful, owns chapter state)
    ├── Toolbar Row
    │   ├── Undo / Redo buttons
    │   ├── Quick Edit button  →  QuickEditDialog (modal)
    │   └── Export CUE button  (MP3 single-file only)
    ├── Column header row  (custom, not DataTable)
    └── ListView.builder
        ├── InsertDivider (hover-reveal, between rows)
        ├── ChapterRowWidget (per row)
        │   ├── Index label
        │   ├── Title TextField
        │   ├── StartTime TextField  (single-file only)
        │   ├── Duration label
        │   ├── File label  (multi-file only)
        │   └── Delete IconButton  (hover-reveal)
        └── AddChapterButton (below last row)
```

`ChapterEditorController` is a plain Dart class (not a `ChangeNotifier`) that holds the mutable chapter list and undo/redo stacks. `ChapterEditor` calls `setState` after every mutation. This keeps the logic testable without Flutter dependencies.

---

## Components and Interfaces

### `ChapterEntry`

Immutable value object representing one row in the editor's in-memory list.

```dart
class ChapterEntry {
  final String title;
  final Duration start;   // always Duration.zero for row 0
  // Derived duration is computed on the fly, not stored.
  const ChapterEntry({required this.title, required this.start});
  ChapterEntry copyWith({String? title, Duration? start});
}
```

Multi-file books use the same type; `start` is set to `Duration.zero` for all rows (unused) and duration is read from `book.chapterDurations` by index.

### `ChapterEditorController`

Pure Dart class. Owns the list and undo/redo stacks. All mutating methods push a snapshot before modifying.

```dart
class ChapterEditorController {
  List<ChapterEntry> entries;
  final List<List<ChapterEntry>> _undoStack = [];
  final List<List<ChapterEntry>> _redoStack = [];

  // Queries
  bool get canUndo;
  bool get canRedo;
  bool get hasConflicts;  // any start[i] >= start[i+1]
  Duration derivedDuration(int index, Duration? bookDuration);

  // Mutations (each pushes undo snapshot, clears redo)
  void addChapter();
  void insertChapter(int afterIndex);
  void deleteChapter(int index);
  void updateTitle(int index, String title);
  void updateStart(int index, Duration start);
  void replaceAll(List<ChapterEntry> newEntries);

  // Undo/redo
  void undo();
  void redo();
  void clearHistory();

  // Serialisation helpers (used by QuickEditDialog)
  String toQuickEditText(bool includeTimestamps);
  static ({List<ChapterEntry> entries, List<int> errorLines}) parseQuickEditText(
      String text, bool expectTimestamps);
}
```

### `ChapterEditor` widget

```dart
class ChapterEditor extends StatefulWidget {
  final Audiobook book;
  final void Function(List<ChapterEntry> chapters) onChanged;
  // onChanged is called after every mutation so BookDetailScreen
  // can update its dirty state.
}
```

`ChapterEditor` creates a `ChapterEditorController` in `initState`, populates it from `book.chapters` (single-file) or `book.chapterNames`/`book.chapterDurations` (multi-file), and rebuilds on every mutation.

`BookDetailScreen._buildChaptersTab` is replaced with:

```dart
Widget _buildChaptersTab(ThemeData theme) {
  return ChapterEditor(
    book: widget.book,
    onChanged: (chapters) {
      _pendingChapters = chapters;
      _onChanged();
    },
  );
}
```

`_apply()` uses `_pendingChapters` (if non-null) instead of `_chapterCtrls` when building the updated `Audiobook`. The existing `_chapterCtrls` list is removed.

### `QuickEditDialog` widget

```dart
class QuickEditDialog extends StatefulWidget {
  final String initialText;
  final bool includeTimestamps;
  final void Function(List<ChapterEntry> result) onSave;
}
```

Contains a single multiline `TextField` with `fontFamily: 'monospace'`, minimum height 480 px. Parses on every keystroke (debounced 300 ms) to show live error annotations in a side gutter. Save button is disabled while any errors exist.

### `CueWriter` service

```dart
class CueWriter {
  const CueWriter._();

  /// Generates CUE sheet content as a String.
  /// Pure function — no I/O.
  static String generate(String mp3Filename, String albumTitle,
      List<ChapterEntry> chapters);

  /// Writes the CUE file to [bookPath]/<bookTitle>.cue.
  static Future<void> write(String bookPath, String bookTitle,
      String mp3Filename, List<ChapterEntry> chapters);

  /// Converts a Duration to CUE MM:SS:FF notation (75 fps).
  static String formatCueTime(Duration d);
}
```

`generate` is a pure function, making it straightforward to test without filesystem access.

### M4B chapter embedding format

For M4B (and M4A) single-file books, chapters are written using the **iTunes/QuickTime chapter track** format, not the Nero `chpl` atom. This means:

- A dedicated chapter text track (`mdia > hdlr` type `text`) is written inside `moov`, with one sample per chapter containing the chapter title as a length-prefixed UTF-8 string.
- A corresponding `chap` atom in the audio track's `tref` box references the chapter track by track ID.
- Timing is expressed via the chapter track's `stts` (sample-to-time) table, with each sample duration equal to the chapter's duration in the track's timescale.

This is the format read by iTunes, Apple Books, and most Apple-ecosystem players. The existing `ScannerService` already parses this format; `MetadataWriter.writeChapters` must write it using the same structure in reverse.

---

## Data Models

### In-memory chapter list

The editor maintains `List<ChapterEntry>` as its source of truth. This is separate from `book.chapters` (which is the last-applied state). The list is initialised from the book on widget creation and written back to the book only when the user clicks Apply.

### Derived duration computation

```
derivedDuration(i) =
  if i < entries.length - 1:  entries[i+1].start - entries[i].start
  else:                        book.duration - entries[i].start  (or null if book.duration is null)
```

This is computed on every render pass — never stored — so it is always consistent with the current start times.

### Undo/redo snapshots

Each snapshot is a `List<ChapterEntry>` (deep copy via `List.of(entries)`). The undo stack is capped at 100 entries to bound memory use. The redo stack is cleared on every non-undo/redo mutation.

### Timestamp parsing

The parser accepts three formats:

| Input example | Pattern |
|---|---|
| `5:30` | `MM:SS` — minutes 0–99, seconds 0–59 |
| `1:05:30` | `H:MM:SS` or `HH:MM:SS` |
| `125:30` | `MMM:SS` — minutes ≥ 100 |

Disambiguation rule: a string with exactly one colon is `MM:SS` if the left part is ≤ 99, otherwise `MMM:SS`. A string with two colons is `H:MM:SS`.

On blur, the field is reformatted to `HH:MM:SS` (zero-padded hours, two-digit minutes and seconds).

### CUE frame computation

```
totalMs = duration.inMilliseconds
minutes = totalMs ~/ 60000
seconds = (totalMs % 60000) ~/ 1000
msRemainder = totalMs % 1000
frames = (msRemainder * 75 / 1000).round().clamp(0, 74)
output = "${minutes.toString().padLeft(2,'0')}:${seconds.toString().padLeft(2,'0')}:${frames.toString().padLeft(2,'0')}"
```

---

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system — essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Population round-trip for single-file books

*For any* non-empty `List<Chapter>`, initialising a `ChapterEditorController` from that list and reading back `entries` should produce a list of the same length where each entry's `title` and `start` equal the corresponding source chapter's `title` and `start`.

**Validates: Requirements 1.1**

### Property 2: Population round-trip for multi-file books

*For any* multi-file book with `n` audio files, initialising a `ChapterEditorController` from that book should produce exactly `n` entries whose titles match `chapterNames` (falling back to the filename stem) and whose derived durations match `chapterDurations`.

**Validates: Requirements 1.2**

### Property 3: Derived duration correctness

*For any* list of `ChapterEntry` values with strictly ascending start times and a known `bookDuration`, the derived duration of entry `i` should equal `entries[i+1].start - entries[i].start` for all `i < n-1`, and `bookDuration - entries[n-1].start` for the last entry.

**Validates: Requirements 1.4, 3.6**

### Property 4: First chapter start is always zero

*For any* `ChapterEditorController` with at least one entry, `entries[0].start` is always `Duration.zero`, regardless of what value is passed to `updateStart(0, ...)`.

**Validates: Requirements 3.3**

### Property 5: Timestamp parsing canonical round-trip

*For any* valid timestamp string in `MM:SS`, `HH:MM:SS`, or `MMM:SS` format, parsing it to a `Duration` and then formatting that `Duration` back to `HH:MM:SS` should produce a string that represents the same total seconds as the original input.

**Validates: Requirements 3.4**

### Property 6: Conflict detection matches strictly-ascending invariant

*For any* list of `ChapterEntry` values, `ChapterEditorController.hasConflicts` is `true` if and only if there exists at least one index `i` such that `entries[i].start >= entries[i+1].start`.

**Validates: Requirements 4.1, 4.2, 4.3**

### Property 7: Add chapter places new row at correct start time

*For any* `ChapterEditorController` with `n` entries (n ≥ 1) and a known `bookDuration`, calling `addChapter()` should append an entry at index `n` whose `start` equals `entries[n-1].start + derivedDuration(n-1)`.

**Validates: Requirements 5.2**

### Property 8: Insert chapter places new row at midpoint

*For any* `ChapterEditorController` with at least two entries, inserting between index `i` and `i+1` should produce a new entry at index `i+1` whose `start` equals `(entries[i].start + entries[i+1].start) ~/ 2`.

**Validates: Requirements 6.2**

### Property 9: Row indices are always sequential after any mutation

*For any* sequence of add, insert, and delete operations on a `ChapterEditorController`, the resulting entries should always be indexable as `0, 1, 2, ..., n-1` (i.e., the list is contiguous with no gaps).

**Validates: Requirements 6.3, 7.2**

### Property 10: Delete reduces count by one (when n > 1)

*For any* `ChapterEditorController` with `n > 1` entries, calling `deleteChapter(i)` for any valid index `i` should produce a list of exactly `n - 1` entries, and the entries that remain should be the original entries with index `i` removed (order preserved).

**Validates: Requirements 7.2**

### Property 11: Quick Edit serialisation round-trip

*For any* list of `ChapterEntry` values with valid titles and strictly ascending start times, serialising to Quick Edit text via `toQuickEditText` and then parsing back via `parseQuickEditText` should produce an equivalent list (same titles, same start times, zero error lines).

**Validates: Requirements 8.2, 8.3, 8.7, 9.1, 9.2**

### Property 12: Quick Edit rightmost-comma parsing

*For any* chapter title that contains one or more commas, serialising that entry to a Quick Edit line and parsing it back should recover the original title exactly (the rightmost comma is used as the title/timestamp separator).

**Validates: Requirements 8.4**

### Property 13: Quick Edit error lines identify exactly the invalid lines

*For any* Quick Edit text where a subset of lines are malformed, `parseQuickEditText` should return an `errorLines` list that contains exactly the 0-based indices of the malformed lines and no others.

**Validates: Requirements 8.5**

### Property 14: CUE frame value is always in [0, 74]

*For any* `Duration`, `CueWriter.formatCueTime` should produce a string whose frame component (the last two digits) is an integer in the range [0, 74] inclusive.

**Validates: Requirements 10.4**

### Property 15: CUE sheet structure matches chapter list

*For any* non-empty list of `ChapterEntry` values and a valid MP3 filename, `CueWriter.generate` should produce a string containing exactly one `FILE` directive, exactly `n` `TRACK` blocks (one per chapter), and exactly `n` `INDEX 01` lines in `MM:SS:FF` format.

**Validates: Requirements 10.3**

### Property 16: Undo/redo stack discipline

*For any* sequence of mutations followed by a sequence of undos, the `ChapterEditorController` state after `k` undos should equal the state that existed `k` mutations ago. Redoing all undone steps should restore the state to the post-mutation state.

**Validates: Requirements 11.2, 11.4, 11.5**

---

## Error Handling

### Timestamp validation errors

- Displayed inline beneath the offending `TextField` using `InputDecoration.errorText`.
- Shown only after the field loses focus (`onEditingComplete` / `FocusNode.onKeyEvent` for Enter), never while typing.
- The field reverts to the last valid value when the user leaves it with an invalid entry.
- A summary banner in the toolbar ("Fix timestamp conflicts before applying") is shown when `hasConflicts` is true; the Apply button is disabled.

### Quick Edit parse errors

- The `QuickEditDialog` shows a side gutter (a narrow column to the left of the text area) with red error icons at the line numbers that failed to parse.
- A count badge on the Save button ("3 errors") communicates the total error count.
- The Save button is disabled while any errors exist.
- Errors are recomputed on a 300 ms debounce after each keystroke to avoid jank on large pastes.

### Delete last row

- The delete button on the only remaining row is disabled (greyed out) with a `Tooltip` reading "At least one chapter is required".

### CUE write failure

- A `SnackBar` with `backgroundColor: Colors.red[900]` displays the `FileSystemException.message`.
- `book.hasCue` is not updated on failure.

### Apply with conflicts

- The Apply button remains disabled (`onPressed: null`) while `hasConflicts` is true.
- The toolbar banner provides the reason so the user is not left wondering why Apply is greyed out.

---

## Testing Strategy

### Unit tests — `test/services/cue_writer_test.dart`

Focus on the pure `CueWriter.generate` and `CueWriter.formatCueTime` functions:

- Property 14: frame value in [0, 74] for generated `Duration` values.
- Property 15: CUE structure matches chapter list for generated inputs.
- Example: known duration `1:23:456 ms` → expected `MM:SS:FF` string.
- Edge case: `Duration.zero` → `00:00:00`.
- Edge case: duration with ms remainder that rounds to 75 → clamped to 74.

### Unit tests — `test/widgets/chapter_editor_test.dart`

Focus on `ChapterEditorController` (pure Dart, no Flutter):

- Properties 1–3: population and derived duration.
- Property 4: first chapter start locked to zero.
- Property 5: timestamp parsing round-trip.
- Property 6: conflict detection.
- Properties 7–10: add/insert/delete mutations.
- Properties 11–13: Quick Edit serialisation and parsing.
- Property 16: undo/redo stack discipline.
- Edge cases: delete last row is a no-op; single-row state after delete.

### Widget tests — `test/widgets/chapter_editor_test.dart`

Flutter widget tests for UI behaviour:

- Toolbar contains Undo, Redo, Quick Edit buttons.
- Export CUE button present for MP3 single-file books, absent otherwise.
- Start time column present for single-file books, absent for multi-file books.
- Delete button disabled on the only remaining row.
- Insert dividers visible on hover, hidden at rest.
- Inline error appears after blur, not during typing.
- Quick Edit dialog opens pre-populated with current chapter text.

### Property-based testing

Use the [`fast_check`](https://pub.dev/packages/fast_check) package (Dart port of fast-check) for property tests. Each property test runs a minimum of 100 iterations.

Tag format: `// Feature: editable-chapter-table, Property N: <property text>`

Properties suited for PBT (pure functions, no I/O):

| Property | Generator |
|---|---|
| 1, 2 | `Arbitrary.list(arbitraryChapter, minLength: 1)` |
| 3 | sorted `List<Duration>` + `bookDuration` |
| 4 | any `Duration` passed to `updateStart(0, ...)` |
| 5 | valid timestamp strings in all three formats |
| 6 | `List<Duration>` (unsorted and sorted variants) |
| 7, 8, 9, 10 | `List<ChapterEntry>` with varying lengths |
| 11, 12, 13 | `List<ChapterEntry>` with titles containing commas |
| 14 | `Duration` with arbitrary milliseconds |
| 15 | `List<ChapterEntry>` + MP3 filename string |
| 16 | sequence of mutation operations |

### Integration tests

- CUE file is written to the correct path on disk (uses a temp directory).
- `book.hasCue` is set to `true` after a successful write.
- `_apply()` in `BookDetailScreen` passes the correct `chapters` list to `onApply` after a Quick Edit save.
