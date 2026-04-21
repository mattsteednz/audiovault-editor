# Implementation Plan: UX/UI Improvements — Cohesive Design System

## Overview

This implementation plan converts the UX/UI improvements design into actionable coding tasks organized by the 5 implementation phases defined in the design document. Each phase builds incrementally, with low-risk changes first (action bar reorganization) progressing to higher-risk changes (resizable sidebar with gesture handling).

The implementation follows the principle of "Progressive Disclosure with Clear Hierarchy" and applies industry-standard UI patterns from Material Design, iTunes/Music.app, VS Code, and Gmail.

## Tasks

### Phase 1: Action Bar Reorganization (Highest Impact, Lowest Risk)

- [-] 1. Reorganize action bar layout in BookDetailScreen
  - [ ] 1.1 Move Export dropdown to More menu
    - Remove Export dropdown from action bar
    - Add "Export OPF" and "Export Cover" items to More menu PopupMenuButton
    - Disable "Export Cover" when no cover image exists
    - _Requirements: 1.1, 1.4, 1.5_
  
  - [ ] 1.2 Move Rename Folder action to More menu
    - Remove standalone Rename button/trigger from current location
    - Add "Rename folder" item to More menu PopupMenuButton
    - Ensure rename dialog still functions correctly
    - _Requirements: 1.1, 1.4, 1.7_
  
  - [ ] 1.3 Reorder action bar widgets
    - Update Row children order: [Copy from] [More] [Spacer] [Undo] [Rescan] [Apply] [Unsaved text]
    - Verify left-alignment for Copy from and More menu (contextual actions)
    - Verify right-alignment for Undo, Rescan, Apply (primary actions)
    - _Requirements: 1.1, 1.2, 1.3_

- [ ] 2. Relocate view toggle above form fields
  - [ ] 2.1 Remove ToggleButtons from action bar Row
    - Delete ToggleButtons widget from _buildActionBar method
    - _Requirements: 6.1_
  
  - [ ] 2.2 Add view toggle above form fields in book detail panel
    - Insert ToggleButtons widget in Column after header Row, before _buildActionBar
    - Update labels: "Merged metadata" and "File tags only" (instead of "OPF / merged" and "File tags")
    - Maintain existing toggle functionality (_showFileMetadata state)
    - _Requirements: 6.2, 6.3, 6.4, 6.5_

- [ ] 3. Checkpoint - Verify action bar reorganization
  - Ensure all tests pass, ask the user if questions arise.

### Phase 2: Sidebar Improvements (High Impact, Medium Risk)

- [ ] 4. Create SortButton widget
  - [ ] 4.1 Implement SortButton widget in lib/widgets/sort_button.dart
    - Create StatelessWidget with currentOrder and onOrderChanged parameters
    - Display label format: "Sort: [Order] ▼"
    - Implement label mapping from SortOrder enum to display strings
    - Use PopupMenuButton for dropdown menu with all sort options
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_
  
  - [ ]* 4.2 Write widget tests for SortButton
    - Test label displays correctly for each SortOrder enum value
    - Test dropdown menu appears on click
    - Test onOrderChanged callback fires when option selected
    - _Requirements: 7.1, 7.2, 7.3, 7.4_

- [ ] 5. Replace sort icon with SortButton in sidebar
  - [ ] 5.1 Update _buildToolbar in HomeScreen
    - Replace PopupMenuButton icon with SortButton widget
    - Pass _ctrl.sortOrder as currentOrder
    - Pass _ctrl.setSortOrder as onOrderChanged callback
    - _Requirements: 7.5_

- [ ] 6. Make filter chips always visible
  - [ ] 6.1 Update filter chip rendering logic in _buildToolbar
    - Remove conditional wrapping (if statement checking counts > 0)
    - Always render both FilterChip widgets in Wrap
    - Set onSelected to null when count is 0 (disables chip)
    - Set onSelected to toggle callback when count > 0 (enables chip)
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6_

- [ ] 7. Add search clear button
  - [ ] 7.1 Add FocusNode for search field in HomeScreen state
    - Declare _searchFocusNode field
    - Initialize in initState
    - Dispose in dispose method
    - _Requirements: 4.4_
  
  - [ ] 7.2 Add suffixIcon to search TextField
    - Add suffixIcon parameter with conditional IconButton
    - Show clear icon (Icons.clear) when _searchCtrl.text.isNotEmpty
    - Hide suffixIcon when text is empty
    - On click: clear text, call setSearchQuery(''), and refocus field
    - Attach _searchFocusNode to TextField
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

