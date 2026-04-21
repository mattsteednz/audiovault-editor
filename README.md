# AudioVault Editor

A Flutter Windows desktop companion app for [AudioVault](https://github.com/mattlgroff/audiovault) that lets you browse and edit audiobook metadata in your local library.

## Features

- **Library scanning** — open any folder and recursively finds audiobooks organised as subfolders of audio files (MP3, M4B, AAC, FLAC, OGG), including author/series grouping up to three levels deep. Reads `metadata.opf` files (Calibre/OverDrive) for richer metadata including series, narrator, genre, identifier, and multiple authors.
- **Metadata editing** — edit title, author, narrator, publisher, language, genre, published date, series, and description directly in the UI; changes are tracked and only committed when you hit Apply
- **Cover art** — drag and drop or browse for a new cover image; on Apply it is converted to JPEG, embedded into each audio file, and written as `cover.jpg` to the book folder
- **Batch editing** — select 2+ books to apply author, narrator, publisher, language, genre, series, and date to all at once
- **Duplicate detection** — books with matching title+author are flagged in the sidebar with a filter chip
- **Missing cover filter** — quickly find books without cover art via a sidebar filter chip
- **Sort options** — Title, Author, Series, Narrator, Duration (ascending/descending)
- **Chapter editing** — view and rename chapters from embedded M4B chapter tracks, CUE sheets, or multi-file MP3 collections
- **Cover art** — drag and drop a new cover image onto the book; on Apply it is converted to JPEG, embedded into each audio file (ID3v2 APIC for MP3, MP4 `covr` atom for M4B/M4A), and written as `cover.jpg` to the book folder
- **Export metadata** — generates a `metadata.opf` (Calibre-compatible) and `cover.jpg` in the book folder from the current metadata
- **Unsaved change tracking** — an indicator shows which books have unapplied edits; Apply is only enabled when something has actually changed

## Getting Started

### Prerequisites

- Flutter 3.x
- Windows 10/11 with Developer Mode enabled
- Visual Studio 2022 Build Tools with the **Desktop development with C++** workload

```bash
flutter pub get
flutter run -d windows
```

## Tech Stack

| Area | Package |
|---|---|
| Audio metadata (read) | `audio_metadata_reader` |
| OPF parsing | `xml` |
| Image conversion | `image` |
| Drag and drop | `desktop_drop` |
| Folder picker | `file_picker` |
| UI | Flutter Material 3 (dark) |

| Genre/tags | ✓ (read + write) |
| Publisher | ✓ (read + write) |
| Language | ✓ (read + write) |
| Identifier (ISBN/ASIN) | ✓ (read, OPF preserve) |
| Multiple authors/narrators | ✓ (read, display) |
| OPF custom meta passthrough | ✓ |

## Supported Formats

| Format | Metadata read | Cover embed |
|---|---|---|
| MP3 | ✓ | ✓ (ID3v2 APIC) |
| M4B / M4A | ✓ | ✓ (MP4 covr atom) |
| FLAC | ✓ | ✓ (METADATA_BLOCK_PICTURE) |
| OGG | ✓ | ✓ (Vorbis comment) |
| AAC | ✓ | — |

## License

MIT
