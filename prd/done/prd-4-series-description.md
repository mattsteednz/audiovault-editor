# PRD-4 (P2): Series and description editing

## Problem
Series name, series index, and description are read from OPF and displayed as read-only. They cannot be edited in the UI, so users must manually edit `metadata.opf` to change them.

## Evidence
- `_buildMetadata` renders series as `_metaRow` (read-only `SelectableText`)
- Description is not shown at all in the UI
- `copyWith` on `Audiobook` does not include series or description

## Proposed Solution
- Add editable fields for Series, Series Index (numeric), and Description (multiline) to the metadata panel
- On Apply, write series/index to `metadata.opf` via `exportOpf` and description to audio file tags
- Series and description are OPF-only fields — no audio tag equivalent for series; description maps to `dc:description` in OPF and comment tags in audio files

## Decision Points
- Series index: text field with numeric keyboard; stored as `int?` — validate on apply, ignore non-numeric input
- Description: multiline `TextField` with max 4 visible lines; scrollable
- Writing description to audio files: MP3 COMM frame, MP4 `©cmt` atom — implement in `MetadataWriter`
- `Audiobook.copyWith` needs `series`, `seriesIndex`, `description` added

## Acceptance Criteria
- [ ] Series, Series Index, and Description are editable in the metadata panel
- [ ] Changes are tracked by the dirty indicator
- [ ] Apply writes series/index to `metadata.opf` and description to audio files
- [ ] Invalid series index (non-numeric) is silently ignored on apply

## Out of Scope
- Writing series to audio file tags (no standard tag for this)

## Implementation Plan
1. Add `series`, `seriesIndex`, `description` to `Audiobook.copyWith`
2. Add controllers `_seriesCtrl`, `_seriesIndexCtrl`, `_descriptionCtrl` to `_BookDetailScreenState`
3. Add editable rows to `_buildMetadata` for Series, Series #, Description (multiline)
4. Include in dirty check and originals reset
5. In `_apply`: call `MetadataWriter.exportOpf` with updated series/index; write description via `applyMetadata`
6. Add `©cmt` MP4 atom and COMM ID3 frame to `MetadataWriter._writeMetadataMp4` / `_writeMetadataMp3`

## Files Impacted
- `lib/models/audiobook.dart` — extend `copyWith`
- `lib/screens/book_detail_screen.dart` — new controllers + rows
- `lib/services/metadata_writer.dart` — description writing + OPF call from apply
- `CHANGELOG.md`