- [ ] 8. Create CoverThumbnail widget
  - [ ] 8.1 Implement CoverThumbnail widget in lib/widgets/cover_thumbnail.dart
    - Create StatelessWidget with book and size parameters (default size: 32)
    - Display Image.memory if book.coverImageBytes exists
    - Display Image.file if book.coverImagePath exists
    - Display placeholder Icon(Icons.book) if no cover
    - Use BoxFit.cover with ClipRRect for rounded corners
    - Add errorBuilder to handle missing/corrupted image files
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6_
  
  - [ ]* 8.2 Write widget tests for CoverThumbnail
    - Test displays image when coverImageBytes present
    - Test displays image when coverImagePath present
    - Test displays placeholder when no cover
    - Test errorBuilder handles image loading errors
    - _Requirements: 8.3, 8.4_

- [ ] 9. Add cover thumbnails to book list
  - [ ] 9.1 Update _buildBookList in HomeScreen
    - Change ListTile leading from Checkbox to CoverThumbnail widget
    - Pass book to CoverThumbnail constructor
    - _Requirements: 8.1, 8.6_

- [ ] 10. Checkpoint - Verify sidebar improvements
  - Ensure all tests pass, ask the user if questions arise.

### Phase 3: Batch Selection (Medium Impact, Medium Risk)

- [ ] 11. Move checkboxes to trailing position
  - [ ] 11.1 Update ListTile in _buildBookList
    - Remove Checkbox from leading parameter
    - Add Checkbox to trailing parameter
    - Maintain existing checkbox functionality (value, onChanged)
    - _Requirements: 5.7_

- [ ] 12. Create BatchSelectionBanner widget
  - [ ] 12.1 Implement BatchSelectionBanner widget in lib/widgets/batch_selection_banner.dart
    - Create StatelessWidget with selectionCount, onClearSelection, onEditAll parameters
    - Display banner with text: "✓ N books selected"
    - Add "Clear selection" TextButton calling onClearSelection
    - Add "Edit all →" FilledButton calling onEditAll
    - Use Material banner styling with light background
    - _Requirements: 5.2, 5.3, 5.4, 5.6_
  
  - [ ]* 12.2 Write widget tests for BatchSelectionBanner
    - Test displays correct selection count
    - Test shows "Clear selection" and "Edit all" buttons
    - Test onClearSelection callback fires when button clicked
    - Test onEditAll callback fires when button clicked
    - _Requirements: 5.2, 5.3, 5.4, 5.6_

- [ ] 13. Add clearBatchSelection method to LibraryController
  - [ ] 13.1 Implement clearBatchSelection in lib/controllers/library_controller.dart
    - Add method that clears _batchPaths set
    - Call notifyListeners after clearing
    - Add batchSelectionCount getter returning _batchPaths.length
    - _Requirements: 5.5_

- [ ] 14. Display batch selection banner in HomeScreen
  - [ ] 14.1 Add BatchSelectionBanner to HomeScreen layout
    - Insert banner in Column above detail panel (before FocusScope)
    - Show banner conditionally when _ctrl.batchPaths.length >= 2
    - Pass _ctrl.batchPaths.length as selectionCount
    - Pass _ctrl.clearBatchSelection as onClearSelection
    - Pass navigation to BatchEditScreen as onEditAll
    - _Requirements: 5.1, 5.8_

- [ ] 15. Checkpoint - Verify batch selection flow
  - Ensure all tests pass, ask the user if questions arise.

### Phase 4: Resizable Sidebar (Medium Impact, High Risk)

- [ ] 16. Add sidebar width preferences to PreferencesService
  - [ ] 16.1 Implement saveSidebarWidth and loadSidebarWidth methods
    - Add _keySidebarWidth constant: 'sidebar_width'
    - Implement saveSidebarWidth(double width) using SharedPreferences.setDouble
    - Implement loadSidebarWidth() returning nullable double from SharedPreferences.getDouble
    - Wrap calls in try-catch for graceful error handling
    - _Requirements: 10.1, 10.2, 10.5_

