# PRD-8 (P3): Batch metadata editing

## Problem
When fixing a whole series or an author's library, the user must open each book individually and apply the same author/narrator change repeatedly. There is no way to select multiple books and apply a field to all of them at once.

## Evidence
- `_selected` is a single `Audiobook?`; no multi-select exists
- `BookDetailScreen` operates on one book at a time

## Proposed Solution
- Add checkbox selection to sidebar list tiles (shown on hover or always visible)
- When 2+ books are selected, the detail panel switches to a "Batch edit" view showing only the fields that make sense to apply in bulk: Author, Narrator, Published, Series, Series Index
- A "Apply to N books" button writes the filled-in fields to all selected books; blank fields are skipped (not overwritten)

## Decision Points
- Selection model: `Set<String>` of paths in `_HomeScreenState`; single-click still selects for detail view, checkbox toggles batch selection
- Blank fields in batch edit are skipped — only non-empty fields are written
- Batch apply runs sequentially (not parallel) to avoid file contention
- Progress shown as `LinearProgressIndicator` with "X / N" counter
- After batch apply, selection is cleared and books list is updated

## Acceptance Criteria
- [ ] Checkboxes appear on list tiles; selecting 2+ shows batch edit panel
- [ ] Batch edit panel has Author, Narrator, Published, Series, Series # fields
- [ ] Only non-empty fields are written to each selected book
- [ ] Progress indicator shown during batch apply
- [ ] Books list updated after batch apply completes

## Out of Scope
- Batch chapter editing
- Batch cover art

## Implementation Plan
1. Add `_selectedPaths` (`Set<String>`) to `_HomeScreenState`
2. `ListTile` gets a leading `Checkbox`; `onChanged` toggles `_selectedPaths`; `onTap` sets `_selected` (single detail view)
3. Add `BatchEditPanel` widget (new file `lib/screens/batch_edit_screen.dart`) with 5 field controllers and "Apply to N books" button
4. `HomeScreen.build`: if `_selectedPaths.length >= 2`, show `BatchEditPanel` instead of `BookDetailScreen`
5. Batch apply: iterate selected books, call `MetadataWriter.applyMetadata` for each with only non-empty fields merged; update `_books` list after each
6. Show `LinearProgressIndicator` + counter during batch apply

## Files Impacted
- `lib/main.dart`
- `lib/screens/batch_edit_screen.dart` (new)
- `CHANGELOG.md`
