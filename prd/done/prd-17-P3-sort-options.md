# PRD-17 (P3): Additional sort options — series, narrator, duration

## Problem
The sidebar sort menu only offers Title A–Z/Z–A and Author A–Z/Z–A. Users who organise by series or want to find the shortest/longest books have no way to sort by series, narrator, or duration.

## Evidence
- `_SortOrder` enum has four values: `titleAsc`, `titleDesc`, `authorAsc`, `authorDesc`
- `_filteredBooks` getter handles only those four cases

## Proposed Solution
Add four more sort options to the existing `PopupMenuButton`:
- Series A–Z (books without a series sort last)
- Narrator A–Z
- Duration (shortest first)
- Duration (longest first)

## Acceptance Criteria
- [ ] Sort menu shows six additional items (Series A–Z, Narrator A–Z, Duration ↑, Duration ↓)
- [ ] Series sort places books with no series after all series books
- [ ] Duration sort handles `null` duration (treated as 0)
- [ ] Selected sort order persists while the library is open (in-memory only)

## Out of Scope
- Persisting sort preference across app restarts

## Implementation Plan
1. Extend `_SortOrder` enum with `seriesAsc`, `narratorAsc`, `durationAsc`, `durationDesc`
2. Add corresponding `switch` cases in `_filteredBooks` getter
3. Add four `PopupMenuItem` entries to the sort `PopupMenuButton`

## Files Impacted
- `lib/main.dart`
- `CHANGELOG.md`
