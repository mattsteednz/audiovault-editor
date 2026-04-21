# Design Document: UX/UI Improvements — Cohesive Design System

## Overview

This design implements a cohesive design system for the AudioVault Editor based on the principle of **"Progressive Disclosure with Clear Hierarchy."** The redesign addresses 8 critical usability issues through systematic application of industry-standard UI patterns from iTunes/Music.app, VS Code, Gmail, and Material Design.

### Design Philosophy

**"Show what matters now, hide what doesn't, make everything discoverable"**

The design prioritizes:
- **Clarity over efficiency** — Some actions require an extra click but are more discoverable
- **Discoverability over power** — Overflow menus make infrequent features findable
- **Consistency over innovation** — Matches standard patterns users already know
- **Adaptability** — Resizable panels accommodate different content and preferences

### Key Improvements

1. **Three-Tier Action Hierarchy** — Organizes actions by importance and frequency
2. **Resizable Sidebar** — Adapts to content with persistent width preference
3. **Always-Visible Filter Chips** — Prevents layout shift and improves predictability
4. **Search Clear Button** — Quick search reset with single click
5. **Batch Selection Banner** — Clear visual feedback for multi-book editing
6. **View Toggle Relocation** — Positioned near affected fields with clearer labels
7. **Sort Button with State** — Shows current sort order at a glance
8. **Cover Thumbnails** — Visual scanning aid in book list
9. **Keyboard Navigation** — Logical tab order for efficient keyboard use
10. **Preferences Persistence** — Saves sidebar width across sessions

## Architecture

### Component Structure

The design maintains the existing two-panel layout with enhancements:

```
┌─────────────────────────────────────────────────────────────────┐
│ HomeScreen (Scaffold)                                           │
│ ┌─────────────────┬─────────────────────────────────────────┐  │
│ │ Sidebar         │ Detail Panel                            │  │
│ │ (Resizable)     │                                         │  │
│ │                 │ [Batch Banner] (conditional)            │  │
│ │ [Toolbar]       │                                         │  │
│ │ [Book List]     │ [Book Detail / Batch Edit]              │  │
│ │ [Resize Handle] │                                         │  │
│ └─────────────────┴─────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Widget Hierarchy

#### HomeScreen Widget Tree

```
HomeScreen (StatefulWidget)
├── Scaffold
    ├── Column
        ├── MaterialBanner (error banner, conditional)
        └── Expanded
            └── Row
                ├── ResizableSidebar (new widget)
                │   ├── Column
                │   │   ├── _buildToolbar()
                │   │   │   ├── FilledButton (Open Folder)
                │   │   │   ├── Text (folder path)
                │   │   │   ├── Row
                │   │   │   │   ├── TextField (search with clear button)
                │   │   │   │   └── SortButton (new widget)
                │   │   │   ├── Text (book count)
                │   │   │   └── Wrap (filter chips - always visible)
                │   │   └── Expanded
                │   │       └── _buildBookList()
                │   └── GestureDetector (resize handle)
                ├── VerticalDivider
                └── Expanded
                    └── Column
                        ├── BatchSelectionBanner (conditional)
                        └── Expanded
                            └── FocusScope
                                └── [BookDetailScreen | BatchEditScreen]
```

#### BookDetailScreen Widget Tree (Modified)

```
BookDetailScreen
└── Padding
    └── Column
        ├── Row (header)
        │   ├── _buildCover()
        │   └── _buildSummary()
        ├── ViewToggle (relocated from action bar)
        ├── _buildActionBar() (reorganized)
        │   ├── OutlinedButton (Copy from)
        │   ├── PopupMenuButton (More menu)
        │   ├── Spacer
        │   ├── IconButton (Undo)
        │   ├── IconButton (Rescan)
        │   └── FilledButton (Apply)
        ├── TabBar
        └── Expanded
            └── TabBarView
