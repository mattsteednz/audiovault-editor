# PRD-5 (P2): Split Export into Cover and OPF separately

## Problem
"Export metadata" always writes both `metadata.opf` and `cover.jpg`. Sometimes only one is needed — e.g. the user just wants to export a cover without touching the OPF, or wants to regenerate the OPF without overwriting a manually placed cover.

## Decision Points
- Replace the single "Export metadata" button with a dropdown/split button: "Export OPF" and "Export cover.jpg"
- Use a `MenuAnchor` or `PopupMenuButton` attached to the existing button to keep the toolbar compact
- "Export cover.jpg" is disabled if the book has no cover (no `coverImagePath` and no `coverImageBytes`)

## Acceptance Criteria
- [ ] Separate actions for exporting OPF and cover
- [ ] Export cover disabled when no cover is available
- [ ] Each shows its own success/error SnackBar

## Out of Scope
- Exporting to a custom path (always writes to the book folder)

## Implementation Plan
1. Replace `OutlinedButton.icon` for Export with a `PopupMenuButton` showing two items: "Export OPF" and "Export cover.jpg"
2. "Export cover.jpg" calls `MetadataWriter.exportCover`; disabled when no cover
3. "Export OPF" calls `MetadataWriter.exportOpf`
4. Each item has its own try/catch SnackBar

## Files Impacted
- `lib/screens/book_detail_screen.dart`
- `CHANGELOG.md`
