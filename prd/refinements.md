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

## PRD-9: Publisher/language edit
- `©pub` and `©lan` are non-standard iTunes atoms; some players may not read them. Standard alternatives (`cprt`, `©too`) exist but are less common. Kept as-is for now.

## PRD-10: Cover browse button
- `FilePicker.pickFiles(type: FileType.image)` on Windows shows all image types natively — no extension filtering needed.

## PRD-11: Write chapter names to M4B
- Deferred from this bundle. Writing `chpl` atoms requires careful byte-level surgery on the M4B container; the risk of corrupting files is non-trivial. Recommend a dedicated PRD with a round-trip test fixture before implementing.

## PRD-12: Duplicate detection
- Normalisation strips all non-alphanumeric characters. Books with very short titles (e.g. "It") may produce false positives if authors also match. Consider adding a minimum key length threshold.

## PRD-13: Missing cover filter
- Filter chips only appear after a scan (when counts > 0). If both filters are active simultaneously, books must satisfy both conditions (AND logic). OR logic may be more useful — log for follow-up.

## PRD-14: Genre field
- `Mp4Metadata.genre` field availability confirmed in audio_metadata_reader 1.4.2. `VorbisMetadata` uses `genres` (plural list).
- `©gen` atom is the freeform genre; `gnre` is the iTunes numeric genre. Using `©gen` for maximum compatibility with freeform strings.

## PRD-15: Multi-author
- Additional authors are read-only in the UI (display only). Editing them is deferred — requires a dynamic list widget.

## PRD-16: Rename folder
- Deferred from this bundle. Requires careful handling of in-memory path references across the book list and detail screen.

## PRD-17: Sort options
- Series sort places books with no series after all series books (empty string sorts last). Books with identical series are not sub-sorted by series index — could be a follow-up.

## PRD-18: Copy metadata from another book
- Deferred from this bundle. Requires a new dialog widget and passing `allBooks` down to `BookDetailScreen`.

## PRD-19: ISBN/ASIN
- `dc:identifier` is read and preserved in OPF round-trips. Editing deferred — identifier format validation (ISBN-13 check digit, ASIN format) would be needed for a good UX.

## PRD-20: OPF meta passthrough
- `calibre:series` and `calibre:series_index` are excluded from `opfMeta` to avoid duplication. All other `<meta name=...>` entries are preserved.
- Empty `content` attributes are skipped (consistent with existing field parsing).


- **Blank fields skipped**: Prevents accidentally blanking a field across 50 books.
- **Sequential apply**: Avoids file contention and makes progress reporting straightforward.
- **Single-click still opens detail view**: Checkbox is the batch selection mechanism — doesn't break existing single-book workflow.
