# PRD-13 (P2): Missing cover art indicator and filter

## Problem
In a large library it is common to have books with no cover art. There is no way to quickly identify which books are missing covers without clicking through each one individually.

## Evidence
- `Audiobook.coverImagePath` and `coverImageBytes` are both nullable with no UI distinction between "has cover" and "no cover" in the sidebar list
- No filter exists for cover status

## Proposed Solution
- Show a small `Icons.image_not_supported` icon in the sidebar list tile when a book has no cover (both `coverImagePath` and `coverImageBytes` are null)
- Add a "No cover" `FilterChip` in the toolbar (alongside the future "Dupes" chip from PRD-12) that filters the list to books missing cover art
- The cover widget in `BookDetailScreen` already shows a placeholder icon — no change needed there

## Acceptance Criteria
- [ ] Books without cover art show a distinct icon in the sidebar
- [ ] "No cover" filter chip narrows the list to cover-less books
- [ ] Books with a cover do not show the icon
- [ ] Filter chip count badge shows how many books are missing covers

## Out of Scope
- Automatically fetching cover art from the internet
- Bulk cover assignment

## Implementation Plan
1. In `_HomeScreenState`, compute `int get _missingCoverCount` from `_books`
2. Sidebar `ListTile` subtitle row: append `Icon(Icons.image_not_supported, size: 12, color: Colors.grey)` when `coverImagePath == null && coverImageBytes == null`
3. Toolbar: add "No cover (_n_)" `FilterChip`; when active, `_filteredBooks` additionally filters to books missing cover
4. Update filter count label to reflect active filters

## Files Impacted
- `lib/main.dart` — filter chip, missing-cover predicate, count badge
- `CHANGELOG.md`
