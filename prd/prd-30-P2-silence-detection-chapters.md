# PRD-30 (P2): Silence-Detection Chapter Generation

## Problem

Books imported without embedded chapters (e.g. a single M4B ripped from a CD, or a single MP3 with no CUE sheet) show an empty or single-entry chapter table. Users currently have no way to auto-generate chapter boundaries — they must enter every timestamp by hand.

## Evidence

- `_scanSubfolder` in `ScannerService` only reads chapters from embedded M4B atoms or CUE sheets; single-file books with neither source have `chapters = []`.
- `ChapterEditor` already supports full chapter editing for single-file books; it just has no way to seed the table automatically.
- ffmpeg's `silencedetect` filter is the standard tool for this task and is already used by tools like Beets and Audiobook Shelf.

## Proposed Solution

Add a **"Detect chapters"** button to the `ChapterEditor` toolbar (single-file books only). Clicking it opens a **Detect Chapters dialog** that:

1. Runs ffmpeg `silencedetect` on the audio file with configurable parameters.
2. Shows a live progress bar while scanning.
3. Previews the detected chapter count and a scrollable list of timestamps.
4. Lets the user accept or discard before touching the chapter table.
5. On accept, warns if existing chapters will be replaced, then populates the table (pushing to the undo stack).

---

## Scope

**Eligible books:** any single-file audiobook (`audioFiles.length == 1`), regardless of format (M4B, MP3, FLAC, OGG, M4A, etc.).

**Not in scope:** multi-file books — they already have natural chapter boundaries per file.

---

## ffmpeg Dependency

The app resolves ffmpeg at runtime by checking three locations in order:

1. **System PATH** — `ffmpeg` (or `ffmpeg.exe` on Windows) is on the user's PATH.
2. **App directory root** — `<exe_dir>/ffmpeg.exe` (i.e. placed next to the executable).
3. **App directory bin subfolder** — `<exe_dir>/ffmpeg/bin/ffmpeg.exe` (standard layout when extracting a full ffmpeg Windows build ZIP).

The first location that resolves to an executable file wins. `SilenceDetectionService.ffmpegPath` returns the resolved path, or `null` if none of the three locations yield a valid executable.

If ffmpeg cannot be found, the "Detect chapters" button is **disabled** with a tooltip:

> "ffmpeg not found. Add ffmpeg to your PATH, or place ffmpeg.exe (or ffmpeg/bin/ffmpeg.exe) next to audiovault_editor.exe."

No crash, no silent failure.

---

## UI: Button Placement

Add to the `ChapterEditor` toolbar, between the undo/redo group and the Quick Edit button:

```
[↩] [↪]   [Detect chapters ▾]   [Quick Edit]
```

The button is only rendered when `_isSingleFile` is true. It is disabled (greyed) when ffmpeg is unavailable.

---

## UI: Detect Chapters Dialog

### Default state

```
┌─────────────────────────────────────────────────────┐
│  Detect Chapters                                    │
│                                                     │
│  Noise floor   [-45 dB          ]                   │
│  Min silence   [1.5 s           ]                   │
│                                                     │
│  ▶ Advanced                                         │
│                                                     │
│  [Cancel]                    [Detect]               │
└─────────────────────────────────────────────────────┘
```

### Advanced section (expanded)

The "Advanced" disclosure row expands inline to show:

- **Noise floor** — dB value, range −90 to −20, default −45 dB.
  Label: `Noise floor (dB)`. Input: numeric text field.
- **Min silence duration** — seconds, range 0.1–10.0, default 1.5 s.
  Label: `Min silence (s)`. Input: numeric text field.

Both fields are also shown in the collapsed (default) state as the primary controls — "Advanced" in the default state is a no-op disclosure; it exists to signal that these are tunable parameters without overwhelming first-time users.

> **Refinement note:** Keep the UI simple — two fields is not overwhelming. The "Advanced" label signals "you can tune this" without hiding the controls behind a click. Both fields are always visible.

### Detecting state (progress)

After tapping **Detect**, the dialog transitions to a progress view:

