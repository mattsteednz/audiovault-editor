# Implementation Plan: Editable Chapter Table

## Overview

Replace the read-only `DataTable` in `BookDetailScreen`'s Chapters tab with a fully interactive `ChapterEditor` widget. The work is split into five incremental steps: (1) the pure-Dart controller and data model, (2) the `ChapterEditor` widget and row UI, (3) the `QuickEditDialog` modal, (4) the `CueWriter` service, and (5) wiring everything into `BookDetailScreen` and `MetadataWriter`.

## Tasks

- [x] 1. Implement `ChapterEntry` and `ChapterEditorController`
  - Create `lib/widgets/chapter_editor.dart` with the `ChapterEntry` immutable value object (`title`, `start`, `copyWith`).
  - Implement `ChapterEditorController` as a pure Dart class (no Flutter imports) with:
    - `List<ChapterEntry> entries` field
    - `_undoStack` / `_redoStack` capped at 100 entries each
    - `canUndo`, `canRedo`, `hasConflicts` getters
    - `derivedDuration(int index, Duration? bookDuration)` — computed, never stored
    - Mutating methods `addChapter`, `insertChapter`, `deleteChapter`, `updateTitle`, `updateStart` — each pushes a snapshot before mutating and clears the redo stack
    - `replaceAll` for Quick Edit save
    - `undo()` / `redo()` / `clearHistory()`
    - `toQuickEditText(bool includeTimestamps)` serialiser
    - `static parseQuickEditText(String text, bool expectTimestamps)` parser returning `({List<ChapterEntry> entries, List<int> errorLines})`
    - `updateStart(0, ...)` must silently clamp to `Duration.zero` (first chapter is always locked)
  - Timestamp parsing must handle `MM:SS`, `HH:MM:SS`, and `MMM:SS` (minutes ≥ 100); disambiguation: one colon + left part ≤ 99 → `MM:SS`, one colon + left part > 99 → `MMM:SS`, two colons → `H:MM:SS`.
  - `parseQuickEditText` must use the rightmost comma as the title/timestamp separator; quoted titles (`"…"`) are also supported.
  - _Requirements: 1.1, 1.2, 1.4, 3.3, 3.4, 3.5, 4.1–4.3, 5.2, 6.2, 7.2, 8.2–8.5, 9.1, 9.2, 11.1, 11.2_

  - [ ]* 1.1 Write property test: population round-trip for single-file books
    - **Property 1: Population round-trip for single-file books**
    - **Validates: Requirements 1.1**

  - [ ]* 1.2 Write property test: population round-trip for multi-file books
    - **Property 2: Population round-trip for multi-file books**
    - **Validates: Requirements 1.2**

  - [ ]* 1.3 Write property test: derived duration correctness
    - **Property 3: Derived duration correctness**
    - **Validates: Requirements 1.4, 3.6**

  - [ ]* 1.4 Write property test: first chapter start is always zero
    - **Property 4: First chapter start is always zero**
    - **Validates: Requirements 3.3**

  - [ ]* 1.5 Write property test: timestamp parsing canonical round-trip
    - **Property 5: Timestamp parsing canonical round-trip**
    - **Validates: Requirements 3.4**

  - [ ]* 1.6 Write property test: conflict detection matches strictly-ascending invariant
    - **Property 6: Conflict detection matches strictly-ascending invariant**
    - **Validates: Requirements 4.1, 4.2, 4.3**

  - [ ]* 1.7 Write property test: add chapter places new row at correct start time
    - **Property 7: Add chapter places new row at correct start time**
    - **Validates: Requirements 5.2**

  - [ ]* 1.8 Write property test: insert chapter places new row at midpoint
    - **Property 8: Insert chapter places new row at midpoint**
    - **Validates: Requirements 6.2**

  - [ ]* 1.9 Write property test: row indices are always sequential after any mutation
    - **Property 9: Row indices are always sequential after any mutation**
    - **Validates: Requirements 6.3, 7.2**

  - [ ]* 1.10 Write property test: delete reduces count by one (when n > 1)
    - **Property 10: Delete reduces count by one (when n > 1)**
    - **Validates: Requirements 7.2**

  - [ ]* 1.11 Write property test: Quick Edit serialisation round-trip
    - **Property 11: Quick Edit serialisation round-trip**
    - **Validates: Requirements 8.2, 8.3, 8.7, 9.1, 9.2**

  - [ ]* 1.12 Write property test: Quick Edit rightmost-comma parsing
    - **Property 12: Quick Edit rightmost-comma parsing**
    - **Validates: Requirements 8.4**

  - [ ]* 1.13 Write property test: Quick Edit error lines identify exactly the invalid lines
    - **Property 13: Quick Edit error lines identify exactly the invalid lines**
    - **Validates: Requirements 8.5**

  - [ ]* 1.14 Write property test: undo/redo stack discipline
    - **Property 16: Undo/redo stack discipline**
    - **Validates: Requirements 11.2, 11.4, 11.5**

