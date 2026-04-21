# PRD-12 (P2): Duplicate book detection

## Problem
Large libraries often accumulate duplicate audiobooks — same title/author in different folders, or the same book imported twice under slightly different names. There is no way to identify these without manually scrolling the list.

## Evidence
- `_books` list has no deduplication logic
- No UI affordance for flagging or comparing duplicates

## Proposed Solution
- After a scan completes, run a duplicate-detection pass that groups books by normalised `(title, author)` key (lowercase, punctuation stripped)
- Books that share a key are flagged with a `hasDuplicate` indicator in the sidebar (a small warning icon next to the dirty dot)
- A "Show duplicates" filter toggle in the toolbar narrows the list to only flagged books
- Selecting a flagged book shows a "Possible duplicate of: X" banner at the top of the detail panel with a "Go to" link

## Acceptance Criteria
- [ ] After scan, books with matching normalised title+author show a warning icon in the sidebar
- [ ] "Show duplicates" toggle filters the list to flagged books only
- [ ] Detail panel shows a banner listing the other book(s) with the same key
- [ ] "Go to" in the banner selects the other book
- [ ] No false positives for books with empty title or author

## Out of Scope
- Audio fingerprinting / content-based deduplication
- Automatic deletion

## Implementation Plan
1. After `_scanner.scanFolder` returns, compute a `Map<String, List<String>>` of normalised key → list of paths; store `Set<String> _duplicatePaths` on `_HomeScreenState`
2. Normalisation: `(title + author).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')`; skip entries where both are empty
3. Sidebar `ListTile`: add a `Icons.warning_amber` icon (amber, size 12) when `_duplicatePaths.contains(book.path)`
4. Toolbar: add a "Dupes" `FilterChip` that, when active, filters `_filteredBooks` to `_duplicatePaths` only
5. `BookDetailScreen`: accept an optional `List<Audiobook> duplicates` parameter; if non-empty, show a `MaterialBanner` at the top of the detail column listing titles with `TextButton` "Go to" that calls a new `onSelectBook` callback
6. Re-run duplicate detection after batch apply and after single-book apply

## Files Impacted
- `lib/main.dart` — duplicate detection pass, `_duplicatePaths`, filter chip, `onSelectBook` callback
- `lib/screens/book_detail_screen.dart` — optional `duplicates` param + banner
- `CHANGELOG.md`
