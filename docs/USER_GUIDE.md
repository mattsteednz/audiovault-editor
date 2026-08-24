# AudioVault Editor — User Guide

AudioVault Editor is a Windows desktop companion for your AudioVault library.
It lets you browse audiobooks stored as *one folder per book*, edit their
embedded tags and chapters, fix cover art, and batch-apply changes — with
atomic writes and undo protection.

## Getting started

1. Launch the app and click **Open Folder** (or press `Ctrl+O`) to pick the
   folder that contains your audiobook library. Books are discovered up to
   three levels deep (`Author/Book/book.m4b` works out of the box).
2. Your folder, sort order, sidebar width and window size are remembered.
3. Select a book to edit it. The **Apply** button only lights up when
   something actually changed.

### Supported formats

| Format | Tags read | Writes | Covers |
|---|---|---|---|
| MP3  | ✓ | ✓ (ID3v2.3 / v2.4 preserved) | ✓ APIC |
| M4B/M4A | ✓ | ✓ (iTunes `ilst` atoms) | ✓ `covr` |
| FLAC | ✓ | ✓ (Vorbis comments) | ✓ PICTURE |
| OGG  | ✓ | ✓ (comment header) | ✓ METADATA_BLOCK_PICTURE |
| AAC (.aac) | duration only | ✗ reported on Apply | ✗ |

## The editing model

**Merged vs file tags.** Books may carry metadata in embedded tags *and* in a
Calibre-style `metadata.opf`. By default the editor shows the merged view
(OPF wins). Toggle **File tags only** to see what's physically inside the
audio files. Nothing is written until you hit **Apply**.

**Covers.** Drag an image onto the cover or use the browse button. On Apply
the image is re-encoded to JPEG, embedded into every audio file, and written
as `cover.jpg` next to the book.

**Chapters.** Sources: Nero `chpl`, QuickTime chapter tracks, CUE sheets, or
one chapter per file for multi-file books. The Chapters tab supports inline
editing, Quick Edit paste (names / times / both), silence-detection via
ffmpeg, timestamp shifting and one-click renumbering. Conflicts block Apply.

## Fast workflows

- **Apply-and-next** — after a successful Apply the selection advances to the
  next book in your current view (toggle in Settings).
- **Batch edit** — tick two or more books; blank fields leave each book
  untouched.
- **Copy from…** — pull author/series/etc. from any other book.
- **Shortcuts**: `Ctrl+S` apply · `Ctrl+Z/Y` global undo/redo · `Ctrl+O` open ·
  `Ctrl+F` search · `F5` rescan · `Esc` clear search.

## Safety

- All writes are **atomic**: files are rebuilt in a temp file first, so a
  crash mid-write never corrupts your audio.
- Optionally enable **Keep .bak backups** in Settings to preserve one
  generation of each original file.
- **Export snapshot .zip** bundles freshly generated OPFs for every shown
  book as a lightweight backup of textual metadata.
- Global undo covers tag applies, rescans, batch edits and folder renames.

## ffmpeg (optional)

Chapter detection from silence needs `ffmpeg`. It is resolved from (1) the
path set in Settings, (2) your system PATH, (3) `ffmpeg.exe` beside the app,
(4) `ffmpeg\bin\ffmpeg.exe` beside the app.

## Logs

Settings → **Open log folder** reveals daily log files (7-day retention) that
are useful when reporting bugs.