- [x] 2. Checkpoint — controller tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 3. Implement `ChapterEditor` widget and row UI
  - In `lib/widgets/chapter_editor.dart`, add the `ChapterEditor` `StatefulWidget`:
    - `initState` creates a `ChapterEditorController`, populates it from `book.chapters` (single-file) or `book.chapterNames`/`book.chapterDurations` (multi-file), and calls `clearHistory()`.
    - `didUpdateWidget` reinitialises the controller when `book.path` changes.
    - Toolbar row: Undo icon button, Redo icon button, Quick Edit button, and (for MP3 single-file books only) Export CUE button.
    - Conflict banner: shown below the toolbar when `controller.hasConflicts` is true; disables the Apply button via `onChanged` callback.
    - Column header row (custom `Row`, not `DataTable`): `#`, `Title`, `Start` (single-file only), `Duration`, `File` (multi-file only).
    - `ListView.builder` rendering:
      - `InsertDivider` between rows: a `MouseRegion` that reveals a `(+)` `IconButton` on hover; calls `controller.insertChapter(i)` then `setState`.
      - `ChapterRowWidget` per entry:
        - Index label.
        - Title `TextField` — calls `controller.updateTitle(i, v)` on change; marks dirty via `onChanged`.
        - Start time `TextField` (single-file only): row 0 is read-only (`00:00:00`); other rows use a `FocusNode` — on blur, parse and reformat to `HH:MM:SS`, show `InputDecoration.errorText` on invalid input, revert to last valid value; errors shown only on blur, never while typing.
        - Derived duration label (read-only).
        - File label (multi-file only).
        - Delete `IconButton` wrapped in `MouseRegion` (hover-reveal); disabled with tooltip when only one row remains.
      - `AddChapterButton` below the last row.
    - Every mutation calls `setState` and `widget.onChanged(controller.entries)`.
    - Undo/Redo buttons call `controller.undo()` / `controller.redo()` then `setState` and `widget.onChanged`.
    - `clearHistory()` is called when Apply fires (via `onApply` callback) and when a new book is loaded.
  - _Requirements: 1.1–1.4, 2.1–2.3, 3.1–3.8, 4.4–4.5, 5.1–5.4, 6.1–6.4, 7.1–7.5, 11.1–11.8, 12.1–12.2, 13.1–13.3_

  - [ ]* 3.1 Write widget tests for `ChapterEditor` toolbar and column visibility
    - Toolbar contains Undo, Redo, Quick Edit buttons.
    - Export CUE button present for MP3 single-file books, absent for M4B and multi-file books.
    - Start time column present for single-file books, absent for multi-file books.
    - _Requirements: 3.1, 3.2, 10.1, 10.7_

  - [ ]* 3.2 Write widget tests for row interactions
    - Delete button disabled on the only remaining row (tooltip shown).
    - Insert dividers visible on hover, hidden at rest.
    - Inline timestamp error appears after blur, not during typing.
    - First row start time field is read-only.
    - _Requirements: 3.3, 3.5, 4.4, 7.3_

- [x] 4. Implement `QuickEditDialog`
  - Create `lib/widgets/quick_edit_dialog.dart` with `QuickEditDialog` `StatefulWidget`:
    - Single multiline `TextField` with `fontFamily: 'monospace'`, minimum height 480 px.
    - Pre-populated via `initialText` from `controller.toQuickEditText(includeTimestamps)`.
    - Parse on every keystroke, debounced 300 ms, using `ChapterEditorController.parseQuickEditText`.
    - Side gutter: a narrow column to the left of the text area showing red error icons at the line numbers that failed to parse.
    - Save button disabled while any errors exist; shows error count badge ("3 errors") when errors are present.
    - On Save: validate full list for format errors and `hasConflicts`; if valid, call `onSave(entries)` and close; if invalid, keep modal open and display all errors.
    - On Cancel: close without calling `onSave`; `ChapterEditor` restores the pre-modal state.
    - Supports ≥ 200 lines without performance degradation (single `TextField`, not one widget per line).
  - In `ChapterEditor`, wire the Quick Edit button to open `QuickEditDialog` via `showDialog`; on save, call `controller.replaceAll(entries)` then `setState` and `widget.onChanged`.
  - _Requirements: 8.1–8.10, 9.1–9.3, 12.3_

  - [ ]* 4.1 Write widget tests for `QuickEditDialog`
    - Dialog opens pre-populated with current chapter text.
    - Save button disabled while parse errors exist.
    - Cancel discards changes and restores previous list.
    - _Requirements: 8.1, 8.2, 8.8, 8.9, 9.1_

