# PRD-26 (P4): Keyboard shortcuts

## Problem
All actions in the app require mouse interaction. Power users editing many books in sequence have no way to apply changes, undo, navigate between books, or trigger a rescan without reaching for the mouse. This slows down bulk editing workflows significantly.

## Evidence
- No `Shortcuts` or `Actions` widgets exist anywhere in the widget tree
- No `Focus` nodes are configured for keyboard navigation between the sidebar and detail panel
- `FilledButton` for Apply, `IconButton` for Undo/Rescan have no keyboard equivalents

## Proposed Solution
Register a set of global keyboard shortcuts using Flutter's `Shortcuts` + `Actions` system:

| Shortcut | Action |
|---|---|
| `Ctrl+S` | Apply (if dirty and not applying) |
| `Ctrl+Z` | Undo last apply |
| `Ctrl+R` | Rescan selected book |
| `↑` / `↓` | Navigate to previous/next book in the sidebar list |
| `Ctrl+F` | Focus the search field |
| `Escape` | Clear search field (if focused) |

## Acceptance Criteria
- [ ] `Ctrl+S` triggers Apply when a book is selected and has unsaved changes
- [ ] `Ctrl+Z` triggers Undo when an undo snapshot is available
- [ ] `Ctrl+R` triggers Rescan for the selected book
- [ ] `↑` / `↓` move selection through the sidebar book list
- [ ] `Ctrl+F` moves keyboard focus to the search field
- [ ] `Escape` clears the search field when it is focused
- [ ] Shortcuts do not fire when a text field has focus (except Escape and Ctrl+F)
- [ ] Shortcuts are documented in a tooltip or help overlay (P4 — can be a simple `?` icon button showing a dialog)

## Out of Scope
- Customisable key bindings
- Shortcuts for batch edit actions
- Full keyboard-only navigation of the metadata form fields (tab order is handled by Flutter's default focus traversal)

## Decision Points
- `Shortcuts` + `Actions` at the `HomeScreen` level covers the global shortcuts. Text field focus is handled by checking `FocusManager.instance.primaryFocus` — if it is a `TextField`, suppress navigation shortcuts but allow `Ctrl+S`, `Ctrl+Z`, `Ctrl+R`.
- Arrow key navigation: maintain a `_focusedIndex` in `LibraryController` (or `_HomeScreenState`) that maps to `filteredBooks`; `↑`/`↓` update it and call `selectBook`.

## Implementation Plan
1. Define `ApplyIntent`, `UndoIntent`, `RescanIntent`, `NavigateUpIntent`, `NavigateDownIntent`, `FocusSearchIntent`, `ClearSearchIntent` as `Intent` subclasses
2. Wrap `HomeScreen.build` body in a `Shortcuts` widget mapping `LogicalKeySet` → intent
3. Register `Actions` handlers at the same level; each handler delegates to the appropriate `_ctrl` method or `_searchCtrl` operation
4. For `NavigateUpIntent`/`NavigateDownIntent`: compute the current index in `_ctrl.filteredBooks` and call `_ctrl.selectBook` with the adjacent entry; scroll the `ListView` to keep the selection visible using a `ScrollController`
5. Add a `?` `IconButton` in the toolbar that shows an `AlertDialog` listing all shortcuts
6. Ensure `Ctrl+S` is suppressed when `_applying` is true (same guard as the Apply button)

## Files Impacted
- `lib/main.dart` — `Shortcuts` + `Actions` wiring, `ScrollController`, `?` help button
- `lib/controllers/library_controller.dart` — expose `selectBookByIndex` or similar
- `CHANGELOG.md`
