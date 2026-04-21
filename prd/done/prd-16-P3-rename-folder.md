# PRD-16 (P3): Rename folder and files from metadata

## Problem
After correcting metadata, the book's folder name and audio filenames often still reflect the old or incorrect values (e.g. a folder named "unknown_author - untitled" or files named "track01.mp3"). There is no way to rename them from within the app.

## Evidence
- `Audiobook.path` is the folder path; it is never mutated
- `Audiobook.audioFiles` contains the original file paths; they are never renamed
- No rename logic exists anywhere in the codebase

## Proposed Solution
- Add a "Rename folder" action in the detail panel (icon button or menu item under a "…" overflow menu)
- Clicking it proposes a new folder name derived from the current metadata using a configurable template (default: `{Author} - {Title}`)
- A confirmation dialog shows the current name → proposed name; user can edit the proposed name before confirming
- On confirm, rename the folder on disk and update `Audiobook.path` and `audioFiles` in the books list
- Optionally (separate toggle in the dialog): rename each audio file to `{index:02} - {ChapterName}.{ext}` for multi-file books

## Acceptance Criteria
- [ ] "Rename folder" action is accessible from the detail panel
- [ ] Dialog shows current → proposed name with an editable proposed-name field
- [ ] Confirming renames the folder on disk
- [ ] `_books` list and `_selected` are updated with the new path
- [ ] If the target folder name already exists, show an error and abort
- [ ] Rename is disabled while `_applying`

## Out of Scope
- Renaming individual audio files (deferred — complex for M4B single-file books)
- Undo for rename (filesystem rename is not easily reversible)

## Implementation Plan
1. Add `_renameFolder` method to `BookDetailScreen` (or as a standalone dialog widget)
2. Propose name: `'${book.author ?? 'Unknown'} - ${book.title ?? 'Untitled'}'` with filesystem-safe character stripping
3. Show `AlertDialog` with current name, `TextField` pre-filled with proposed name, Cancel / Rename buttons
4. On confirm: `Directory(book.path).rename(newPath)`; if `FileSystemException`, show error SnackBar
5. Call a new `onRenamed(String newPath)` callback on `HomeScreen`; update `_books` by replacing the book with `Audiobook` where `path` and `audioFiles` reflect the new location
6. Disable the action while `_applying` or `_rescanning`

## Files Impacted
- `lib/screens/book_detail_screen.dart` — rename action + dialog
- `lib/main.dart` — `onRenamed` callback, update `_books`
- `CHANGELOG.md`
