# PRD-31 (P2): Quick Edit mode toggle (names-only / timestamps-only / both)

## Problem
When a user wants to rename chapters via copy-paste, the Quick Edit dialog forces them to work with both titles and timestamps on the same line (e.g. `Chapter 1, 00:01:23`). This makes bulk renaming awkward: pasting a plain list of names from an external source requires manually re-appending every timestamp, and a single misplaced comma can corrupt a timestamp and block saving.

The inverse is also true: a user who only wants to nudge timestamps has to scroll past long titles to reach the values they care about.

## Evidence
- `_openQuickEdit` in `ChapterEditor` passes `includeTimestamps: _isSingleFile` — timestamps are always included for single-file books, never for multi-file books. There is no user control.
- `ChapterEditorController.toQuickEditText(bool includeTimestamps)` and `parseQuickEditText(String text, bool expectTimestamps)` already accept a flag, so the serialisation layer is ready.
- `QuickEditDialog` receives `includeTimestamps` as a constructor parameter but never exposes it to the user.

## Proposed Solution
Add a segmented toggle inside `QuickEditDialog` that lets the user switch between three modes:

| Mode | Label | Text format |
|------|-------|-------------|
| Names only | **Names** | `Chapter Title` |
| Both (default for single-file) | **Names + Times** | `Chapter Title, HH:MM:SS` |
| Times only | **Times** | `HH:MM:SS` |

**Behaviour rules:**
- Default mode is **Names + Times** for single-file books (preserving current behaviour) and **Names** for multi-file books.
- Switching modes re-serialises the current in-memory parse result into the new format — unsaved edits in the text field are preserved where possible (titles carry over when switching to/from Names; timestamps carry over when switching to/from Times).
- In **Names only** mode: the text field shows one title per line; saving merges the new titles back onto the existing timestamp list (timestamps are untouched).
- In **Times only** mode: the text field shows one timestamp per line; saving merges the new timestamps back onto the existing title list (titles are untouched).
- In **Names + Times** mode: existing behaviour — both fields editable, both validated.
- The hint text below the title updates to reflect the active mode.
- Error/conflict validation only applies to the fields visible in the current mode (e.g. timestamp conflicts are not checked in Names-only mode).

## Acceptance Criteria
- [ ] A segmented control with three options (Names / Names + Times / Times) appears in the Quick Edit dialog header.
- [ ] Default selection is **Names + Times** for single-file books and **Names** for multi-file books.
- [ ] Switching to **Names only** re-renders the text area with one title per line; timestamps are hidden.
- [ ] Switching to **Times only** re-renders the text area with one timestamp per line; titles are hidden.
- [ ] Switching back to **Names + Times** reconstructs the combined format from the last parsed state.
- [ ] Saving in **Names only** mode updates chapter titles without altering start times.
- [ ] Saving in **Times only** mode updates start times without altering chapter titles.
- [ ] Timestamp conflict detection is suppressed in **Names only** mode.
- [ ] Format error detection is suppressed in **Times only** mode for the title column (only timestamp format is validated).
- [ ] The hint text reflects the active mode.
- [ ] Existing **Names + Times** behaviour is unchanged.

## Out of Scope
- Persisting the last-used mode across dialog opens (always resets to default).
- Adding a mode for multi-file books that shows timestamps (multi-file books have no meaningful start times in the editor).

## Implementation Plan

### 1. Add `QuickEditMode` enum
In `quick_edit_dialog.dart` (or a shared location):
```dart
enum QuickEditMode { namesOnly, both, timesOnly }
```

### 2. Extend `ChapterEditorController` serialisation
Add two new helpers alongside `toQuickEditText`:
- `toNamesOnlyText()` — one title per line (already equivalent to `toQuickEditText(false)`, so this can be an alias).
- `toTimesOnlyText()` — one `HH:MM:SS` per line.
- `parseTimesOnlyText(String text, List<ChapterEntry> existing)` — parses one timestamp per line and merges with `existing` titles; returns entries + errorLines.

### 3. Update `QuickEditDialog`
- Add `QuickEditMode _mode` state, initialised from `widget.includeTimestamps` (true → `both`, false → `namesOnly`).
- Add a `SegmentedButton<QuickEditMode>` in the title row (or just below it).
- On mode change: parse the current text field content with the *old* mode to extract the latest entries, then re-serialise with the new mode into the text field.
- Update `_parseNow` to dispatch to the correct parse method based on `_mode`.
- Update `_save` to merge correctly based on `_mode`:
  - `namesOnly`: call `onSave` with titles from parse + starts from `_originalEntries`.
  - `timesOnly`: call `onSave` with starts from parse + titles from `_originalEntries`.
  - `both`: existing behaviour.
- Store `_originalEntries` (the entries at dialog open time) so merges always have a clean base.

### 4. Update hint text
Replace the static hint string with a switch on `_mode`.

### 5. No changes needed to `ChapterEditorController.replaceAll` or `_openQuickEdit` — the dialog handles everything internally.

## Files Impacted
- `lib/widgets/quick_edit_dialog.dart` — mode toggle, mode-aware parse/save
- `lib/widgets/chapter_editor.dart` — add `toTimesOnlyText` / `parseTimesOnlyText` to `ChapterEditorController`
- `CHANGELOG.md`
