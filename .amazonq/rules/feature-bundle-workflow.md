# Feature Bundle Workflow

A "feature bundle" is a set of related PRDs implemented together on a single branch and merged to `main` as a version bump.

## When to use
- Multiple PRDs share a theme (e.g. metadata fields, UI polish, format support)
- The bundle is scoped to a minor version increment (x.Y.0)

## Branch naming
```
git checkout -b feature/vX.Y.0-<short-bundle-description>
```
Example: `feature/v1.1.0-metadata-enhancements`

## Per-PRD loop (repeat for every PRD in the bundle)
1. Implement the PRD — minimal code, no scope creep
2. Run `flutter analyze` — fix any errors before continuing
3. Run `flutter test` — all tests must pass; add tests for any new non-trivial public service methods
4. Log unresolved questions or deferred decisions in `prd/refinements.md`
5. Commit with message `feat: <prd-title-slug>` (e.g. `feat: publisher-language-edit`)

## After all PRDs are implemented
1. Bump `version` in `pubspec.yaml` to `X.Y.0+<build>`
2. Update `CHANGELOG.md` — add a `## [X.Y.0]` section listing every change
3. Update `README.md` if any user-facing features, formats, or tech-stack entries changed
4. Run `flutter analyze && flutter test` one final time — both must be clean
5. Commit: `chore: bump to vX.Y.0, update changelog and readme`

## Merge and release
```bash
git checkout main
git merge --ff-only feature/vX.Y.0-<description>
git push origin main
```
If fast-forward is not possible (main has diverged), rebase the feature branch first:
```bash
git rebase main
```

## Build release exe (Windows)
```bash
flutter build windows --release
```
The exe is at `build\windows\x64\runner\Release\audiovault_editor.exe`.

## GitHub release
```bash
# Tag the version
git tag vX.Y.0
git push origin vX.Y.0
```
Then create a GitHub release from the tag, attach the exe and any relevant assets.

## Notes
- Never commit directly to `main` during a bundle — all work stays on the feature branch until the final merge
- Each per-PRD commit must leave the branch in a passing state (`flutter test` green)
- If a PRD turns out to be blocked or out of scope mid-bundle, skip it, note it in `refinements.md`, and continue
