# PRD-10 (P1): Cover art browse button

## Problem
The only way to set a new cover is to drag and drop an image file onto the cover widget. There is no file-picker button, which makes the feature inaccessible to users who cannot drag files (e.g. when the library is on a network drive opened via a file dialog, or when using keyboard-only navigation).

## Evidence
- `_buildCover` in `BookDetailScreen` wraps the cover in a `DropTarget` only — no button
- `file_picker` is already a dependency (`pubspec.yaml`) and used for folder picking in `main.dart`

## Proposed Solution
- Add a small "Browse…" icon button overlaid on the cover widget (bottom-left corner, similar to the existing "pending" badge position)
- Tapping it opens `FilePicker.platform.pickFiles` filtered to image types
- The picked path is treated identically to a drag-and-drop result: stored in `_pendingCoverPath`, marks dirty, shows "pending" badge

## Acceptance Criteria
- [ ] A browse icon button is visible on the cover widget
- [ ] Tapping it opens a file picker filtered to jpg/jpeg/png/webp
- [ ] Picking a file sets `_pendingCoverPath` and marks the book dirty
- [ ] Drag-and-drop continues to work unchanged
- [ ] Button is disabled while `_applying`

## Out of Scope
- Fetching cover art from the internet

## Implementation Plan
1. In `_buildCover`, add a `Positioned` `IconButton` (bottom-left) with `Icons.folder_open`
2. On tap: call `FilePicker.platform.pickFiles(type: FileType.image)` and, if a file is returned, set `_pendingCoverPath` and call `_onChanged()`
3. Disable the button when `_applying` is true

## Files Impacted
- `lib/screens/book_detail_screen.dart`
- `CHANGELOG.md`
