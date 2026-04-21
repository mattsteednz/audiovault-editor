# PRD-21 (P1): Tabbed detail layout — Book / Chapters

## Problem
The detail panel is overcrowded: cover art, 12+ editable fields, action buttons, and the chapter table all compete for vertical space. On smaller screens the chapter table is barely visible. The editable metadata and the chapter list serve different workflows and don't need to be visible simultaneously.

## Proposed Solution
Replace the current single-scroll layout with a two-tab view below the header:

### Header (always visible)
- Cover art (with drag-drop + browse button, unchanged)
- Read-only summary block:
  - **Title:** `{title}: {subtitle} ({year})` — omit parts that are empty
  - **Author:** primary author
  - **Narrated by:** primary narrator
  - **Duration:** formatted as now
  - **Files:** formatted as now (e.g. "12 × MP3")
  - **Metadata:** chips/labels showing which sources were found: `embedded`, `metadata.opf`, `cue`
- These fields update live when the user edits them on the Book tab, but are not editable themselves.

### Action bar (always visible, unchanged)
OPF/File toggle, Export, Undo, Rescan, Apply, unsaved indicator.

### Tabs
- **Book** — all editable fields (title, subtitle, author, narrator, published, series, series #, publisher, language, genre, description) plus the read-only additional-authors, additional-narrators, ID rows.
- **Chapters** — the chapter DataTable, unchanged.

## Acceptance Criteria
- [ ] Two tabs labelled "Book" and "Chapters" appear below the action bar
- [ ] Book tab contains all editable metadata fields
- [ ] Chapters tab contains the chapter table
- [ ] Header shows read-only summary that updates live from edit controllers
- [ ] Metadata sources row shows which sources were detected during scan
- [ ] No regression: Apply, Undo, Rescan, Export, dirty tracking all work as before

## Out of Scope
- Reordering or grouping fields within the Book tab
- Third tab for raw file tags

## Implementation Plan
1. Add `hasOpf`, `hasCue`, `hasEmbeddedTags` booleans to `Audiobook` model (set during scan)
2. `ScannerService`: set the new flags based on what was found
3. `BookDetailScreen`: refactor `build` to use header + `TabBar`/`TabBarView`
4. Move editable fields into Book tab, chapter table into Chapters tab
5. Header summary reads from controllers (live) via `_titleCtrl.text` etc.

## Files Impacted
- `lib/models/audiobook.dart`
- `lib/services/scanner_service.dart`
- `lib/screens/book_detail_screen.dart`
- `CHANGELOG.md`