```

### State Management

The design uses the existing `LibraryController` with minimal additions:

**Existing State (unchanged):**
- `_books`, `_selected`, `_undoSnapshot`
- `_dirtyPaths`, `_batchPaths`
- `_duplicatePaths`, `_missingCoverPaths`
- `_showDuplicatesOnly`, `_showMissingCoverOnly`
- `_scanning`, `_scanFound`, `_scanTotal`
- `_folderPath`, `_searchQuery`, `_sortOrder`

**New State (in HomeScreen):**
- `_sidebarWidth: double` — Current sidebar width (250-500px)
- `_isDraggingResize: bool` — Whether resize handle is being dragged

**New State (in LibraryController - optional):**
- `clearBatchSelection()` — Method to clear all batch selections
- `selectAllBatch(List<Audiobook> books)` — Method to select multiple books

### Data Flow

#### Sidebar Resize Flow

```
User drags resize handle
    ↓
GestureDetector.onPanUpdate
    ↓
setState(() => _sidebarWidth = newWidth.clamp(250, 500))
    ↓
Widget rebuilds with new width
    ↓
GestureDetector.onPanEnd
    ↓
PreferencesService.saveSidebarWidth(_sidebarWidth)
```

#### Batch Selection Flow

```
User checks 2+ books
    ↓
LibraryController.toggleBatch()
    ↓
_batchPaths.length >= 2
    ↓
BatchSelectionBanner appears
    ↓
User clicks "Clear selection"
    ↓
LibraryController.clearBatchSelection()
    ↓
Banner disappears
```

#### Search Clear Flow

```
User types in search field
    ↓
TextField.onChanged → LibraryController.setSearchQuery()
    ↓
Clear button (X) appears as suffix icon
    ↓
User clicks clear button
    ↓
_searchCtrl.clear() + LibraryController.setSearchQuery('')
    ↓
TextField.requestFocus()
```

## Components and Interfaces

### 1. ResizableSidebar Widget

**Purpose:** Wraps the sidebar content with a resize handle

**Interface:**
```dart
class ResizableSidebar extends StatefulWidget {
  final Widget child;
  final double initialWidth;
  final double minWidth;
  final double maxWidth;
  final ValueChanged<double> onWidthChanged;
  
  const ResizableSidebar({
    required this.child,
    this.initialWidth = 300,
    this.minWidth = 250,
    this.maxWidth = 500,
    required this.onWidthChanged,
  });
}
```

**State:**
- `_currentWidth: double` — Current width during drag
- `_isDragging: bool` — Whether actively dragging

**Behavior:**
- Displays child widget with current width
- Shows resize handle at bottom (horizontal line with drag cursor)
- On drag: updates width in real-time (clamped to min/max)
- On drag end: calls `onWidthChanged` callback for persistence

### 2. SortButton Widget

**Purpose:** Displays current sort order with dropdown menu

**Interface:**
```dart
class SortButton extends StatelessWidget {
  final SortOrder currentOrder;
  final ValueChanged<SortOrder> onOrderChanged;
  
  const SortButton({
    required this.currentOrder,
    required this.onOrderChanged,
  });
}
```

**Behavior:**
- Displays label: "Sort: [Order] ▼"
- Order text maps from enum: `titleAsc` → "Title A-Z", etc.
- On click: shows PopupMenuButton with all sort options
- On selection: calls `onOrderChanged` callback

**Label Mapping:**
```dart
static const _labels = {
  SortOrder.titleAsc: 'Title A-Z',
  SortOrder.titleDesc: 'Title Z-A',
  SortOrder.authorAsc: 'Author A-Z',
  SortOrder.authorDesc: 'Author Z-A',
  SortOrder.seriesAsc: 'Series A-Z',
  SortOrder.narratorAsc: 'Narrator A-Z',
  SortOrder.durationAsc: 'Duration ↑',
  SortOrder.durationDesc: 'Duration ↓',
};
```

### 3. BatchSelectionBanner Widget

**Purpose:** Shows selection count and actions when 2+ books selected

**Interface:**
```dart
class BatchSelectionBanner extends StatelessWidget {
  final int selectionCount;
  final VoidCallback onClearSelection;
  final VoidCallback onEditAll;
  
  const BatchSelectionBanner({
    required this.selectionCount,
    required this.onClearSelection,
    required this.onEditAll,
  });
}
```

**Layout:**
```
┌────────────────────────────────────────────────────────────┐
│ ✓ N books selected  [Clear selection]  [Edit all →]       │
└────────────────────────────────────────────────────────────┘
```

**Behavior:**
- Only rendered when `selectionCount >= 2`
- "Clear selection" button calls `onClearSelection`
- "Edit all →" button calls `onEditAll`
- Uses Material banner styling with light background

### 4. CoverThumbnail Widget

**Purpose:** Displays 32x32 cover image or placeholder in book list

**Interface:**
```dart
class CoverThumbnail extends StatelessWidget {
  final Audiobook book;
  final double size;
  
