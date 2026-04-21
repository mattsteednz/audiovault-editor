# PRD-27 (P1): Write metadata tags to FLAC and OGG files

## Problem
`MetadataWriter.applyMetadata` only handles MP3 and M4B/M4A/AAC. When a library contains FLAC or OGG files, hitting Apply silently skips all text tag writes for those files — title, author, narrator, publisher, language, genre, and description are never updated on disk. Cover art already works for both formats (via `FlacWriter.embedCover` and `OggWriter.embedCover`), but text tags do not.

## Evidence
- `MetadataWriter.applyMetadata` has branches for `.mp3` and `.m4b/.m4a/.aac` only; FLAC and OGG fall through with no write
- `FlacWriter` has only `embedCover` — no `writeMetadata` method
- `OggWriter` has only `embedCover` — no `writeMetadata` method
- `ScannerService` reads text tags from `VorbisMetadata` (used by both FLAC and OGG) but nothing writes them back

## Proposed Solution
- Add `FlacWriter.writeMetadata(String filePath, Audiobook book)` that rewrites the `VORBIS_COMMENT` metadata block with updated text fields
- Add `OggWriter.writeMetadata(String filePath, Audiobook book)` that rewrites the Vorbis comment packet in the OGG stream with updated text fields
- Wire both into `MetadataWriter.applyMetadata` under `.flac` and `.ogg` branches

### FLAC Vorbis comment fields
| Audiobook field | Vorbis comment key |
|---|---|
| title | `ALBUM` |
| author | `ARTIST` |
| narrator | `PERFORMER` |
| releaseDate | `DATE` |
| description | `COMMENT` |
| publisher | `ORGANIZATION` |
| language | `LANGUAGE` |
| genre | `GENRE` |

### OGG Vorbis comment fields
Same mapping as FLAC — both use the Vorbis comment spec.

## Acceptance Criteria
- [ ] Apply writes all supported text fields to FLAC files
- [ ] Apply writes all supported text fields to OGG files
- [ ] Existing cover art in FLAC/OGG files is preserved after a metadata write
- [ ] A rescan after Apply shows the updated values for FLAC/OGG books
- [ ] Write errors for FLAC/OGG files surface in the existing error SnackBar

## Out of Scope
- Writing chapter data to FLAC/OGG
- Writing cover art as part of `writeMetadata` (cover is handled separately by `embedCover`)

## Implementation Plan
1. `FlacWriter.writeMetadata(String filePath, Audiobook book)`:
   - Read file bytes; verify `fLaC` marker
   - Walk metadata blocks; find the `VORBIS_COMMENT` block (type 4)
   - Build a new Vorbis comment block: vendor string preserved, replace/add known keys, preserve unknown keys
   - Rewrite the file using the existing `_rewriteMetadata` pattern (strip old type-4 block, inject new one before the last block)
2. `OggWriter.writeMetadata(String filePath, Audiobook book)`:
   - Reuse the existing `_rewriteVorbisCommentPacket` infrastructure
   - Instead of only replacing `METADATA_BLOCK_PICTURE`, replace/add all known text comment keys; preserve unknown keys
   - Expose a `writeMetadata` entry point that calls `_rewriteCover`-style page rewriting with the updated packet
3. `MetadataWriter.applyMetadata`: add `else if (ext == '.flac')` → `FlacWriter.writeMetadata` and `else if (ext == '.ogg')` → `OggWriter.writeMetadata`
4. Unit tests:
   - Build a minimal FLAC byte sequence with a `VORBIS_COMMENT` block; call `writeMetadata`; parse back and assert field values
   - Build a minimal OGG page with a Vorbis comment packet; call `writeMetadata`; parse back and assert field values
   - Assert that existing PICTURE blocks are preserved after a metadata-only write

## Files Impacted
- `lib/services/writers/flac_writer.dart` — add `writeMetadata`
- `lib/services/writers/ogg_writer.dart` — add `writeMetadata`
- `lib/services/metadata_writer.dart` — add FLAC/OGG branches in `applyMetadata`
- `test/services/flac_writer_test.dart` (new)
- `test/services/ogg_writer_test.dart` (new)
- `CHANGELOG.md`
