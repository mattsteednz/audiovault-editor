# PRD-3 (P2): Sidebar search and sort

## Problem
With a large library the sidebar has no way to find a specific book or change the order. Books are always sorted alphabetically by title at scan time with no user control.

## Evidence
- `_buildBookList` renders all `_books` with no filtering
- Sort is applied once in `scanFolder` and never again

## Proposed Solution
- Add a search `TextField` below the Open Folder button; filters the visible list by title or author (case-insensitive substring)
- Add a sort menu (icon button) with options: Title A–Z, Title Z–A, Author A–Z, Author Z–A
- Filtering and sorting are in-memory only — the canonical `_books` list is never mutated

## Decision Points
- Sort state persists for the session only (no persistence to disk)
- Search clears when a new folder is opened
- The displayed count ("N book(s)") reflects the filtered count

## Acceptance Criteria
- [ ] Typing in the search box filters the list in real time
- [ ] Sort menu changes the display order
- [ ] Filtered count shown below search box
- [ ] Search and sort reset on new folder open

## Out of Scope
- Persisting sort preference across sessions
- Filtering by format, series, or narrator

## Implementation Plan
1. Add `_searchQuery` (String) and `_sortOrder` (enum: titleAsc, titleDesc, authorAsc, authorDesc) to `_HomeScreenState`
2. Add `_filteredBooks` getter that filters then sorts `_books`
3. Replace the book count `Text` with a `TextField` (search) + `PopupMenuButton` (sort) row
4. `_buildBookList` uses `_filteredBooks` instead of `_books`
5. Reset `_searchQuery` in `_pickFolder`

## Files Impacted
- `lib/main.dart`
- `CHANGELOG.md`
