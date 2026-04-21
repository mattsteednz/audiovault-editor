# PRD-11 (P1): Write chapter names back to M4B atoms

## Problem
Users can rename chapters in the chapter table and hit Apply, but the new names are only stored in the in-memory `Audiobook` model. They are never written back to the M4B file's chapter atoms (`chpl` / QuickTime chapter track). The next rescan or any other player will still show the original names.

## Evidence
- `_apply` in `BookDetailScreen` builds `newChapters` with updated titles but only passes them to `widget.onApply(updated)` — no write path exists
- `MetadataWriter.applyMetadata` writes text tags but has no chapter-writing logic
- `MetadataWriter` has no method for writing `chpl` or QuickTime chapter atoms

## Proposed Solution
- Add `MetadataWriter.writeChapters(String filePath, List<Chapter> chapters)` that rewrites the `chpl` Nero chapter atom inside the M4B's `moov > udta` box
- Call it from `_apply` when `book.chapters.isNotEmpty` and any chapter title has changed
- Use the Nero `chpl` format (already parsed by `ScannerService._parseChpl`) for maximum compatibility

## Acceptance Criteria
- [ ] Renaming a chapter and hitting Apply updates the chapter name in the M4B file
- [ ] A rescan after Apply shows the new chapter names
- [ ] Non-M4B books (multi-file MP3, CUE) are unaffected — chapter names remain UI-only for those formats
- [ ] Chapter write errors surface in the existing error SnackBar

## Out of Scope
- Adding or removing chapters
- Writing chapters to MP3 files (no standard container)
- Writing QuickTime chapter track (only `chpl` Nero format)

## Implementation Plan
1. Add `MetadataWriter.writeChapters(String filePath, List<Chapter> chapters)`:
   - Read file bytes
   - Build a new `chpl` atom from the chapter list (mirror of `_parseChpl` in reverse)
   - Use the existing `_scanForChpl` / box-walking helpers to locate and replace the existing `chpl` atom, or inject one into `moov > udta` if absent
   - Write bytes back to file
2. In `BookDetailScreen._apply`, after `MetadataWriter.applyMetadata`, if `book.chapters.isNotEmpty` and any chapter title changed, call `MetadataWriter.writeChapters(book.audioFiles.first, newChapters)`; collect errors
3. Unit test: build a minimal M4B byte sequence with a `chpl` atom, call `writeChapters`, parse back with `_parseChpl`, assert titles match

## Files Impacted
- `lib/services/metadata_writer.dart` — add `writeChapters`
- `lib/screens/book_detail_screen.dart` — call `writeChapters` in `_apply`
- `test/services/metadata_writer_chapters_test.dart` (new)
- `CHANGELOG.md`