- [x] 5. Implement `CueWriter` service
  - Create `lib/services/cue_writer.dart` with `CueWriter`:
    - `static String formatCueTime(Duration d)` — pure function; computes `MM:SS:FF` at 75 fps using `(msRemainder * 75 / 1000).round().clamp(0, 74)`.
    - `static String generate(String mp3Filename, String albumTitle, List<ChapterEntry> chapters)` — pure function; emits one `FILE` directive, one `TRACK` block per chapter with `TITLE` and `INDEX 01`.
    - `static Future<void> write(String bookPath, String bookTitle, String mp3Filename, List<ChapterEntry> chapters)` — writes `<bookTitle>.cue` to `bookPath`; throws `FileSystemException` on failure.
  - _Requirements: 10.2–10.6_

  - [ ]* 5.1 Write property test: CUE frame value is always in [0, 74]
    - **Property 14: CUE frame value is always in [0, 74]**
    - **Validates: Requirements 10.4**

  - [ ]* 5.2 Write property test: CUE sheet structure matches chapter list
    - **Property 15: CUE sheet structure matches chapter list**
    - **Validates: Requirements 10.3**

  - [ ]* 5.3 Write unit tests for `CueWriter`
    - Known duration `1:23:456 ms` → expected `MM:SS:FF` string.
    - Edge case: `Duration.zero` → `00:00:00`.
    - Edge case: ms remainder that rounds to 75 → clamped to 74.
    - Integration: CUE file written to correct path in a temp directory; `book.hasCue` set to `true` after successful write.
    - _Requirements: 10.2, 10.4, 10.5, 10.6_

- [x] 6. Checkpoint — all unit and widget tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 7. Wire `ChapterEditor` into `BookDetailScreen`
  - In `lib/screens/book_detail_screen.dart`:
    - Add `import` for `ChapterEditor`.
    - Add `List<ChapterEntry>? _pendingChapters` field.
    - Remove `_chapterCtrls` (`List<TextEditingController>`) and all references to it (declaration, `_initControllers`, `_disposeControllers`, `_onChanged`, `_apply`).
    - Remove `_originalChapterTitles` and its usages.
    - Replace `_buildChaptersTab` body with:
      ```dart
      return ChapterEditor(
        book: widget.book,
        onChanged: (chapters) {
          _pendingChapters = chapters;
          _onChanged();
        },
      );
      ```
    - Update `_onChanged` dirty check: replace the `_chapterCtrls` comparison with `_pendingChapters != null`.
    - Update `_apply()`: when `_pendingChapters != null`, build `newChapters` from `_pendingChapters` (converting `ChapterEntry` → `Chapter`) instead of from `_chapterCtrls`; reset `_pendingChapters = null` after a successful apply.
    - Add "Export CUE" to the existing `PopupMenuButton` overflow menu (⋮) — visible and enabled only when the book is a single-file MP3; on selection, call `CueWriter.write(...)`, update `book.hasCue`, and show a success or error `SnackBar`.
    - Clear `_pendingChapters` in `_initControllers` (called on book switch).
  - _Requirements: 1.1–1.3, 2.2, 5.4, 7.4, 11.7, 11.8, 13.3_

- [x] 8. Update `MetadataWriter` to write iTunes/QuickTime chapter track for M4B
  - In `lib/services/metadata_writer.dart`, add a `static Future<List<String>> applyChapters(Audiobook book)` method (or extend `applyMetadata`) that:
    - For M4B/M4A single-file books with a non-empty `book.chapters` list, calls `Mp4Writer.writeChapters(filePath, book.chapters, book.duration)`.
    - For MP3 single-file books, does nothing (chapters are stored in the CUE file, not embedded).
    - Returns per-file error strings.
  - In `lib/services/writers/mp4_writer.dart`, implement `static Future<void> writeChapters(String filePath, List<Chapter> chapters, Duration? bookDuration)`:
    - Builds a chapter text track (`mdia > hdlr` type `text`) with one sample per chapter (title as length-prefixed UTF-8 string).
    - Adds a `chap` atom in the audio track's `tref` box referencing the chapter track by track ID.
    - Expresses timing via the chapter track's `stts` table (sample duration = chapter duration in track timescale).
    - Removes any existing chapter track before writing the new one.
  - Call `applyChapters` from `_apply()` in `BookDetailScreen` when `_pendingChapters != null`.
  - _Requirements: 13.3_

- [x] 9. Final checkpoint — full test suite passes
  - Ensure all tests pass, ask the user if questions arise.

- [x] 10. Update `CHANGELOG.md`
  - Add an entry for the editable chapter table feature under the appropriate version heading.
  - _Requirements: (all)_

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP.
- Property tests use the `fast_check` package; each runs a minimum of 100 iterations.
- Tag format for property tests: `// Feature: editable-chapter-table, Property N: <property text>`
- `ChapterEditorController` is pure Dart — all property tests in task 1 run without Flutter widget infrastructure.
- The Export CUE menu item goes in the existing `PopupMenuButton` overflow menu (⋮), not a new toolbar button.
- Insert dividers and delete buttons are hover-reveal via `MouseRegion`.
- Quick Edit is a modal dialog (`showDialog`), not an inline toggle.
- Undo/redo is local to `ChapterEditorController`, separate from the global undo stack in `BookDetailScreen`.
- Errors are shown only on blur, never while typing.
- No confirmation dialogs for add/insert/delete operations.
