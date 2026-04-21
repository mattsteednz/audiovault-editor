# PRD-22 (P2): Fix subtitle / description OPF conflict

## Problem
`MetadataWriter.exportOpf` writes the subtitle as `<dc:description opf:file-as="subtitle">` and the description as `<dc:description>`. This is non-standard and fragile: the OPF spec has no `opf:file-as` attribute on `dc:description`, and Calibre/OverDrive use `<dc:description>` exclusively for the long description. When both fields are set, the OPF contains two `<dc:description>` elements, which most parsers will handle inconsistently. Additionally, `opf_parser.dart` does not read back the subtitle from OPF on rescan, so a round-trip loses the subtitle.

## Evidence
- `MetadataWriter.exportOpf` emits:
  ```xml
  <dc:description opf:file-as="subtitle">…subtitle…</dc:description>
  <dc:description>…description…</dc:description>
  ```
- `opf_parser.dart` reads `<dc:description>` as `description` only; no subtitle field is parsed from OPF
- After Apply → Rescan, the subtitle field is blank (read from file tags only, not OPF)
- MP3 writer uses `TIT3` for subtitle (correct); MP4 writer uses `©nam` for subtitle (non-standard — `©nam` is the track title, not subtitle)

## Proposed Solution
- **OPF subtitle**: use `<meta name="subtitle" content="…"/>` (Calibre convention) instead of the `dc:description` hack
- **OPF description**: keep `<dc:description>` for the long description only
- **OPF parser**: read `<meta name="subtitle">` into `OpfMetadata.subtitle`; exclude `subtitle` from the `opfMeta` passthrough map so it is not duplicated
- **MP4 subtitle atom**: change from `©nam` (track title) to `©st3` (subtitle, iTunes convention) or keep `©nam` but document the trade-off; update scanner to read it back consistently
- Round-trip test: scan → Apply → Rescan → subtitle and description both preserved

## Acceptance Criteria
- [ ] OPF export writes subtitle as `<meta name="subtitle" content="…"/>` not as `dc:description`
- [ ] OPF export writes description as `<dc:description>` only
- [ ] OPF parser reads `<meta name="subtitle">` back into the subtitle field
- [ ] Subtitle survives a round-trip: scan → Apply → Rescan
- [ ] Description survives a round-trip: scan → Apply → Rescan
- [ ] No duplicate `<dc:description>` elements in exported OPF

## Out of Scope
- Migrating existing OPF files that used the old `dc:description opf:file-as="subtitle"` format (they will be corrected on next Apply)

## Decision Points
- MP4 subtitle atom: `©st3` is the iTunes subtitle atom and is read by most players; `©nam` is the track title. Switch to `©st3` for subtitle and update the scanner to read `©st3` back. Document that some older players may not display `©st3`.
- `subtitle` key must be excluded from `opfMeta` passthrough (same pattern as `calibre:series`) to avoid duplication on re-export.

## Implementation Plan
1. `MetadataWriter.exportOpf`: replace the `dc:description opf:file-as="subtitle"` line with `<meta name="subtitle" content="…"/>` when `book.subtitle != null`
2. `opf_parser.dart`: in the `<meta>` parsing loop, handle `name == 'subtitle'` → set `subtitle`; add `subtitle` to the exclusion list alongside `calibre:series`
3. `ScannerService`: pass `opf.subtitle` through to `Audiobook.subtitle` (currently `subtitle` comes from file tags only — `fileSubtitle` — and OPF subtitle is never read)
4. `Mp4Writer._injectTextAtomsInMoov`: change subtitle atom key from `©nam` to `©st3`
5. `ScannerService`: read `©st3` atom for subtitle from `Mp4Metadata` (currently not read at all from MP4)
6. Round-trip integration test: build an `Audiobook` with both subtitle and description, export OPF, parse back, assert both fields match

## Files Impacted
- `lib/services/metadata_writer.dart` — OPF subtitle element + MP4 atom key
- `lib/services/opf_parser.dart` — read `<meta name="subtitle">`; exclude from passthrough
- `lib/services/scanner_service.dart` — pass OPF subtitle to Audiobook; read `©st3` from MP4
- `test/services/opf_parser_test.dart` — add subtitle round-trip case
- `CHANGELOG.md`
