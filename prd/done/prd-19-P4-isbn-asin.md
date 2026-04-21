# PRD-19 (P4): ISBN / ASIN identifier field

## Problem
Audiobook metadata standards (OPF, Audible, library systems) commonly include an ISBN or ASIN identifier. The app has no field for identifiers, so books imported from Calibre or Audible lose their identifier when the OPF is re-exported.

## Evidence
- `Audiobook` model has no identifier field
- `opf_parser.dart` does not read `<dc:identifier>` elements
- `MetadataWriter.exportOpf` does not emit `<dc:identifier>`

## Proposed Solution
- Add an `identifier` field to `Audiobook` (stores the raw value, e.g. `"isbn:9781234567890"` or `"asin:B001234567"`)
- Read the first `<dc:identifier>` from OPF on scan
- Show a read-only `_metaRow('ID', ...)` in the detail panel (editing identifiers is an edge case; promote to editable in a follow-up if requested)
- Preserve the identifier in OPF re-export so it is not lost on Apply

## Acceptance Criteria
- [ ] `<dc:identifier>` is read from OPF and stored in `Audiobook.identifier`
- [ ] Identifier is shown as a read-only row in the detail panel when present
- [ ] `exportOpf` emits `<dc:identifier>` when the field is set
- [ ] Identifier survives a round-trip: scan → Apply → rescan

## Out of Scope
- Editing the identifier in the UI
- Writing identifier to audio file tags (no standard field)
- Multiple identifiers

## Implementation Plan
1. `Audiobook`: add `identifier` (`String?`) field; add to `copyWith`
2. `opf_parser.dart`: read first `<dc:identifier>` element; store raw inner text
3. `MetadataWriter.exportOpf`: emit `<dc:identifier>${_xmlEscape(book.identifier!)}</dc:identifier>` when set
4. `BookDetailScreen._buildMetadata`: add `_metaRow('ID', widget.book.identifier)`

## Files Impacted
- `lib/models/audiobook.dart`
- `lib/services/opf_parser.dart`
- `lib/services/metadata_writer.dart`
- `lib/screens/book_detail_screen.dart`
- `CHANGELOG.md`
