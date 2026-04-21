# PRD-18 (P3): Copy metadata from another book

## Problem
When adding a new book in a series where other books already have correct metadata, the user must manually retype author, narrator, series name, and series index. There is no way to copy those fields from an existing book in the library.

## Evidence
- No copy/paste mechanism exists between books
- `BatchEditScreen` can set shared fields but requires selecting multiple books and doesn't pre-fill from an existing book

## Proposed Solution
- Add a "Copy from…" button in the detail panel (in the action row, next to Export)
- Clicking it opens a searchable dialog listing all other books in the library
- Selecting a source book shows a checklist of fields to copy (Author, Narrator, Series, Series #, Genre, Publisher, Language)
- Confirming copies the checked fields into the current book's edit controllers and marks the book dirty
- No files are written until the user hits Apply

## Acceptance Criteria
- [ ] "Copy from…" button is visible in the detail panel action row
- [ ] Dialog lists all other books with search
- [ ] User can select which fields to copy
- [ ] Copied values populate the edit controllers and mark the book dirty
- [ ] Apply writes the copied values normally
- [ ] Button is disabled when the library has only one book

## Out of Scope
- Copying chapter names
- Copying cover art (use drag-and-drop for that)

## Implementation Plan
1. Add `onCopyFrom` callback to `BookDetailScreen` that receives a source `Audiobook` and a `Set<String>` of field names to copy
2. Add "Copy from…" `OutlinedButton.icon` in the action row; disabled when `allBooks.length <= 1`
3. Create `lib/widgets/copy_from_dialog.dart`: `StatefulWidget` with a `TextField` search, `ListView` of books, and a `CheckboxListTile` per copyable field; returns `(Audiobook source, Set<String> fields)` via `Navigator.pop`
4. In `BookDetailScreen`, on dialog result, update the relevant controllers and call `_onChanged()`
5. Pass `allBooks` (excluding current) down from `HomeScreen` to `BookDetailScreen`

## Files Impacted
- `lib/screens/book_detail_screen.dart` — button + `onCopyFrom` callback + `allBooks` param
- `lib/widgets/copy_from_dialog.dart` (new)
- `lib/main.dart` — pass `allBooks` to `BookDetailScreen`
- `CHANGELOG.md`