```
┌─────────────────────────────────────────────────────┐
│  Detecting chapters…                                │
│                                                     │
│  ████████████░░░░░░░░░░░░░░░░░░  38%               │
│                                                     │
│  [Cancel]                                           │
└─────────────────────────────────────────────────────┘
```

**Progress calculation:** ffmpeg `silencedetect` emits lines like:
```
size=N time=HH:MM:SS.ss bitrate=...
```
Parse `time=` from stderr and divide by the book's known `duration` to get a 0–100% value. If `duration` is null, show an indeterminate spinner instead.

Cancel terminates the ffmpeg process immediately (`process.kill()`).

### Auto-retry on excessive chapters

If the detected chapter count exceeds **100**:

1. The dialog does **not** show the preview.
2. It automatically retries with progressively less sensitive parameters, stepping through:

   | Attempt | Noise floor | Min silence |
   |---------|-------------|-------------|
   | 1 (user) | user value | user value |
   | 2 | user value | user value × 2 |
   | 3 | user value | user value × 4 |
   | 4 | user value + 10 dB | user value × 2 |
   | 5 | user value + 10 dB | user value × 4 |

   Noise floor is clamped to −20 dB max. Min silence is clamped to 10 s max.

3. Each retry shows a status message:
   > "Found 143 chapters — adjusting parameters and retrying (attempt 2/5)…"

4. If all 5 attempts still exceed 100 chapters, show the result from the attempt with the fewest chapters and display a warning:
   > "⚠ Could not reduce below 100 chapters automatically. Showing best result (87 chapters). You may want to adjust the parameters manually."

5. The final auto-selected parameters are shown in the fields so the user can see what was used.

### Preview state

```
┌─────────────────────────────────────────────────────┐
│  Detect Chapters                                    │
│                                                     │
│  ✓ Found 12 chapters                                │
│                                                     │
│  ┌──────────────────────────────────────────────┐  │
│  │  1   Chapter 1      00:00:00                 │  │
│  │  2   Chapter 2      00:14:32                 │  │
│  │  3   Chapter 3      00:31:07                 │  │
│  │  …                                           │  │
│  └──────────────────────────────────────────────┘  │
│                                                     │
│  Noise floor: -45 dB   Min silence: 1.5 s           │
│                                                     │
│  [Re-detect]           [Cancel]   [Apply chapters]  │
└─────────────────────────────────────────────────────┘
```

- Chapter titles are auto-generated as `Chapter 1`, `Chapter 2`, etc.
- Timestamps are shown in `HH:MM:SS` format.
- The list is scrollable (max ~8 rows visible before scroll).
- **Re-detect** returns to the parameter form (fields pre-filled with last-used values).
- **Apply chapters** proceeds to the replace-warning step (see below).

### Replace warning (if existing chapters present)

If `_ctrl.entries` is non-empty when the user taps **Apply chapters**:

```
┌─────────────────────────────────────────────────────┐
│  Replace existing chapters?                         │
│                                                     │
│  This will replace the 8 existing chapters with     │
│  12 detected chapters. This can be undone with      │
│  Ctrl+Z in the chapter editor.                      │
│                                                     │
│  [Cancel]                    [Replace]              │
└─────────────────────────────────────────────────────┘
```

If the chapter table is currently empty, skip this confirmation and apply directly.

---

## Chapter Table Population

On confirm:

1. Call `_ctrl.replaceAll(detectedEntries)` — this pushes to the undo stack automatically (existing `ChapterEditorController.replaceAll` already does this).
2. Call `widget.onChanged(_ctrl.entries)` to mark the book dirty.
3. Close the dialog.

The user can immediately Ctrl+Z in the chapter editor to revert to the previous chapter list.

---

## ffmpeg Command

```
ffmpeg -i <input_file>
       -af silencedetect=noise=<floor>dB:d=<duration>
       -f null -
```

Run via `dart:io` `Process.start`. Parse stderr line by line.

**Silence end timestamps** (lines containing `silence_end`) mark the start of the next chapter:

```
[silencedetect @ ...] silence_end: 874.123 | silence_duration: 2.041
```

Chapter boundaries = list of `silence_end` values. First chapter always starts at `00:00:00`.

**Progress** is parsed from lines like:
```
size=    0kB time=00:14:32.10 bitrate=...
```

---

## New Service: `SilenceDetectionService`

```dart
// lib/services/silence_detection_service.dart

class SilenceDetectionResult {
  final List<Duration> boundaries; // silence_end timestamps
  final String? error;
}

class SilenceDetectionService {
  /// Resolves ffmpeg by checking in order:
  ///   1. System PATH (`ffmpeg` / `ffmpeg.exe`)
  ///   2. `<exe_dir>/ffmpeg.exe`
  ///   3. `<exe_dir>/ffmpeg/bin/ffmpeg.exe`
  /// Returns the first path that resolves to an existing file, or null.
  static String? get ffmpegPath { ... }

  static bool get isAvailable => ffmpegPath != null;

  /// Runs silencedetect and streams progress (0.0–1.0) and result.
  Stream<SilenceDetectionProgress> detect({
    required String filePath,
    required double noiseFloorDb,    // e.g. -45.0
    required double minSilenceSecs,  // e.g. 1.5
    required Duration? totalDuration,
  });
}

sealed class SilenceDetectionProgress {}
class SilenceDetectionProgressUpdate extends SilenceDetectionProgress {
  final double fraction; // 0.0–1.0
}
class SilenceDetectionComplete extends SilenceDetectionProgress {
  final List<Duration> boundaries;
}
class SilenceDetectionError extends SilenceDetectionProgress {
  final String message;
}
```

---

## New Widget: `DetectChaptersDialog`

```
lib/widgets/detect_chapters_dialog.dart
```

Stateful widget managing the multi-step flow:
- `_DetectState.params` → parameter form
- `_DetectState.detecting` → progress view
- `_DetectState.preview` → results preview
- `_DetectState.replacing` → replace confirmation

Returns `List<ChapterEntry>?` via `Navigator.pop` — null means cancelled.

---

## Acceptance Criteria

- [ ] "Detect chapters" button appears in the chapter editor toolbar for single-file books only
- [ ] Button is disabled with explanatory tooltip when ffmpeg is not found
- [ ] Dialog shows noise floor and min silence fields with correct defaults (−45 dB, 1.5 s)
- [ ] Progress bar shows percentage derived from ffmpeg time output; falls back to indeterminate if duration unknown
- [ ] Cancel terminates the ffmpeg process immediately
- [ ] Auto-retry fires when detected count > 100, stepping through up to 5 parameter combinations
- [ ] Auto-retry status message is shown during each retry attempt
- [ ] If all retries exceed 100, best result is shown with a warning banner
- [ ] Preview shows chapter count, scrollable list of `Chapter N / HH:MM:SS` rows, and the parameters used
- [ ] Re-detect returns to the parameter form with last-used values pre-filled
- [ ] Replace confirmation is shown when existing chapters are non-empty; skipped when table is empty
- [ ] Replace confirmation message states the old and new chapter counts
- [ ] Applying populates the chapter editor table via `_ctrl.replaceAll`, pushing to the undo stack
- [ ] Ctrl+Z in the chapter editor reverts to the previous chapter list after detection
- [ ] Multi-file books do not show the "Detect chapters" button

---

## Out of Scope

- Detecting chapters in multi-file books
- Editing detected chapter titles before applying (use the chapter editor after applying)
- Saving detection parameters as persistent preferences (follow-up)
- Detecting silence in a time range (e.g. only scan the first hour)

---

## Files Impacted

- `lib/services/silence_detection_service.dart` (new)
- `lib/widgets/detect_chapters_dialog.dart` (new)
- `lib/widgets/chapter_editor.dart` — add toolbar button, wire dialog, call `_ctrl.replaceAll`
- `CHANGELOG.md`
- `windows/CMakeLists.txt` or release workflow — bundle ffmpeg.exe alongside the executable
