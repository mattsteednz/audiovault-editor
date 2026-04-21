# PRD-7 (P2): Window title shows library folder path

## Problem
The window title is always "AudioVault Editor" regardless of which folder is open. With multiple windows or when alt-tabbing, there is no way to tell which library is loaded.

## Evidence
- `MaterialApp.title` is hardcoded to `'AudioVault Editor'`
- No platform channel or `window_manager` package is used

## Proposed Solution
Use the `window_manager` package to set the window title to `"AudioVault Editor — <folder name>"` when a folder is loaded, and reset to `"AudioVault Editor"` when no folder is open.

## Decision Points
- Use `window_manager` (pub.dev) rather than a platform channel — it's the standard Flutter Windows approach and already used by similar tools
- Show only the last path component (folder name), not the full path — keeps the title bar readable
- Title updates immediately when `_folderPath` changes

## Acceptance Criteria
- [ ] Window title shows `"AudioVault Editor — <folder name>"` when a folder is loaded
- [ ] Window title resets to `"AudioVault Editor"` when no folder is open
- [ ] Title updates on every new folder open

## Out of Scope
- Showing the selected book in the title

## Implementation Plan
1. Add `window_manager: ^0.4.0` to `pubspec.yaml`
2. In `main()`, call `await windowManager.ensureInitialized()` and set initial title
3. In `_HomeScreenState._pickFolder`, after setting `_folderPath`, call `windowManager.setTitle('AudioVault Editor — ${p.basename(result)}')`
4. On folder clear (if ever added), reset title

## Files Impacted
- `pubspec.yaml`
- `lib/main.dart`
- `CHANGELOG.md`
