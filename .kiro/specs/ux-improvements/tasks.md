# Implementation Plan: UX/UI Improvements — Cohesive Design System

## Overview

This implementation plan converts the UX/UI improvements design into actionable coding tasks organized by the 5 implementation phases defined in the design document. Each phase builds incrementally, with low-risk changes first (action bar reorganization) progressing to higher-risk changes (resizable sidebar with gesture handling).

The implementation follows the principle of "Progressive Disclosure with Clear Hierarchy" and applies industry-standard UI patterns from Material Design, iTunes/Music.app, VS Code, and Gmail.

## Tasks

### Phase 1: Action Bar Reorganization (Highest Impact, Lowest Risk)

- [x] 1. Reorganize action bar layout in BookDetailScreen
  - [x] 1.1 Move Export dropdown to More menu
  - [x] 1.2 Move Rename Folder action to More menu
  - [x] 1.3 Reorder action bar widgets

- [x] 2. Relocate view toggle above form fields
  - [x] 2.1 Remove ToggleButtons from action bar Row
  - [x] 2.2 Add view toggle above form fields in book detail panel

- [x] 3. Checkpoint - Verify action bar reorganization

### Phase 2: Sidebar Improvements (High Impact, Medium Risk)

- [x] 4. Create SortButton widget
  - [x] 4.1 Implement SortButton widget in lib/widgets/sort_button.dart

- [x] 5. Replace sort icon with SortButton in sidebar
  - [x] 5.1 Update _buildToolbar in HomeScreen

- [x] 6. Make filter chips always visible
  - [x] 6.1 Update filter chip rendering logic in _buildToolbar

- [x] 7. Add search clear button
  - [x] 7.1 Add FocusNode for search field in HomeScreen state
  - [x] 7.2 Add suffixIcon to search TextField

- [x] 8. Create CoverThumbnail widget
  - [x] 8.1 Implement CoverThumbnail widget in lib/widgets/cover_thumbnail.dart

- [x] 9. Add cover thumbnails to book list
  - [x] 9.1 Update _buildBookList in HomeScreen

- [x] 10. Checkpoint - Verify sidebar improvements

### Phase 3: Batch Selection (Medium Impact, Medium Risk)

- [x] 11. Move checkboxes to trailing position
  - [x] 11.1 Update ListTile in _buildBookList

- [x] 12. Create BatchSelectionBanner widget
  - [x] 12.1 Implement BatchSelectionBanner widget in lib/widgets/batch_selection_banner.dart

- [x] 13. Add clearBatchSelection method to LibraryController
  - [x] 13.1 Implement clearBatchSelection in lib/controllers/library_controller.dart

- [x] 14. Display batch selection banner in HomeScreen
  - [x] 14.1 Add BatchSelectionBanner to HomeScreen layout

- [x] 15. Checkpoint - Verify batch selection flow

### Phase 4: Resizable Sidebar (Medium Impact, High Risk)

- [x] 16. Add sidebar width preferences to PreferencesService
  - [x] 16.1 Implement saveSidebarWidth and loadSidebarWidth methods

- [x] 17. Create ResizableSidebar widget
  - [x] 17.1 Implement ResizableSidebar widget in lib/widgets/resizable_sidebar.dart

- [x] 18. Integrate ResizableSidebar into HomeScreen
  - [x] 18.1 Add sidebar width state to HomeScreen
  - [x] 18.2 Wrap sidebar Column with ResizableSidebar widget
  - [x] 18.3 Restore sidebar width on app launch

- [x] 20. Checkpoint - Verify resizable sidebar functionality

### Phase 5: Polish and Finalization

- [x] 21. Verify keyboard navigation tab order
  - [x] 21.1 Test tab order in action bar
  - [x] 21.2 Test tab order in book detail form

- [x] 24. Update CHANGELOG.md
  - [x] 24.1 Add entry for UX/UI improvements feature

- [x] 25. Final checkpoint - Complete feature verification

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation at phase boundaries
- Phase 1-2 are low-risk layout changes; Phase 3-4 involve state management and gesture handling
- All widget tests and integration tests are marked optional but recommended for quality assurance
- Manual testing checklist (task 23) covers visual verification and user experience validation
