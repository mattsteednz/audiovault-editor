# PRD-15 (P2): Multiple authors / contributors

## Problem
Many audiobooks have multiple authors (e.g. co-written books) or multiple narrators. The current model stores a single `author` and `narrator` string. When a book has multiple `dc:creator` entries in its OPF, only the first author and first narrator are kept; the rest are silently dropped.

## Evidence
- `opf_parser.dart` uses `if (role == 'aut' && author == null) author = text` — takes only the first
- `Audiobook` has `author` and `narrator` as single nullable strings
- `MetadataWriter` writes a single `TPE1` / `©ART` value

## Proposed Solution
- Keep the existing `author` and `narrator` single-string fields as the "display" / primary value (no breaking change to the rest of the app)
- Store additional authors in a new `additionalAuthors` list and additional narrators in `additionalNarrators`
- In `BookDetailScreen`, show a secondary read-only row "Also by:" when `additionalAuthors` is non-empty, and "Also narrated by:" for narrators
- On Apply, write all authors as multiple `TPE1` frames (ID3v2.4 allows multiple) and multiple `dc:creator` entries in OPF
- Batch edit is unaffected (operates on primary author/narrator only)

## Acceptance Criteria
- [ ] OPF with multiple `dc:creator aut` entries preserves all authors in the model
- [ ] Detail panel shows "Also by:" row when additional authors exist
- [ ] Apply writes all authors to OPF; primary author written to audio file tags
- [ ] No regression for single-author books

## Out of Scope
- Editing additional authors in the UI (read-only display for now)
- Writing multiple authors to audio file tags (primary only)

## Implementation Plan
1. `Audiobook`: add `additionalAuthors` (`List<String>`) and `additionalNarrators` (`List<String>`) fields, defaulting to `const []`; add to `copyWith`
2. `opf_parser.dart`: collect all `aut` creators into a list; first → `author`, rest → `additionalAuthors`; same for `nrt`
3. `BookDetailScreen._buildMetadata`: after the Author row, if `additionalAuthors.isNotEmpty`, add a `_metaRow('Also by', book.additionalAuthors.join(', '))`; same for narrators
4. `MetadataWriter.exportOpf`: emit one `<dc:creator opf:role="aut">` per author (primary + additional)

## Files Impacted
- `lib/models/audiobook.dart`
- `lib/services/opf_parser.dart`
- `lib/screens/book_detail_screen.dart`
- `lib/services/metadata_writer.dart` (OPF export only)
- `CHANGELOG.md`
