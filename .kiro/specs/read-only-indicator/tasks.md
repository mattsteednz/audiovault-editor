# Implementation Plan: Read-Only Indicator

## Overview

Add read-only permission detection to the scan pipeline and surface the result as a visual indicator throughout the UI. The work flows from the data model outward: add the `ReadOnlyStatus` enum and field to `Audiobook`, detect permissions in `ScannerService`, propagate the value through `LibraryController`, then render badges, filter chips, and Apply-button gating in the UI.

## Tasks

- [x] 1. Add `ReadOnlyStatus` enum and `readOnlyStatus` field to the `Audiobook` model
  - Define `enum ReadOnlyStatus { writable, folderReadOnly, filesReadOnly }` in `lib/models/audiobook.dart`
  - Add `final ReadOnlyStatus readOnlyStatus` field to `Audiobook`, defaulting to `ReadOnlyStatus.writable`
  - Add `readOnlyStatus` parameter to the `Audiobook` constructor with a default of `ReadOnlyStatus.writable`
  - Extend `Audiobook.copyWith` to accept and propagate a `ReadOnlyStatus? readOnlyStatus` parameter
  - _Requirements: 2.1, 2.2, 2.3_

  - [ ]* 1.1 Write unit tests for `readOnlyStatus` field and `copyWith` behaviour
    - Verify default value is `ReadOnlyStatus.writable` when not set
    - Verify `copyWith` preserves existing value when not passed
    - Verify `copyWith` updates value when explicitly passed
    - _Requirements: 2.1, 2.2, 2.3_

- [x] 2. Implement permission detection in `ScannerService`
  - Add a private `_checkReadOnlyStatus(Directory dir, List<String> audioFiles)` method to `ScannerService` that returns a `ReadOnlyStatus`
  - Check folder writability using `dart:io` `FileStat` or a probe write approach without modifying files (e.g. check `FileStat.modeString` or attempt `Directory.createTemp` and immediately delete it)
  - Check each audio file's writability using `File.openWrite` with a try/catch, or `FileStat` mode bits — do not write any bytes
  - Apply the three-way logic: folder not writable → `folderReadOnly`; folder writable but any file not writable → `filesReadOnly`; all writable → `writable`
  - Call `_checkReadOnlyStatus` inside `_scanSubfolder` and pass the result to the `Audiobook` constructor as `readOnlyStatus`
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7_

  - [ ]* 2.1 Write unit tests for `_checkReadOnlyStatus` logic
    - Expose a `@visibleForTesting` static helper or test via a thin wrapper to verify the three-way classification
    - Test: folder read-only → `folderReadOnly`
    - Test: folder writable, one file read-only → `filesReadOnly`
    - Test: all writable → `writable`
    - _Requirements: 1.3, 1.4, 1.5_

- [x] 3. Checkpoint — Ensure model and scanner tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 4. Update `LibraryController` to track and expose read-only state
  - Add `int _readOnlyCount` field and `Set<String> _readOnlyPaths` to `LibraryController`
  - Add `bool _showReadOnlyOnly` field, `int get readOnlyCount`, `bool get showReadOnlyOnly`, and `void toggleShowReadOnly()` following the same pattern as `showDuplicatesOnly`
  - Update `_recomputeFlags` to populate `_readOnlyPaths` and `_readOnlyCount` from `_books` where `readOnlyStatus != ReadOnlyStatus.writable`
  - Update `filteredBooks` to filter by `_readOnlyPaths` when `_showReadOnlyOnly` is true
  - Ensure `onBookApplied` and `onBookRenamed` preserve `readOnlyStatus` from the updated `Audiobook` (the value already lives on the model, so `copyWith` propagation is sufficient — verify no accidental reset occurs)
  - _Requirements: 2.4, 6.5, 6.6, 6.7_

  - [ ]* 4.1 Write unit tests for `LibraryController` read-only tracking
    - Test `readOnlyCount` returns correct count after books are loaded
    - Test `toggleShowReadOnly` filters `filteredBooks` correctly
    - Test `_recomputeFlags` updates count when book list changes
    - _Requirements: 6.5, 6.6, 6.7_

