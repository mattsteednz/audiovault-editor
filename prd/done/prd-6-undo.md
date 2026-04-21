# PRD-6 (P2): Undo — revert to last applied state

## Problem
Once Apply is hit, there is no way to go back. If the user applies incorrect metadata, they must manually retype the old values. The rescan button re-reads from disk but that only helps if the file write succeeded.

## Evidence
- `_apply` overwrites `_originalTitle` etc. with the new values immediately
- No snapshot of pre-apply state is kept

## Proposed Solution
- After a successful Apply, store a snapshot of the previous `Audiobook` state
- Add an "Undo" icon button that restores the snapshot and re-writes the files
- Only one level of undo (last apply); snapshot is cleared when a new book is selected or the folder is rescanned

## Decision Points
- Undo re-writes the files (not just the UI) — it calls `applyMetadata` with the snapshot values so the files match the UI
- Undo is disabled if no snapshot exists or if `_applying`
- Snapshot is stored on `_HomeScreenState` (not inside `BookDetailScreen`) so it survives book re-selection

## Acceptance Criteria
- [ ] Undo button appears after a successful Apply
- [ ] Clicking Undo restores the previous metadata in both UI and files
- [ ] Undo is only available for the most recent apply
- [ ] Undo clears when switching books or rescanning

## Out of Scope
- Multi-level undo
- Undoing cover art changes (file is already overwritten)

## Implementation Plan
1. Add `_undoSnapshot` (`Audiobook?`) to `_HomeScreenState`; set to the pre-apply book in `_onBookApplied`; clear on folder open and book selection change
2. Add `onUndo` callback to `BookDetailScreen`; pass `_undoSnapshot != null` as `canUndo`
3. Add Undo `IconButton` (undo icon) next to Rescan; calls `onUndo` when enabled
4. `onUndo` in `HomeScreen`: calls `MetadataWriter.applyMetadata` with snapshot, then `_onBookApplied(snapshot)`

## Files Impacted
- `lib/main.dart`
- `lib/screens/book_detail_screen.dart`
- `CHANGELOG.md`
