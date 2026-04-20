# Changelog

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