- [x] 5. Add the Read-Only Badge widget
  - Create `lib/widgets/read_only_badge.dart` containing a small `ReadOnlyBadge` widget
  - The widget accepts an optional `String? tooltip` parameter
  - Render `Icon(Icons.lock_outline, size: 12)` for list usage (no colour override) and `Icon(Icons.lock_outline, size: 16, color: Colors.amber)` for detail-panel usage — accept a `bool prominent` flag to switch between the two styles
  - Wrap the icon in a `Tooltip` widget using the provided tooltip string when non-null
  - _Requirements: 3.3, 3.4, 4.5_

- [x] 6. Show the Read-Only Badge in the book list sidebar
  - In `lib/main.dart`, inside `_buildBookList`'s `ListTile` subtitle `Row`, add a `ReadOnlyBadge` with `prominent: false` when `book.readOnlyStatus != ReadOnlyStatus.writable`
  - Position the badge before the author text, alongside the existing duplicate-warning and missing-cover icons, following the same `Padding(padding: EdgeInsets.only(right: 4), child: ...)` pattern
  - Do not show the badge when `readOnlyStatus == ReadOnlyStatus.writable`
  - _Requirements: 3.1, 3.2, 3.4, 3.5_

- [x] 7. Add the "Read-only (N)" filter chip to the sidebar toolbar
  - In `lib/main.dart`, inside `_buildToolbar`'s `Wrap` of filter chips, add a `FilterChip` labelled `'Read-only (${_ctrl.readOnlyCount})'`
  - Set `selected: _ctrl.showReadOnlyOnly`
  - Set `onSelected` to `(_) => _ctrl.toggleShowReadOnly()` when `_ctrl.readOnlyCount > 0`, otherwise `null` (disabled)
  - Match the existing chip style (`labelStyle`, `padding`, `visualDensity`)
  - _Requirements: 6.1, 6.2, 6.3, 6.4_

- [x] 8. Show the Read-Only Badge in the Book Detail panel
  - In `lib/screens/book_detail_screen.dart`, inside `_buildSummary`, add a `ReadOnlyBadge` with `prominent: true` below the title line when `widget.book.readOnlyStatus != ReadOnlyStatus.writable`
  - Pass the correct tooltip string:
    - `folderReadOnly` → `"Folder is read-only — metadata changes cannot be saved"`
    - `filesReadOnly` → `"One or more audio files are read-only — metadata changes cannot be saved"`
  - Do not show the badge when `readOnlyStatus == ReadOnlyStatus.writable`
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

- [x] 9. Disable the Apply button for read-only books
  - In `lib/screens/book_detail_screen.dart`, inside `_buildActionBar`, locate the Apply `FilledButton`
  - Compute `final bool isReadOnly = widget.book.readOnlyStatus != ReadOnlyStatus.writable`
  - Set `onPressed` to `null` when `isReadOnly` is true (in addition to the existing `_applying` and `_isDirty` guards)
  - Wrap the Apply button in a `Tooltip` with message `"Cannot save — folder or files are read-only"` when `isReadOnly` is true; otherwise use the existing tooltip or none
  - Ensure Undo, Rescan, and other action buttons are unaffected
  - _Requirements: 5.1, 5.2, 5.3, 5.4_

  - [ ]* 9.1 Write widget tests for Apply button disabled state
    - Pump a `BookDetailScreen` with a book whose `readOnlyStatus` is `folderReadOnly` and verify the Apply button is disabled
    - Pump with `readOnlyStatus == writable` and verify the Apply button follows normal dirty-state logic
    - _Requirements: 5.1, 5.2, 5.3_

- [x] 10. Final checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP
- Each task references specific requirements for traceability
- The permission check in task 2 must be non-destructive — no files may be written or modified during detection
- The `ReadOnlyStatus` enum should be defined in `lib/models/audiobook.dart` alongside the `Audiobook` class for co-location
- `onBookRenamed` in `LibraryController` manually constructs a new `Audiobook`; update it to carry `readOnlyStatus` from the original book
