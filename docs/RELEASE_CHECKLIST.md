# Release Checklist

## 1. Version + changelog
- [ ] Bump `version:` in `pubspec.yaml` (`X.Y.Z+build`).
- [ ] Add a `CHANGELOG.md` section for the new version (Added / Changed /
      Fixed) referencing the PRD numbers where applicable.

## 2. Quality gates (all must be green)
- [ ] `flutter analyze` — zero issues (CI runs with `--fatal-warnings`).
- [ ] `flutter test` — full suite green.
- [ ] Manual smoke on a real library:
  - [ ] Open folder → scan completes, no warnings you don't expect.
  - [ ] Edit tags → Apply → verify in another tool (e.g. Mp3tag).
  - [ ] Chapters: edit timestamps, Quick Edit paste, write to M4B, re-scan
        shows new chapters.
  - [ ] Cover: drag-drop → Apply → cover.jpg written + embedded.
  - [ ] Batch edit 2+ books; blank-field behaviour intact.
  - [ ] Undo/redo across apply + rescan + rename.
  - [ ] Close app with unsaved changes → guard dialog appears.
  - [ ] Settings: ffmpeg override picked up by Detect chapters.

## 3. Release engineering
- [ ] Tag the commit: `git tag vX.Y.Z && git push origin vX.Y.Z`.
- [ ] GitHub Actions builds + attaches `audiovault-editor-vX.Y.Z-windows.zip`.
- [ ] Release notes mention the VC++ Redistributable requirement.
- [ ] Optional: build installer via `installer/windows.iss` (Inno Setup) and
      attach alongside the zip.

## 4. Post-release
- [ ] Verify the release download launches on a clean machine.
- [ ] Close/verify GitHub issues fixed by the release.