  const CoverThumbnail({
    required this.book,
    this.size = 32,
  });
}
```

**Behavior:**
- If `book.coverImageBytes != null`: displays Image.memory
- Else if `book.coverImagePath != null`: displays Image.file
- Else: displays placeholder Icon(Icons.book)
- Uses BoxFit.cover with ClipRRect for rounded corners
- Lazy-loads images (Flutter handles this automatically)

### 5. Enhanced TextField (Search with Clear)

**Implementation:** Modify existing search TextField

**Changes:**
```dart
TextField(
  controller: _searchCtrl,
  onChanged: _ctrl.setSearchQuery,
  decoration: InputDecoration(
    hintText: 'Search...',
    isDense: true,
    prefixIcon: Icon(Icons.search, size: 16),
    suffixIcon: _searchCtrl.text.isNotEmpty
        ? IconButton(
            icon: Icon(Icons.clear, size: 16),
            onPressed: () {
              _searchCtrl.clear();
              _ctrl.setSearchQuery('');
              // Request focus to keep user in search field
              FocusScope.of(context).requestFocus(_searchFocusNode);
            },
          )
        : null,
    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    border: OutlineInputBorder(),
  ),
)
```

**State Addition:**
- Add `_searchFocusNode: FocusNode` to HomeScreen state
- Attach to TextField: `focusNode: _searchFocusNode`

### 6. Always-Visible Filter Chips

**Implementation:** Modify existing filter chip rendering

**Current (conditional):**
```dart
if (_ctrl.duplicateCount > 0 || _ctrl.missingCoverCount > 0) ...[
  Wrap(
    children: [
      if (_ctrl.duplicateCount > 0) FilterChip(...),
      if (_ctrl.missingCoverCount > 0) FilterChip(...),
    ],
  ),
]
```

**New (always visible):**
```dart
Wrap(
  spacing: 4,
  children: [
    FilterChip(
      label: Text('Dupes (${_ctrl.duplicateCount})'),
      selected: _ctrl.showDuplicatesOnly,
      onSelected: _ctrl.duplicateCount > 0 ? (_) => _ctrl.toggleShowDuplicates() : null,
      labelStyle: TextStyle(fontSize: 11),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    ),
    FilterChip(
      label: Text('No cover (${_ctrl.missingCoverCount})'),
      selected: _ctrl.showMissingCoverOnly,
      onSelected: _ctrl.missingCoverCount > 0 ? (_) => _ctrl.toggleShowMissingCover() : null,
      labelStyle: TextStyle(fontSize: 11),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    ),
  ],
)
```

**Key Change:** `onSelected` is `null` when count is 0, which disables the chip

### 7. Reorganized Action Bar

**Current Layout:**
```
[ToggleButtons] [Spacer] [Copy] [More] [Export▼] [Undo] [Rescan] [Apply] [Unsaved text]
```

**New Layout:**
```
[Copy from] [More▼] [Spacer] [Undo] [Rescan] [Apply] [Unsaved text]
```

**More Menu Contents:**
- Export OPF
- Export Cover (disabled if no cover)
- Rename Folder

**View Toggle:** Moved above form fields (below summary, above "Title:" field)

### 8. Trailing Checkboxes in Book List

**Current:**
```dart
ListTile(
  leading: Checkbox(...),
  title: Text(book.title),
  subtitle: Text(book.author),
)
```

**New:**
```dart
ListTile(
  leading: CoverThumbnail(book: book),
  title: Text(book.title),
  subtitle: Text(book.author),
  trailing: Checkbox(...),
)
```

**Rationale:** Matches Gmail pattern, keeps visual focus on content (cover + title)

## Data Models

No new data models required. All state is managed through existing `Audiobook` model and controller state.

### PreferencesService Extension

**New Methods:**

```dart
class PreferencesService {
  static const _keySidebarWidth = 'sidebar_width';
  
