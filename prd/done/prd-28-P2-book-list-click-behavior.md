# PRD-28 (P2): Book list click behavior — switch books by default, batch select via checkbox

## Problem
Currently, clicking anywhere on a book list item (including the text) toggles the checkbox and enters batch-select mode. This is backwards for typical usage: users switch between books far more often than they select multiple books. The current behavior requires reaching for the checkbox to switch books, which is inefficient.

## Evidence
- `CheckboxListTile` in `_buildBookList` has `onChanged` that toggles batch selection on any click
- Single-click opens detail view only if the checkbox is unchecked
- No way to quickly switch between books without using the checkbox
- Batch selection is a secondary workflow (less common than single-book browsing)

## Proposed Solution
- Clicking the book text or anywhere except the checkbox → select that book (switch to detail view)
- Clicking the checkbox → toggle batch selection (add/remove from batch)
- Checkbox remains visible and functional for power users who need batch operations
- Single-click workflow is now the default; batch selection is opt-in via checkbox

## Acceptance Criteria
- [ ] Clicking book title/author text switches to that book (calls `selectBook`)
- [ ] Checkbox click toggles batch selection without switching books
- [ ] Checkbox is still visible and functional
- [ ] Selected book is highlighted (existing `selectedTileColor` behavior)
- [ ] Batch selection still works as before (2+ books checked → batch edit panel)
- [ ] No regression in batch edit workflow

## Out of Scope
- Changing batch edit panel behavior
- Keyboard navigation changes (handled separately in PRD-26)

## Implementation Plan
1. Replace `CheckboxListTile` with a custom `ListTile` + `Checkbox` layout
2. `ListTile` has `onTap` → call `selectBook(book)` (no batch toggle)
3. `Checkbox` has `onChanged` → call `toggleBatch(book, selected: checked)`
4. Ensure `selectedTileColor` still applies when book is selected
5. Verify batch edit panel still appears when 2+ books are checked

## Files Impacted
- `lib/main.dart` — replace `CheckboxListTile` with custom layout
- `CHANGELOG.md`

