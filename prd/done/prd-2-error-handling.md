# PRD-2 (P1): Error handling UI for Apply and Export

## Problem
`_apply` and `exportMetadata` catch all exceptions silently. If a file is locked, permissions are denied, or a write partially fails, the user sees nothing — the UI looks like it succeeded.

## Evidence
- `MetadataWriter.applyCover`, `applyMetadata`, `exportMetadata` all have bare `catch (_) {}` or `catch (e) {}` with no propagation
- `_apply` in `BookDetailScreen` has no try/catch at all — an unhandled exception would crash the apply flow silently in release mode

## Proposed Solution
- Wrap `_apply` in a try/catch; on error show a `SnackBar` with the error message
- `MetadataWriter` methods collect per-file errors and return a result object instead of swallowing them
- Apply shows a summary if some files failed (e.g. "Applied to 3/4 files — 1 failed: book.m4b (Access denied)")

## Decision Points
- Return type for `applyMetadata`/`applyCover`: use a simple `List<String> errors` return rather than a full result type — keeps it minimal
- Loading state: disable Apply button and show a `CircularProgressIndicator` in place of the check icon while writing

## Acceptance Criteria
- [ ] Apply shows a loading indicator while writing
- [ ] Any file-level error surfaces in a SnackBar with the filename and error
- [ ] A fully successful apply shows no error UI (silent success)
- [ ] Export metadata errors are shown in a SnackBar

## Out of Scope
- Retry logic
- Detailed error logging to disk

## Implementation Plan
1. Change `MetadataWriter.applyMetadata` and `applyCover` to return `List<String>` (list of `"filename: error"` strings); empty = success
2. Change `exportMetadata` to rethrow or return error string
3. In `BookDetailScreen._apply`:
   - Set `_applying = true` in setState before writes, `false` after
   - Disable Apply button when `_applying`; show `SizedBox(width:18, height:18, child: CircularProgressIndicator(strokeWidth: 2))` in place of check icon
   - Collect errors from both calls; if non-empty show SnackBar listing them
4. Wrap Export metadata button `onPressed` in try/catch; show SnackBar on error

## Files Impacted
- `lib/services/metadata_writer.dart` — return errors instead of swallowing
- `lib/screens/book_detail_screen.dart` — loading state + error SnackBar
- `CHANGELOG.md`
