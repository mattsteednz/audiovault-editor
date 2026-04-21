# PRD-25 (P3): Scan progress with live book count

## Problem
When scanning a large library the sidebar shows only a generic `LinearProgressIndicator` with no indication of how many books have been found or how far along the scan is. For libraries with hundreds of books this gives no useful feedback — the user cannot tell if the scan is progressing normally or has stalled.

## Evidence
- `ScannerService.scanFolder` accepts an `onBookFound` callback and calls it as each book is discovered
- `LibraryController` passes `onBookFound: (b) { _books.add(b); notifyListeners(); }` — books appear in the list as they are found
- The sidebar shows `LinearProgressIndicator()` (indeterminate) while `_ctrl.scanning` is true
- No count of found-so-far books is shown during the scan

## Proposed Solution
- Replace the indeterminate `LinearProgressIndicator` with a determinate one once the total subfolder count is known
- Show a "Scanning… N book(s) found" label below the progress bar during the scan
- After the scan completes, the label transitions to the normal "N of M book(s)" filter count

## Acceptance Criteria
- [ ] During scan, a live "Scanning… N book(s) found" counter updates as books are discovered
- [ ] Progress bar becomes determinate once the top-level subfolder count is known
- [ ] After scan completes, the counter is replaced by the normal filtered count label
- [ ] Scanning a folder with 0 books shows "No books found" after completion

## Out of Scope
- Cancelling an in-progress scan
- Per-book progress (individual file reads)

## Decision Points
- Determinate progress: `ScannerService.scanFolder` can count top-level subdirectories before starting the recursive scan and report that as the total. Progress = books-found / estimated-total is a reasonable approximation even if some subdirs contain multiple books.
- The "N book(s) found" label is shown in place of the filtered count only while scanning; it does not replace the search/sort row.

## Implementation Plan
1. `ScannerService.scanFolder`: add optional `onProgress(int found, int total)` callback; call it after each top-level subdir is processed with the running count and the total subdir count
2. `LibraryController`: add `_scanFound` and `_scanTotal` int fields; wire `onProgress` to update them and call `notifyListeners()`; expose as `scanFound` and `scanTotal` getters; reset both when scan starts and completes
3. `HomeScreen._buildToolbar`: replace the static `LinearProgressIndicator()` with:
   - `LinearProgressIndicator(value: _ctrl.scanTotal > 0 ? _ctrl.scanFound / _ctrl.scanTotal : null)` (determinate when total known)
   - A `Text('Scanning… ${_ctrl.scanFound} book(s) found', ...)` label below it
4. After scan completes (`!_ctrl.scanning`), the label reverts to the existing filtered count text

## Files Impacted
- `lib/services/scanner_service.dart` — add `onProgress` callback
- `lib/controllers/library_controller.dart` — track `scanFound`/`scanTotal`; expose getters
- `lib/main.dart` — update progress bar and label in `_buildToolbar`
- `CHANGELOG.md`
