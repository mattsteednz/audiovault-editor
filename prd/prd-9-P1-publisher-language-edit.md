# PRD-9 (P1): Editable publisher and language fields

## Problem
Publisher and language are read from file tags and OPF but rendered as read-only `_metaRow` labels in `BookDetailScreen`. Users cannot correct or set them, and Apply never writes them back to audio files or OPF.

## Evidence
- `_buildMetadata` calls `_metaRow('Publisher', ...)` and `_metaRow('Language', ...)` — not `_editableRow`
- `_writeMetadataMp3` writes no publisher or language frame
- `_writeMetadataMp4` writes no publisher or language atom
- `exportOpf` already emits `<dc:publisher>` and `<dc:language>` — they just never change

## Proposed Solution
- Promote publisher and language to editable `TextEditingController` fields alongside the existing ones
- On Apply, write publisher to MP3 `TPUB` frame and MP4 `©pub` atom; write language to MP3 `TLAN` frame and MP4 `©lan` atom
- Include both in OPF export (already done — no change needed there)
- Batch edit panel gains Publisher and Language fields

## Acceptance Criteria
- [ ] Publisher and Language show as editable text fields in the detail panel
- [ ] Editing either field marks the book dirty and enables Apply
- [ ] Apply writes publisher/language to MP3 and M4B/M4A files
- [ ] Apply writes publisher/language to `metadata.opf`
- [ ] Batch edit panel includes Publisher and Language
- [ ] Undo restores previous publisher/language values

## Out of Scope
- Language validation / ISO 639 picker

## Implementation Plan
1. `BookDetailScreen`: add `_publisherCtrl` and `_languageCtrl`; wire `_initControllers`, `_disposeControllers`, `_onChanged`, and `_apply` the same way as existing fields
2. `_buildMetadata`: replace the two `_metaRow` calls with `_editableRow`
3. `MetadataWriter._writeMetadataMp3`: add `TPUB` and `TLAN` frames to `newFrames`; add both to `stripIds`
4. `MetadataWriter._writeMetadataMp4` / `_injectTextAtomsInMoov`: add `©pub` and `©lan` atoms
5. `Audiobook.copyWith`: add `publisher` and `language` parameters (currently missing from `copyWith`)
6. `BatchEditScreen`: add publisher and language controllers + fields; apply same skip-if-blank logic

## Files Impacted
- `lib/models/audiobook.dart` — add `publisher`/`language` to `copyWith`
- `lib/screens/book_detail_screen.dart` — two new controllers + editable rows
- `lib/screens/batch_edit_screen.dart` — two new fields
- `lib/services/metadata_writer.dart` — write TPUB/TLAN and ©pub/©lan
- `CHANGELOG.md`
