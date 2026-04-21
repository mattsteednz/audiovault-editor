# Refinements

Decision points that were resolved during PRD writing. Kept here for reference.

## PRD-1: Rescan

- **Single-book entry point**: Added `scanBook(String folderPath)` to `ScannerService` rather than exposing `_scanSubfolder` directly — keeps the private API clean.
- **Unsaved changes on rescan**: Show a confirmation dialog rather than silently discarding — avoids data loss surprise.

## PRD-2: Error handling

- **Return type for writer methods**: `List<String>` (per-file error strings) rather than a typed result object — minimal change, sufficient for the UI need.
- **Loading state**: `_applying` bool gates the Apply button and swaps the icon for a small `CircularProgressIndicator` — no separate loading overlay needed.
- **Silent success**: No SnackBar on full success — avoids noise for the common case.

## PRD-3: Search and sort

- **In-memory only**: `_books` is never mutated; `_filteredBooks` getter derives the display list — no risk of losing books when search is cleared.
- **Count reflects filter**: The book count shown updates to match the filtered result so the user knows how many matched.

## PRD-4: Series and description

- **Series is OPF-only**: No standard audio tag for series — Apply writes series/index to `metadata.opf` only, not to audio files.
- **Description in audio files**: MP3 COMM frame, MP4 `©cmt` atom — consistent with how other players store it.
- **Series index validation**: Non-numeric input silently ignored on apply rather than showing a validation error — keeps the UX simple.

## PRD-5: Split export

- **PopupMenuButton**: Keeps the toolbar compact vs. two separate buttons.
- **Export cover disabled when no cover**: Prevents writing an empty file.

## PRD-6: Undo

- **Undo re-writes files**: Ensures files and UI stay in sync — a UI-only undo would be misleading.
- **One level only**: Sufficient for the "oops I just applied the wrong thing" use case without the complexity of a full undo stack.
- **Snapshot on HomeScreen**: Survives book re-selection; cleared on folder open.

## PRD-7: Window title

- **`window_manager` package**: Standard approach for Flutter Windows; avoids writing a platform channel.
- **Folder name only**: Full path is too long for a title bar; last component is sufficient.

## PRD-8: Batch editing

- **Blank fields skipped**: Prevents accidentally blanking a field across 50 books.
- **Sequential apply**: Avoids file contention and makes progress reporting straightforward.
- **Single-click still opens detail view**: Checkbox is the batch selection mechanism — doesn't break existing single-book workflow.
