# Requirements Document: UX/UI Improvements — Cohesive Design System

## Introduction

This feature implements a cohesive design system for the AudioVault Editor based on the principle of "Progressive Disclosure with Clear Hierarchy." The current UI suffers from overcrowding, hidden functionality, inconsistent visual hierarchy, and unclear interaction patterns. This redesign addresses 8 critical usability issues through systematic application of industry-standard UI patterns (iTunes/Music.app, VS Code, Gmail, Material Design).

The improvements focus on reducing cognitive load, improving discoverability, providing better adaptability, and delivering clearer feedback while maintaining consistency with established desktop application patterns.

## Glossary

- **Action_Bar**: The horizontal toolbar in the book detail screen containing primary actions (Apply, Undo, Rescan) and contextual actions (Copy from, More menu)
- **Sidebar**: The left panel containing the folder picker, search field, sort controls, filter chips, and book list
- **Filter_Chips**: Interactive chips showing "Dupes (N)" and "No cover (N)" that filter the book list
- **Batch_Selection_Banner**: A banner displayed when 2+ books are selected, showing selection count and actions
- **View_Toggle**: A segmented control for switching between "Merged metadata" and "File tags only" views
- **Sort_Button**: A button displaying the current sort order with a dropdown menu for changing it
- **Search_Clear_Button**: An icon button (X) that appears in the search field when text is present
- **Resize_Handle**: A draggable control at the bottom of the sidebar for adjusting sidebar width
- **Cover_Thumbnail**: A 32x32 pixel image displayed to the left of book titles in the sidebar
- **More_Menu**: An overflow menu (⋮) containing infrequent actions like Export and Rename
- **Primary_Actions**: Tier 1 actions that are always visible and right-aligned (Apply, Undo, Rescan)
- **Contextual_Actions**: Tier 2 actions that are left-aligned and context-dependent (Copy from, More menu)
- **Overflow_Actions**: Tier 3 actions hidden in the More menu (Export OPF, Export Cover, Rename Folder)

## Requirements

### Requirement 1: Three-Tier Action Hierarchy

**User Story:** As a user, I want the action bar to be organized by importance and frequency, so that I can quickly find the actions I need without visual clutter.

#### Acceptance Criteria

1. THE Action_Bar SHALL contain exactly 6 visible items: Copy from button, More menu, spacer, Undo button, Rescan button, and Apply button
2. THE Primary_Actions (Apply, Undo, Rescan) SHALL be right-aligned in the Action_Bar
3. THE Contextual_Actions (Copy from, More menu) SHALL be left-aligned in the Action_Bar
4. THE More_Menu SHALL contain Export OPF, Export Cover, and Rename Folder as Overflow_Actions
5. WHEN the More_Menu is opened, THE System SHALL display all Overflow_Actions with appropriate icons
6. THE Export action SHALL be removed from the Action_Bar and split into "Export OPF" and "Export Cover" in the More_Menu
7. THE Rename Folder action SHALL be moved from a separate dialog trigger to the More_Menu

### Requirement 2: Resizable Sidebar with Persistent Width

**User Story:** As a user, I want to resize the sidebar to accommodate long book titles, so that I can see full titles without truncation.

#### Acceptance Criteria

1. THE Sidebar SHALL display a Resize_Handle at its bottom edge
2. WHEN the user drags the Resize_Handle horizontally, THE Sidebar SHALL resize in real-time
3. THE Sidebar width SHALL be constrained between 250 pixels and 500 pixels
4. WHEN the user releases the Resize_Handle, THE System SHALL persist the sidebar width to preferences
5. WHEN the application launches, THE System SHALL restore the sidebar width from preferences
6. IF no saved width exists, THE Sidebar SHALL default to 300 pixels width

### Requirement 3: Always-Visible Filter Chips

**User Story:** As a user, I want filter chips to always be visible, so that the UI doesn't jump when filters become available.

#### Acceptance Criteria

1. THE Filter_Chips SHALL always be rendered in the Sidebar toolbar, regardless of filter counts
2. WHEN a filter count is 0, THE corresponding Filter_Chip SHALL be displayed in a disabled/grayed state
3. WHEN a filter count is greater than 0, THE corresponding Filter_Chip SHALL be displayed in an enabled state
4. THE Filter_Chips SHALL display current counts: "Dupes (N)" and "No cover (N)"
5. WHEN a disabled Filter_Chip is clicked, THE System SHALL not change the filter state
6. THE vertical position of elements below Filter_Chips SHALL remain constant regardless of filter counts

### Requirement 4: Search Clear Button

**User Story:** As a user, I want a clear button in the search field, so that I can quickly clear my search without manually deleting text.

#### Acceptance Criteria

1. WHEN the search field contains text, THE System SHALL display a Search_Clear_Button as a suffix icon
2. WHEN the search field is empty, THE Search_Clear_Button SHALL not be displayed
3. WHEN the Search_Clear_Button is clicked, THE System SHALL clear the search field text
4. WHEN the Search_Clear_Button is clicked, THE System SHALL refocus the search field
5. THE Search_Clear_Button SHALL use an "X" icon

