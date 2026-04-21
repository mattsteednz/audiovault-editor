# PRD-14 (P2): Genre / tags field

## Problem
Genre is a standard metadata field in every audio format (ID3 `TCON`, MP4 `©gen`, Vorbis `GENRE`) and is used by audiobook players and library managers to categorise books. The app reads no genre data and provides no way to set it.

## Evidence
- `Audiobook` model has no `genre` field
- `ScannerService` reads no genre tag from any format
- `MetadataWriter` writes no genre tag
- `opf_parser.dart` reads no `dc:subject` element (the OPF equivalent of genre)

## Proposed Solution
- Add a `genre` field to `Audiobook`
- Read genre from file tags on scan (MP3 `TCON`, MP4 `©gen`, Vorbis `GENRE`) and from OPF `<dc:subject>`
- Add an editable `Genre` row in `BookDetailScreen`
- On Apply, write genre to MP3 `TCON`, MP4 `©gen`, and OPF `<dc:subject>`
- Include genre in batch edit

## Acceptance Criteria
- [ ] Genre is read from file tags and OPF on scan
- [ ] Genre field is editable in the detail panel
- [ ] Apply writes genre to MP3 and M4B/M4A files and to `metadata.opf`
- [ ] Batch edit includes a Genre field
- [ ] Empty genre field on Apply clears the tag (writes empty string, consistent with other fields)

## Out of Scope
- Genre autocomplete / controlled vocabulary
- Multiple genres per book

## Implementation Plan
1. `Audiobook`: add `genre` field and `genre` parameter to `copyWith`
2. `ScannerService._scanSubfolder`: read `TCON` from `Mp3Metadata`, `©gen` from `Mp4Metadata`, `GENRE` from `VorbisMetadata`; store as `fileGenre`; OPF wins if present
3. `opf_parser.dart`: read `<dc:subject>` as genre
4. `MetadataWriter._writeMetadataMp3`: add `TCON` frame; add to `stripIds`
5. `MetadataWriter._writeMetadataMp4` / `_injectTextAtomsInMoov`: add `©gen` atom
6. `MetadataWriter.exportOpf`: emit `<dc:subject>` when genre is set
7. `BookDetailScreen`: add `_genreCtrl`, wire into `_initControllers` / `_apply` / `_onChanged`; add `_editableRow('Genre', _genreCtrl)`
8. `BatchEditScreen`: add genre field

## Files Impacted
- `lib/models/audiobook.dart`
- `lib/services/scanner_service.dart`
- `lib/services/opf_parser.dart`
- `lib/services/metadata_writer.dart`
- `lib/screens/book_detail_screen.dart`
- `lib/screens/batch_edit_screen.dart`
- `CHANGELOG.md`
