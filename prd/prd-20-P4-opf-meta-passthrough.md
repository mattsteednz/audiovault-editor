# PRD-20 (P4): OPF custom `<meta>` passthrough

## Problem
Calibre and other tools write arbitrary `<meta name="..." content="..."/>` elements to `metadata.opf` (e.g. `calibre:rating`, `calibre:timestamp`, `calibre:title_sort`, custom columns). When the app re-exports the OPF on Apply it only writes the fields it knows about, silently dropping all other `<meta>` elements.

## Evidence
- `MetadataWriter.exportOpf` builds the OPF from scratch using only the fields in `Audiobook`
- `opf_parser.dart` reads only `calibre:series` and `calibre:series_index` from `<meta>` elements; all others are discarded
- No `unknownMeta` or passthrough field exists on `Audiobook`

## Proposed Solution
- Parse all `<meta name="..." content="..."/>` elements in `opf_parser.dart` into a `Map<String, String>` stored as `Audiobook.opfMeta`
- Remove the keys the app manages (`calibre:series`, `calibre:series_index`) from the map so they are not duplicated
- In `MetadataWriter.exportOpf`, emit the remaining entries from `opfMeta` after the known fields

## Acceptance Criteria
- [ ] Unknown `<meta>` elements from the original OPF are preserved on re-export
- [ ] Known fields (`calibre:series`, `calibre:series_index`) are not duplicated
- [ ] Books without an OPF are unaffected
- [ ] Round-trip test: parse an OPF with custom meta → export → parse again → custom meta unchanged

## Out of Scope
- Editing unknown meta fields in the UI
- Passthrough of unknown `<dc:*>` elements

## Implementation Plan
1. `Audiobook`: add `opfMeta` (`Map<String, String>`) field, default `const {}`; add to `copyWith`
2. `opf_parser.dart`: collect all `<meta>` name/content pairs into a map; remove `calibre:series` and `calibre:series_index` keys; store remainder in `OpfMetadata.opfMeta`
3. `ScannerService`: pass `opf.opfMeta` through to `Audiobook`
4. `MetadataWriter.exportOpf`: after the known `<meta>` elements, iterate `book.opfMeta` and emit each entry
5. Unit test: parse OPF with `calibre:rating` and `calibre:timestamp`, export, parse again, assert both keys present with original values

## Files Impacted
- `lib/models/audiobook.dart`
- `lib/services/opf_parser.dart`
- `lib/services/scanner_service.dart`
- `lib/services/metadata_writer.dart`
- `test/services/opf_passthrough_test.dart` (new)
- `CHANGELOG.md`
