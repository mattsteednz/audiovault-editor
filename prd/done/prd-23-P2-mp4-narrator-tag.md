# PRD-23 (P2): Correct MP4 narrator tag

## Problem
`Mp4Writer` writes the narrator to the `©wrt` atom (composer), which is semantically wrong and causes the narrator to appear in the "Composer" field of players like VLC and iTunes rather than a narrator or performer field. Additionally, `ScannerService` does not read any narrator value from MP4 file tags — so for M4B books without an OPF, the narrator field is always blank after a scan.

## Evidence
- `Mp4Writer._injectTextAtomsInMoov` uses `©wrt` for narrator
- `ScannerService` reads `Mp4Metadata` but only extracts `album` (title), `artist` (author), `year` (date), and `genre` — no narrator field
- The `audio_metadata_reader` package exposes `Mp4Metadata` with no dedicated narrator field; the closest standard atom is `©wrt` (composer) or a custom `----:com.apple.iTunes:NARRATOR` freeform atom

## Proposed Solution
- Write narrator to both `©wrt` (composer, for broad player compatibility) and a freeform iTunes atom `----:com.apple.iTunes:NARRATOR` (for players that support it, e.g. Prologue, Overcast)
- On scan, read narrator from `©wrt` as a fallback when no OPF is present; document that this may show "Composer" in some players
- Update the scanner to attempt reading the freeform `NARRATOR` atom if `audio_metadata_reader` exposes raw atoms; fall back to `©wrt` if not

## Acceptance Criteria
- [ ] Apply writes narrator to `©wrt` in M4B/M4A files
- [ ] Apply also writes narrator to `----:com.apple.iTunes:NARRATOR` freeform atom
- [ ] Scanner reads narrator from `©wrt` for M4B/M4A files when no OPF is present
- [ ] Narrator survives a round-trip: scan → Apply → Rescan for M4B books
- [ ] No regression for MP3 or FLAC narrator handling

## Out of Scope
- Reading freeform atoms via `audio_metadata_reader` if the package does not expose them (document as a known limitation)
- Writing narrator to AAC files (AAC metadata write is not supported)

## Decision Points
- `©wrt` is the most widely supported atom for a "secondary creator" role in M4B players. The freeform atom is additive and does not break compatibility.
- If `audio_metadata_reader` does not expose freeform atoms, the scanner will read `©wrt` only. This is acceptable since OPF is the authoritative source when present.

## Implementation Plan
1. `Mp4Writer._injectTextAtomsInMoov`: keep `©wrt` for narrator; add a freeform atom builder `_buildFreeformAtom('NARRATOR', value)` and include it in the atoms list
2. Add `Mp4Writer._buildFreeformAtom(String name, String value)` that constructs a `----` atom with `mean` = `com.apple.iTunes` and `name` = the given name
3. `ScannerService`: in the `Mp4Metadata` branch, attempt to read narrator from `Mp4Metadata` — check if the package exposes a `composer` or `writer` field; if so, use it as `fileNarrator` for M4B/M4A
4. Unit test: build a minimal M4B byte sequence, write narrator via `Mp4Writer.writeMetadata`, parse back and assert `©wrt` contains the narrator value

## Files Impacted
- `lib/services/writers/mp4_writer.dart` — add freeform atom builder; keep `©wrt`
- `lib/services/scanner_service.dart` — read narrator from MP4 tags
- `test/services/mp4_writer_test.dart` (new or extend existing)
- `CHANGELOG.md`
