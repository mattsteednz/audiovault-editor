# Changelog

## [Unreleased]

## [1.1.0] - 2025-07-14

### Changed
- Extracted `LibraryController` (`ChangeNotifier`) from `_HomeScreenState` — all scanning, undo, dirty-tracking, batch selection, search, and sort logic now lives in `lib/controllers/library_controller.dart`
- Split `MetadataWriter` (700+ line static class) into format-specific writers: `Mp3Writer`, `Mp4Writer`, `FlacWriter`, `OggWriter` under `lib/services/writers/`; `MetadataWriter` is now a thin orchestrator
- `Audiobook.copyWith` now uses the sentinel pattern — all nullable fields can be explicitly cleared to `null`
- Replaced hand-rolled `_base64Encode` in OGG cover embedding with `dart:convert`'s `base64Encode`
- All intra-`lib/` imports converted to `package:` imports per `always_use_package_imports` lint rule
- `ScannerService.naturalSortCompare` promoted to public static for testability

### Fixed
- Redundant `Endian.big` arguments removed from `ByteData.getUint32` calls (big-endian is the default)
- Unnecessary `await` on tail-call returns in M4B chapter parser removed
- Redundant `start: null` argument removed from `_ChapterRow` constructor

### Added
- `analysis_options.yaml` — 12 additional lint rules enabled: `prefer_single_quotes`, `avoid_print`, `always_use_package_imports`, `cancel_subscriptions`, `close_sinks`, `avoid_dynamic_calls`, `prefer_const_constructors`, `prefer_const_declarations`, `unnecessary_await_in_return`, `use_string_buffers`, `avoid_redundant_argument_values`, `noop_primitive_operations`
- `.amazonq/rules/code-quality.md` — project coding standards for state management, models, services, error handling, testing, and linting
- Unit tests: `test/models/audiobook_test.dart` (10 `copyWith` round-trip tests), `test/services/mp3_writer_test.dart` (5 syncsafe integer tests), `test/services/opf_parser_test.dart` (9 OPF parsing tests), `test/services/scanner_service_test.dart` (5 natural sort tests)

### Fixed
- Toggle between OPF/merged and File tags no longer marks the form dirty
- `_dirtyPaths` in sidebar now correctly shows orange dot when a book has unsaved changes
- Export metadata now includes subtitle field in `metadata.opf`
- Apply button shows a loading spinner while writing; errors surface in a SnackBar instead of being silently swallowed
- Cover embed and metadata write errors are now reported per-file

### Added
- Rescan button — re-reads the book folder from disk; prompts to discard unsaved changes if any exist
- Search field in sidebar — filters by title or author in real time
- Sort menu in sidebar — Title A–Z / Z–A, Author A–Z / Z–A
- Series and Series # editable fields in metadata panel; written to `metadata.opf` on Apply
- Description editable field (multiline); written to COMM (MP3) and `©cmt` (M4B) on Apply
- Export split into separate OPF and cover.jpg actions via dropdown
- Undo button — restores and re-writes the previous metadata after an Apply
- Window title shows `AudioVault Editor — <folder name>` when a library is open
- Batch editing — check 2+ books to open a batch edit panel; applies Author, Narrator, Published, Series, Series # to all selected books; blank fields are skipped
- Apply now always exports `metadata.opf` to keep it in sync with audio file tags

## [1.0.0] - 2025-04-21

### Added
- Library scanning — recursively finds audiobooks up to three levels deep (flat, author-grouped, author+series); reads `metadata.opf` for richer metadata
- Metadata editing — editable title, author, narrator, and published date with unsaved-change tracking
- Chapter editing — view and rename chapters from M4B embedded tracks, CUE sheets, or multi-file MP3 collections
- Cover art — drag and drop a new image onto the book; converted to JPEG on Apply and embedded into each audio file
  - MP3: ID3v2 APIC frame
  - M4B / M4A: MP4 `covr` atom
  - FLAC: `METADATA_BLOCK_PICTURE` block
  - OGG: Vorbis comment `METADATA_BLOCK_PICTURE`
- Text metadata writing — title, author, narrator, year written into audio files on Apply
  - MP3: TIT2, TPE1, TPE2, TYER ID3 frames
  - M4B / M4A: `©nam`, `©ART`, `©wrt`, `©day` iTunes atoms
- Export metadata — writes `metadata.opf` (Calibre-compatible) and `cover.jpg` to the book folder
- Unsaved change indicator — orange dot in sidebar for books with pending edits; Apply only enabled when something has changed
