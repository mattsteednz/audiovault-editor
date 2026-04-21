# PRD-34 (P4): Chapter bookmarks

## Problem
The app only tracks a single "current position" per book. Users can't mark a quote or interesting section to return to later. For long audiobooks this is a meaningful gap versus competing apps.

## Evidence
- `PositionService` stores only current position, not bookmarks
- No UI affordance for marking

## Proposed Solution
- Extend `PositionService` schema with a `bookmarks` table (`book_id`, `chapter_index`, `position_ms`, `label?`, `created_at`).
- Add a bookmark button to PlayerScreen (floating action or AppBar); long-press to label.
- Add a bookmarks sheet listing bookmarks for the current book; tap to seek.
- Optional: show bookmarks as ticks on the scrubber.

## Acceptance Criteria
- [ ] Users can add, label, jump to, and delete bookmarks
- [ ] Bookmarks persist across app restarts
- [ ] Schema migration tested on existing DB

## Out of Scope
- Cloud sync of bookmarks.

## Implementation Plan
1. Bump `PositionService` DB version from N to N+1 with `onUpgrade` adding:
   ```sql
   CREATE TABLE bookmarks (
     id INTEGER PRIMARY KEY AUTOINCREMENT,
     book_id TEXT NOT NULL,
     chapter_index INTEGER NOT NULL,
     position_ms INTEGER NOT NULL,
     label TEXT,
     created_at INTEGER NOT NULL
   );
   CREATE INDEX idx_bookmarks_book_id ON bookmarks(book_id);
   ```
2. Add methods to `PositionService`: `addBookmark(bookId, chapterIndex, positionMs, {label})`, `getBookmarks(bookId)`, `deleteBookmark(id)`, `updateBookmarkLabel(id, label)`.
3. Create `lib/models/bookmark.dart` data class.
4. PlayerScreen: add bookmark icon to AppBar → tap captures current chapter+position; long-press opens label dialog.
5. Create `lib/widgets/bookmarks_sheet.dart` — bottom sheet showing a `ListView.builder` of bookmarks for the current book; tap → seek via `audioHandler`; swipe-to-delete.
6. Optional: in player scrubber, overlay tick marks at bookmark positions (skip if complicates rendering; defer to follow-up).
7. Migration test: build DB at old version with sample positions, upgrade, assert new table exists and old data intact.
8. Unit tests for CRUD operations; widget test for the bookmarks sheet.

## Files Impacted
- `lib/services/position_service.dart` (schema + CRUD)
- `lib/models/bookmark.dart` (new)
- `lib/screens/player_screen.dart` (AppBar action + sheet launcher)
- `lib/widgets/bookmarks_sheet.dart` (new)
- `test/services/position_service_bookmarks_test.dart` (new)
- `test/services/position_service_migration_test.dart` (new)
- `CHANGELOG.md`