  /// Save the sidebar width preference
  static Future<void> saveSidebarWidth(double width) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySidebarWidth, width);
  }
  
  /// Load the saved sidebar width, or null if none saved
  static Future<double?> loadSidebarWidth() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keySidebarWidth);
  }
}
```

### LibraryController Extension

**New Methods:**

```dart
class LibraryController extends ChangeNotifier {
  /// Clear all batch selections
  void clearBatchSelection() {
    _batchPaths.clear();
    notifyListeners();
  }
  
  /// Get count of selected books
  int get batchSelectionCount => _batchPaths.length;
}
```

## Error Handling

### Sidebar Resize Errors

**Scenario:** User drags resize handle beyond screen bounds

**Handling:**
- Clamp width to `max(minWidth, min(maxWidth, dragPosition))`
- Prevent negative widths or widths exceeding screen width
- If drag position < minWidth, snap to minWidth
- If drag position > maxWidth, snap to maxWidth

**Code:**
```dart
void _onPanUpdate(DragUpdateDetails details) {
  setState(() {
    final newWidth = _currentWidth + details.delta.dx;
    _currentWidth = newWidth.clamp(widget.minWidth, widget.maxWidth);
  });
}
```

### Preferences Persistence Errors

**Scenario:** SharedPreferences fails to save/load

**Handling:**
- Wrap all PreferencesService calls in try-catch
- On save failure: log error but continue (non-critical)
- On load failure: use default values (300px for sidebar)
- No user-facing error messages (graceful degradation)

**Code:**
```dart
Future<void> _restoreSidebarWidth() async {
  try {
    final width = await PreferencesService.loadSidebarWidth();
    if (width != null) {
      setState(() => _sidebarWidth = width);
    }
  } catch (e) {
    // Use default width (300px)
    debugPrint('Failed to load sidebar width: $e');
  }
}
```

### Cover Thumbnail Loading Errors

**Scenario:** Cover image file is missing or corrupted

**Handling:**
- Use `Image.file` with `errorBuilder` parameter
- On error: display placeholder icon instead
- No error messages (visual fallback is sufficient)

**Code:**
```dart
Widget build(BuildContext context) {
  if (book.coverImagePath != null) {
    return Image.file(
      File(book.coverImagePath!),
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Icon(Icons.book, size: size * 0.6, color: Colors.grey);
      },
    );
  }
  return Icon(Icons.book, size: size * 0.6, color: Colors.grey);
}
```

### Batch Selection Edge Cases

**Scenario:** User selects books, then filters/searches to hide them

**Handling:**
- Keep selections in `_batchPaths` even if filtered out
- Banner shows total selection count (not just visible)
- "Clear selection" clears all, including hidden selections
- When user removes filter, selections remain

**Rationale:** Matches Gmail behavior — selections persist across view changes

## Testing Strategy

This feature involves UI layout, interaction patterns, and state management. Testing will use a combination of widget tests, integration tests, and manual testing.

### Widget Tests

**Purpose:** Verify individual widget behavior and rendering

**Test Cases:**

1. **ResizableSidebar Widget**
   - Renders child widget with initial width
   - Shows resize handle at bottom
   - Clamps width to min/max bounds during drag
   - Calls onWidthChanged callback on drag end

2. **SortButton Widget**
   - Displays correct label for each SortOrder enum value
   - Shows dropdown menu on click
   - Calls onOrderChanged callback when option selected

3. **BatchSelectionBanner Widget**
   - Displays correct selection count
   - Shows "Clear selection" and "Edit all" buttons
   - Calls appropriate callbacks when buttons clicked

4. **CoverThumbnail Widget**
   - Displays image when coverImageBytes present
   - Displays image when coverImagePath present
   - Displays placeholder icon when no cover
   - Handles image loading errors gracefully

5. **Search Clear Button**
   - Clear button appears when text present
   - Clear button hidden when text empty
   - Clicking clear button clears text and refocuses field

6. **Always-Visible Filter Chips**
   - Both chips always rendered
   - Chips disabled when count is 0
   - Chips enabled when count > 0
   - Clicking enabled chip toggles filter

### Integration Tests

**Purpose:** Verify end-to-end workflows and state management

**Test Cases:**

1. **Sidebar Resize Persistence**
   - Resize sidebar to 400px
   - Restart app
   - Verify sidebar width is 400px

2. **Batch Selection Flow**
   - Select 2 books
   - Verify banner appears
   - Click "Clear selection"
   - Verify banner disappears and selections cleared

3. **Search with Clear**
   - Type search query
   - Verify results filtered
   - Click clear button
   - Verify search cleared and all books shown

4. **Sort Order Persistence**
   - Change sort order to "Author A-Z"
   - Restart app
   - Verify sort order is "Author A-Z"

5. **Filter Chip Interaction**
   - Enable "Dupes" filter
   - Verify only duplicate books shown
   - Enable "No cover" filter
   - Verify only books without covers shown
   - Disable both filters
   - Verify all books shown

### Manual Testing Checklist

**UI Layout:**
- [ ] Action bar has exactly 6 items in correct order
- [ ] View toggle positioned above form fields
- [ ] Filter chips always visible (not jumping)
- [ ] Batch banner appears when 2+ books selected
- [ ] Checkboxes in trailing position
- [ ] Cover thumbnails display correctly

**Interaction:**
- [ ] Sidebar resizes smoothly between 250-500px
- [ ] Resize handle has correct cursor (ew-resize)
- [ ] Search clear button appears/disappears correctly
- [ ] Sort button shows current order
- [ ] More menu contains Export and Rename actions
- [ ] Batch banner buttons work correctly

**Keyboard Navigation:**
- [ ] Tab order flows logically through action bar
- [ ] Tab skips sidebar (ExcludeFocus)
- [ ] Tab moves through form fields in order
- [ ] Enter key activates focused button

**Persistence:**
- [ ] Sidebar width persists across sessions
- [ ] Sort order persists across sessions
- [ ] Window bounds persist across sessions

**Edge Cases:**
- [ ] Sidebar resize works at screen edges
- [ ] Batch selection persists when filtering
- [ ] Cover thumbnails handle missing files
- [ ] Long book titles truncate properly
- [ ] Filter chips work when counts are 0

### Performance Testing

**Cover Thumbnail Loading:**
- Test with library of 1000+ books
- Verify smooth scrolling (no jank)
- Verify memory usage stays reasonable
- Verify lazy loading works (images load as scrolled into view)

**Sidebar Resize:**
- Test rapid dragging
- Verify no lag or stuttering
- Verify preferences save doesn't block UI

## Implementation Considerations

### Phase 1: Action Bar Reorganization (Low Risk)

**Files:** `lib/screens/book_detail_screen.dart`

**Changes:**
1. Move Export dropdown to More menu
2. Move Rename to More menu
3. Reorder action bar widgets
4. Move view toggle above form fields

**Risks:** Low — purely layout changes, no state management

**Testing:** Widget tests for action bar layout

### Phase 2: Sidebar Improvements (Medium Risk)

**Files:** `lib/main.dart`

**Changes:**
1. Replace sort icon with SortButton widget
2. Make filter chips always visible
3. Add search clear button
4. Add cover thumbnails to book list

**Risks:** Medium — filter chip logic change could affect filtering behavior

**Testing:** Widget tests + integration tests for filtering

### Phase 3: Batch Selection (Medium Risk)

**Files:** `lib/main.dart`, `lib/controllers/library_controller.dart`

**Changes:**
1. Move checkbox to trailing position
2. Add BatchSelectionBanner widget
3. Add clearBatchSelection method to controller

**Risks:** Medium — changes to selection UI could confuse users

**Testing:** Integration tests for batch selection flow

### Phase 4: Resizable Sidebar (High Risk)

**Files:** `lib/main.dart`, `lib/services/preferences_service.dart`

**Changes:**
1. Create ResizableSidebar widget
2. Add sidebar width state to HomeScreen
3. Add resize handle with GestureDetector
4. Add preferences methods for sidebar width
5. Restore sidebar width on launch

**Risks:** High — complex gesture handling, state management, persistence

**Testing:** Widget tests + integration tests + manual testing

### Phase 5: Polish (Low Risk)

**Files:** Multiple

**Changes:**
1. Verify tab order with FocusTraversalGroup
2. Test all interactions
3. Update CHANGELOG.md

**Risks:** Low — final verification and documentation

**Testing:** Manual testing checklist

### Technical Decisions

#### Decision 1: Sidebar Resize Implementation

**Options:**
1. Use `GestureDetector` with `onPanUpdate`
2. Use `Draggable` widget
3. Use third-party package (e.g., `flutter_resizable_container`)

**Choice:** Option 1 (GestureDetector)

**Rationale:**
- Most control over behavior
- No external dependencies
- Simple implementation for horizontal resize
- Easy to add constraints (min/max width)

#### Decision 2: Cover Thumbnail Size

**Options:**
1. 24x24 (very small, minimal space)
2. 32x32 (small, readable)
3. 48x48 (medium, prominent)

**Choice:** Option 2 (32x32)

**Rationale:**
- Large enough to recognize covers
- Small enough to not dominate list
- Matches common UI patterns (Gmail, Spotify)
- Fits well with existing ListTile height

#### Decision 3: Filter Chip Disabled State

**Options:**
1. Hide chips when count is 0
2. Show chips grayed out when count is 0
3. Show chips but disable interaction when count is 0

**Choice:** Option 3 (show + disable)

**Rationale:**
- Prevents layout shift (always same height)
- Communicates feature exists even when not applicable
- Matches Material Design disabled state pattern
- Users learn about feature even when not using it

#### Decision 4: Batch Banner Position

**Options:**
1. Top of sidebar (above toolbar)
2. Top of detail panel (above book detail)
3. Bottom of screen (floating)

**Choice:** Option 2 (top of detail panel)

**Rationale:**
- Affects detail panel (where batch edit happens)
- Doesn't interfere with sidebar scrolling
- Matches Gmail pattern (banner above content)
- Clear visual connection to affected area

#### Decision 5: View Toggle Position

**Options:**
1. Keep in action bar (current)
2. Move above form fields
3. Move to tab bar area

**Choice:** Option 2 (above form fields)

**Rationale:**
- Directly affects form field content
- Frees up action bar space
- Clearer cause-effect relationship
- Matches "controls near affected content" pattern

### Migration Strategy

**Backward Compatibility:**
- All existing preferences remain compatible
- New preferences (sidebar width) have sensible defaults
- No database migrations required
- No breaking changes to existing features

**Rollout Plan:**
1. Implement phases 1-2 (low/medium risk) first
2. Release beta for testing
3. Implement phases 3-4 (medium/high risk)
4. Release beta for testing
5. Implement phase 5 (polish)
6. Release stable version

**Rollback Plan:**
- Each phase is independently revertible
- Preferences changes are additive (no deletions)
- If critical bug found, can disable specific features via feature flags

### Accessibility Considerations

**Keyboard Navigation:**
- All interactive elements accessible via Tab key
- Logical tab order (left-to-right, top-to-bottom)
- Sidebar excluded from tab order (ExcludeFocus)
- Resize handle accessible via keyboard (future enhancement)

**Screen Readers:**
- All buttons have semantic labels (tooltip parameter)
- Batch banner announces selection count
- Filter chips announce enabled/disabled state
- Cover thumbnails have semantic labels

**Visual:**
- Sufficient color contrast for all text
- Disabled state clearly indicated (grayed out)
- Focus indicators visible on all interactive elements
- Resize handle has clear visual affordance

**Motor:**
- Resize handle has large hit area (full width of sidebar)
- Buttons have minimum 44x44 touch target
- No time-based interactions
- No precision-required gestures

## Correctness Properties

**Property-based testing is not applicable to this feature.**

This feature focuses on UI layout, visual design, and interaction patterns rather than algorithmic logic or data transformations. The appropriate testing approach uses:

- **Widget tests** for component rendering and behavior
- **Integration tests** for end-to-end workflows
- **Manual testing** for visual verification and user experience validation
- **Snapshot tests** (optional) for layout regression detection

Property-based testing is designed for testing universal properties across large input spaces (parsers, serializers, algorithms, business logic). UI layout and interaction patterns are better validated through example-based tests with specific scenarios and visual inspection.

## Summary

This design implements a cohesive design system that addresses all 10 requirements through systematic application of industry-standard UI patterns. The implementation is phased to minimize risk, with low-risk layout changes first, followed by medium-risk state management changes, and finally high-risk gesture handling.

The design maintains backward compatibility with existing features and preferences while adding new capabilities. All changes are independently testable and revertible.

Key technical decisions prioritize simplicity (GestureDetector over third-party packages), consistency (Material Design patterns), and user experience (always-visible filter chips, trailing checkboxes, clear visual hierarchy).

The result is a more discoverable, adaptable, and predictable UI that reduces cognitive load and improves user efficiency.
