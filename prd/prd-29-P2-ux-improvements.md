# PRD-29 (P2): UX/UI Improvements — Cohesive Design System

## Problem
The current UI has several usability issues that create friction:
1. **Action bar is overcrowded** — 8+ buttons/controls in one row, hard to scan
2. **Export button is confusing** — Disabled button with dropdown, unclear it's clickable
3. **No visual hierarchy in sidebar** — All books look the same, hard to scan
4. **Sidebar width is fixed** — 300px doesn't adapt to content (long titles get cut off)
5. **Search has no clear button** — Users must manually delete text
6. **Sort menu is hidden** — Small icon, current sort order not visible
7. **Filter chips appear/disappear** — UI jumps when chips show/hide
8. **Batch selection mode is unclear** — No visual indication you're in "batch mode"

## Evidence
- Action bar has: ToggleButtons, Spacer, Copy, More, Export, Undo, Rescan, Apply, Unsaved text
- Export button uses `OutlinedButton.icon(onPressed: null)` with PopupMenuButton child (confusing pattern)
- Sidebar uses fixed `SizedBox(width: 300)` — no resize capability
- Search TextField has no suffix icon for clearing
- Sort PopupMenuButton shows only icon, no current state label
- FilterChips conditionally rendered with `if (_ctrl.duplicateCount > 0)` — causes layout shift
- Batch mode has no banner or visual feedback (only checkbox state changes)

## Proposed Solution
Implement a cohesive design system based on **"Progressive Disclosure with Clear Hierarchy"**:

### 1. Three-Tier Action Hierarchy
- **Tier 1 (Primary)**: Apply, Undo, Rescan — right-aligned, always visible
- **Tier 2 (Context)**: Copy from, More menu — left-aligned, contextual
- **Tier 3 (Overflow)**: Export OPF, Export Cover, Rename Folder — in More menu

### 2. Resizable Sidebar
- Add drag handle at bottom of sidebar
- Allow resize between 250-500px
- Persist width in preferences
- Show current sort order: "Sort: Title A-Z ▼" instead of icon only

### 3. Always-Visible Filter Chips
- Render filter chips always (not conditionally)
- Disable/gray out when count is 0
- Prevents layout shift

### 4. Search Clear Button
- Add suffix icon (X) when search has text
- Clicking X clears search and refocuses field

### 5. Batch Selection Banner
- Show banner when 2+ books selected: "✓ 3 books selected [Clear selection] [Edit all →]"
- Move checkbox to trailing position (right side, like Gmail)
- Banner provides clear exit from batch mode

### 6. View Toggle Relocation
- Move "OPF / merged" vs "File tags" toggle from action bar to above form fields
- Rename to "Merged metadata" / "File tags only" for clarity
- Frees up action bar space

### 7. Cover Thumbnails (Optional)
- Add 32x32 cover thumbnails to left of book title in sidebar
- Lazy-load to minimize memory impact
- Aids visual scanning

## Acceptance Criteria
- [ ] Action bar has max 6 items (Copy, More, Spacer, Undo, Rescan, Apply)
- [ ] Export and Rename are in More (⋮) overflow menu
- [ ] Sidebar is resizable (250-500px range) with drag handle
- [ ] Sidebar width persists across sessions
- [ ] Sort button shows current state: "Sort: Title A-Z ▼"
- [ ] Filter chips always visible (grayed when count = 0)
- [ ] Search field has clear (X) button when text present
- [ ] Batch selection shows banner: "✓ N books selected [Clear] [Edit all]"
- [ ] Checkbox is in trailing position (right side)
- [ ] View toggle moved above form fields with clearer labels
- [ ] Cover thumbnails show in sidebar (32x32, lazy-loaded)
- [ ] Tab order makes sense for keyboard navigation

## Out of Scope
- Keyboard shortcuts (deferred to future PRD)
- Grouping/collapsing in sidebar (not needed)
- Advanced filtering (beyond existing Dupes/No cover)

## Design Rationale
**Philosophy**: "Show what matters now, hide what doesn't, make everything discoverable"

