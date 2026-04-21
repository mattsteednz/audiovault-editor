# PRD-1 (P1): Per-book rescan

## Problem
After hitting Apply, the user has to reopen the entire folder to verify that file tags were updated correctly. The OPF/File tags toggle shows the in-memory state but doesn't re-read from disk. There is no way to confirm a write succeeded without closing and reopening the library.

## Evidence
- `_apply` in `BookDetailScreen` updates in-memory `Audiobook` but never re-reads from disk
- The "File tags" toggle reads `fileTitleRaw` etc. which are set at scan time and updated optimistically on Apply — not from disk

## Proposed Solution
Add a rescan button (refresh icon) in the detail panel header. It re-scans the single book folder using `ScannerService.scanSingleBook` (to be added), replaces the book in the list, and resets the detail view — giving a true disk read to confirm writes.

## Decision Points
- `ScannerService` currently has no single-book entry point. Add `scanBook(String folderPath)` that calls `_scanSubfolder` directly.
- The rescan button should be disabled while a scan is in progress to prevent double-taps.
- If the book has unsaved changes, rescan discards them — show a confirmation dialog first.

## Acceptance Criteria
- [ ] Rescan button visible in detail panel header
- [ ] Clicking it re-reads the book folder from disk and updates the UI
- [ ] If unsaved changes exist, a confirmation dialog warns before discarding
- [ ] Button is disabled during the rescan

## Out of Scope
- Rescanning the entire library (that's the existing Open Folder button)

## Implementation Plan
1. Add `Future<Audiobook?> scanBook(String folderPath)` to `ScannerService` — delegates to `_scanSubfolder`
2. Add `onRescan` callback to `BookDetailScreen` signature
3. Add rescan `IconButton` next to Export metadata; disable while `_applying` or `_rescanning`
4. On tap: if `_isDirty`, show `AlertDialog` confirming discard; on confirm call `onRescan`
5. In `HomeScreen._onBookRescanned`: call `scanner.scanBook`, update `_books` list and `_selected`

## Files Impacted
- `lib/services/scanner_service.dart` — add `scanBook`
- `lib/screens/book_detail_screen.dart` — rescan button + callback
- `lib/main.dart` — `_onBookRescanned` handler
- `CHANGELOG.md`