- [ ] 17. Create ResizableSidebar widget
  - [ ] 17.1 Implement ResizableSidebar widget in lib/widgets/resizable_sidebar.dart
    - Create StatefulWidget with child, initialWidth, minWidth, maxWidth, onWidthChanged parameters
    - Add state fields: _currentWidth, _isDragging
    - Wrap child in SizedBox with _currentWidth
    - Add GestureDetector at bottom for resize handle
    - Implement onPanUpdate to update width (clamped to min/max)
    - Implement onPanEnd to call onWidthChanged callback
    - Display resize handle with horizontal line and ew-resize cursor
    - _Requirements: 2.1, 2.2, 2.3_
  
  - [ ]* 17.2 Write widget tests for ResizableSidebar
    - Test renders child with initial width
    - Test shows resize handle at bottom
    - Test clamps width to min/max bounds during drag
    - Test calls onWidthChanged callback on drag end
    - _Requirements: 2.2, 2.3, 2.4_

- [ ] 18. Integrate ResizableSidebar into HomeScreen
  - [ ] 18.1 Add sidebar width state to HomeScreen
    - Add _sidebarWidth field (default: 300.0)
    - Add _isDraggingResize field (default: false)
    - _Requirements: 2.6_
  
  - [ ] 18.2 Wrap sidebar Column with ResizableSidebar widget
    - Replace SizedBox(width: 300) with ResizableSidebar
    - Pass _sidebarWidth as initialWidth
    - Pass 250 as minWidth, 500 as maxWidth
    - Implement onWidthChanged to update state and persist width
    - _Requirements: 2.1, 2.2, 2.3, 2.4_
  
  - [ ] 18.3 Restore sidebar width on app launch
    - Call PreferencesService.loadSidebarWidth in _restorePreferences
    - Update _sidebarWidth state if saved width exists
    - Use default 300px if no saved width
    - _Requirements: 2.5, 2.6_

- [ ]* 19. Write integration tests for sidebar resize persistence
  - Test resize sidebar to 400px
  - Test restart app and verify sidebar width is 400px
  - Test sidebar width constraints (250-500px)
  - _Requirements: 2.3, 2.4, 2.5_

- [ ] 20. Checkpoint - Verify resizable sidebar functionality
  - Ensure all tests pass, ask the user if questions arise.

### Phase 5: Polish and Finalization

- [ ] 21. Verify keyboard navigation tab order
  - [ ] 21.1 Test tab order in action bar
    - Verify Tab moves through: Copy from → More → Undo → Rescan → Apply
    - Verify Sidebar is excluded from tab order (ExcludeFocus already present)
    - _Requirements: 9.1, 9.2, 9.3_
  
  - [ ] 21.2 Test tab order in book detail form
    - Verify Tab moves through form fields in display order
    - Verify focus indicators visible on all interactive elements
    - _Requirements: 9.4, 9.5_

- [ ]* 22. Run integration tests for complete workflows
  - Test search with clear button workflow
  - Test batch selection flow (select, banner, clear, edit all)
  - Test sort order persistence across sessions
  - Test filter chip interaction (enable/disable filters)
  - _Requirements: 3.1-3.6, 4.1-4.5, 5.1-5.8, 7.1-7.5_

- [ ]* 23. Perform manual testing checklist
  - Verify UI layout matches design (action bar, view toggle, filter chips, batch banner, checkboxes, thumbnails)
  - Test all interactions (sidebar resize, search clear, sort button, more menu, batch banner buttons)
  - Test keyboard navigation (tab order, focus indicators)
  - Test persistence (sidebar width, sort order)
  - Test edge cases (sidebar resize at screen edges, batch selection with filtering, missing cover thumbnails, long book titles)
  - _Requirements: All requirements 1.1-10.5_

- [ ] 24. Update CHANGELOG.md
  - [ ] 24.1 Add entry for UX/UI improvements feature
    - Document all 10 improvements in user-facing language
    - Mention action bar reorganization, resizable sidebar, batch selection banner, etc.
    - Credit design philosophy: "Progressive Disclosure with Clear Hierarchy"
    - _Requirements: All requirements 1.1-10.5_

- [ ] 25. Final checkpoint - Complete feature verification
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation at phase boundaries
- Phase 1-2 are low-risk layout changes; Phase 3-4 involve state management and gesture handling
- All widget tests and integration tests are marked optional but recommended for quality assurance
- Manual testing checklist (task 23) covers visual verification and user experience validation