**Patterns Referenced**:
- **iTunes/Music.app** — Clean toolbar, progressive disclosure
- **VS Code** — Resizable panels, contextual actions
- **Gmail** — Trailing checkboxes, selection banner
- **Material Design** — Clear hierarchy, purposeful motion

**Trade-offs**:
- ✅ **Clarity over efficiency** — Export is now 2 clicks (acceptable, infrequent)
- ✅ **Discoverability over power** — Overflow menu makes features findable
- ✅ **Consistency over innovation** — Matches standard patterns users know
- ❌ **Vertical space** — Banner, filter chips take room (worth it for clarity)
- ❌ **Complexity** — Resizable sidebar adds state management (worth it for flexibility)

## Implementation Plan

### Phase 1: Action Bar Reorganization (Highest impact, lowest risk)
1. Move Export OPF/Cover to More (⋮) overflow menu
2. Move Rename Folder to More (⋮) overflow menu
3. Reorder action bar: [Copy] [More] [Spacer] [Undo] [Rescan] [Apply]
4. Move view toggle above form fields, rename labels
5. Update action bar layout to use Row with proper spacing

### Phase 2: Sidebar Improvements (High impact, medium risk)
6. Change sort button to show label: "Sort: Title A-Z ▼"
7. Make filter chips always visible (grayed when count = 0)
8. Add search clear button (suffix icon)
9. Add cover thumbnails (32x32) to book list items
10. Implement lazy-loading for cover thumbnails

### Phase 3: Batch Selection (Medium impact, medium risk)
11. Move checkbox from leading to trailing position
12. Add selection banner when 2+ books selected
13. Add "Clear selection" and "Edit all" actions to banner
14. Update batch selection logic

### Phase 4: Resizable Sidebar (Medium impact, high risk)
15. Add GestureDetector for drag handle at sidebar bottom
16. Implement resize logic (250-500px constraints)
17. Persist sidebar width in PreferencesService
18. Restore sidebar width on launch

### Phase 5: Polish
19. Verify tab order for keyboard navigation
20. Test all interactions
21. Update CHANGELOG.md

## Files Impacted
- `lib/main.dart` — sidebar resize, filter chips, search clear, batch banner, thumbnails
- `lib/screens/book_detail_screen.dart` — action bar reorganization, view toggle relocation
- `lib/services/preferences_service.dart` — save/load sidebar width
- `lib/controllers/library_controller.dart` — batch selection state
- `CHANGELOG.md`

## Visual Mockup

```
┌────────────────────┬─────────────────────────────────────────┐
│ [Open Folder]      │ [Cover]  Title, Author, Duration...    │
│ /library           │                                         │
│                    │ View: [Merged] [File tags]             │
│ [Search...] [X]    │                                         │
│ Sort: Title A-Z ▼  │ [Copy from] [⋮]  [Undo][Rescan][Apply]│
│ 45 of 120 books    │                                         │
│                    │ [Book] [Chapters (12)]                  │
│ [Dupes: 3]         │ ┌─────────────────────────────────────┐│
│ [No cover: 5]      │ │ Title: [___________]                ││
│                    │ │ Author: [___________]               ││
│ ┌────────────────┐ │ └─────────────────────────────────────┘│
│ │📖 Book Title  ☐│ │                                         │
│ │  Author       │ │                                         │
│ └────────────────┘ │                                         │
│ [═══]              │ ← Resize handle                         │
└────────────────────┴─────────────────────────────────────────┘

When 2+ books selected:
┌────────────────────────────────────────────────────────────┐
│ ✓ 3 books selected  [Clear selection]  [Edit all →]       │
└────────────────────────────────────────────────────────────┘
```

## Success Metrics
- Reduced cognitive load (fewer visible buttons)
- Improved discoverability (labeled sort, always-visible filters)
- Better adaptability (resizable sidebar)
- Clearer feedback (batch banner, search clear)
- Consistent with industry patterns (trailing checkbox, overflow menu)
