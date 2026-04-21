# PRD-24 (P3): Persist user preferences across sessions

## Problem
Every time the app is restarted, the user must re-open their library folder and re-configure their sort order. The last-opened folder path, sort preference, and window size/position are all lost. For users with a fixed library location this is a repeated friction point.

## Evidence
- `LibraryController` holds `_folderPath`, `_sortOrder`, and `_batchPaths` in memory only — no persistence
- `main()` does not restore any previous state on launch
- `window_manager` is already a dependency but window size/position are never saved

## Proposed Solution
- Use the `shared_preferences` package to persist: last folder path, sort order
- On launch, if a saved folder path exists, automatically reload it (with a loading indicator)
- Restore the saved sort order immediately on launch
- Use `window_manager` to save and restore window bounds (size + position) on close/open

## Acceptance Criteria
- [ ] Last-opened folder is automatically reloaded on next launch
- [ ] Sort order is restored to the last-used value on launch
- [ ] Window size and position are restored on launch
- [ ] If the saved folder no longer exists, show a dismissible banner and clear the saved path
- [ ] User can still open a different folder at any time

## Out of Scope
- Persisting the selected book or scroll position within the list
- Persisting search query
- Multiple library profiles

## Decision Points
- Auto-reload on launch: show the folder path and a loading indicator immediately; do not block the UI. If the folder scan fails (path gone), show a banner.
- `shared_preferences` is the standard Flutter package for lightweight key-value persistence; no database needed.
- Window bounds: save on `WindowListener.onWindowClose`; restore in `main()` before `runApp`.

## Implementation Plan
1. Add `shared_preferences: ^2.x` to `pubspec.yaml`
2. Create `lib/services/preferences_service.dart` with static methods: `saveFolder(String path)`, `loadFolder()`, `saveSortOrder(SortOrder)`, `loadSortOrder()`, `saveWindowBounds(Rect)`, `loadWindowBounds()`
3. `LibraryController`: call `PreferencesService.saveFolder` in `pickFolder`; call `PreferencesService.saveSortOrder` in `setSortOrder`
4. `main()`: after `windowManager.ensureInitialized()`, load saved window bounds and call `windowManager.setBounds`; load saved folder and sort order; pass to `LibraryController` initial state
5. Add `WindowListener` mixin to `_HomeScreenState`; implement `onWindowClose` to save current window bounds
6. `LibraryController`: if saved folder path does not exist on auto-load, emit an error state; `HomeScreen` shows a `MaterialBanner` with "Library folder not found" and a Dismiss button

## Files Impacted
- `pubspec.yaml` — add `shared_preferences`
- `lib/services/preferences_service.dart` (new)
- `lib/controllers/library_controller.dart` — save folder + sort on change; accept initial values
- `lib/main.dart` — restore preferences on launch; `WindowListener` for bounds save
- `CHANGELOG.md`