### Requirement 5: Batch Selection Banner with Trailing Checkboxes

**User Story:** As a user, I want clear visual feedback when I'm in batch selection mode, so that I understand I'm editing multiple books and can easily exit that mode.

#### Acceptance Criteria

1. WHEN 2 or more books are selected, THE System SHALL display a Batch_Selection_Banner above the detail panel
2. THE Batch_Selection_Banner SHALL display the selection count: "✓ N books selected"
3. THE Batch_Selection_Banner SHALL contain a "Clear selection" button
4. THE Batch_Selection_Banner SHALL contain an "Edit all →" button
5. WHEN the "Clear selection" button is clicked, THE System SHALL deselect all books and hide the banner
6. WHEN the "Edit all →" button is clicked, THE System SHALL navigate to the batch edit screen
7. THE checkboxes in the book list SHALL be positioned in the trailing (right) position instead of leading (left)
8. WHEN fewer than 2 books are selected, THE Batch_Selection_Banner SHALL not be displayed

### Requirement 6: View Toggle Relocation and Clarity

**User Story:** As a user, I want the view toggle to be positioned near the fields it affects with clearer labels, so that I understand what it controls.

#### Acceptance Criteria

1. THE View_Toggle SHALL be removed from the Action_Bar
2. THE View_Toggle SHALL be positioned above the form fields in the book detail panel
3. THE View_Toggle labels SHALL be "Merged metadata" and "File tags only" instead of "OPF / merged" and "File tags"
4. WHEN the View_Toggle is changed, THE System SHALL update the displayed metadata according to the selected view
5. THE View_Toggle SHALL use a segmented button control (ToggleButtons widget)

### Requirement 7: Sort Button with Visible Current State

**User Story:** As a user, I want to see the current sort order at a glance, so that I don't have to open a menu to check how books are sorted.

#### Acceptance Criteria

1. THE Sort_Button SHALL display a text label showing the current sort order
2. THE Sort_Button label format SHALL be "Sort: [Order] ▼" where [Order] is the current sort (e.g., "Title A-Z", "Author Z-A")
3. WHEN the Sort_Button is clicked, THE System SHALL display a dropdown menu with all sort options
4. WHEN a sort option is selected, THE Sort_Button label SHALL update to reflect the new sort order
5. THE Sort_Button SHALL replace the current icon-only sort PopupMenuButton

### Requirement 8: Cover Thumbnails in Book List

**User Story:** As a user, I want to see small cover images next to book titles in the sidebar, so that I can visually scan and identify books more quickly.

#### Acceptance Criteria

1. THE System SHALL display a Cover_Thumbnail to the left of each book title in the book list
2. THE Cover_Thumbnail SHALL be 32 pixels wide by 32 pixels tall
3. WHEN a book has a cover image, THE Cover_Thumbnail SHALL display that image
4. WHEN a book has no cover image, THE Cover_Thumbnail SHALL display a placeholder icon
5. THE Cover_Thumbnails SHALL be lazy-loaded to minimize memory impact
6. THE Cover_Thumbnail SHALL not interfere with the checkbox or book selection interaction

### Requirement 9: Keyboard Navigation Support

**User Story:** As a user, I want logical tab order through all interactive elements, so that I can efficiently navigate the application using only my keyboard.

#### Acceptance Criteria

1. THE tab order SHALL follow a logical left-to-right, top-to-bottom flow
2. WHEN the user presses Tab in the Action_Bar, THE focus SHALL move from Copy from → More → Undo → Rescan → Apply
3. THE Sidebar SHALL be excluded from the tab order using ExcludeFocus widget
4. THE form fields in the book detail panel SHALL be included in the tab order
5. WHEN the user presses Tab in the book detail form, THE focus SHALL move through fields in display order

### Requirement 10: Preferences Persistence

**User Story:** As a user, I want my sidebar width preference to be saved, so that my layout is preserved across application sessions.

#### Acceptance Criteria

1. THE PreferencesService SHALL provide a saveSidebarWidth method accepting a double value
2. THE PreferencesService SHALL provide a loadSidebarWidth method returning a nullable double
3. WHEN the sidebar is resized, THE System SHALL call saveSidebarWidth with the new width
4. WHEN the application launches, THE System SHALL call loadSidebarWidth and apply the saved width if present
5. THE sidebar width preference SHALL be stored using the key "sidebar_width"

## Special Requirements Guidance

This feature does not include parsers or serializers, so no round-trip testing requirements apply.

## Out of Scope

- Keyboard shortcuts (deferred to PRD-26)
- Grouping or collapsing books in the sidebar
- Advanced filtering beyond existing Dupes and No cover filters
- Customizable action bar layouts
- Sidebar position (left vs right)
- Multiple sidebar panels or tabs
