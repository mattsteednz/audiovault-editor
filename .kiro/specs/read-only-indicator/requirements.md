# Requirements Document: Read-Only Indicator

## Introduction

When AudioVault Editor scans an audiobook folder, it reads metadata from audio files, OPF files, and cover images. If the folder or any of its files are set to read-only at the OS level, any attempt to save metadata changes will silently fail or produce an error. This feature adds read-only permission detection to the scan process and surfaces a clear visual indicator in the UI so users know upfront that editing or saving metadata may not be possible for a given book.

The detection runs during scanning (both full library scans and single-book rescans) and the result is stored on the `Audiobook` model. The indicator is shown in the book list sidebar and in the book detail panel.

## Glossary

- **Scanner_Service**: The `ScannerService` class in `lib/services/scanner_service.dart` responsible for discovering and reading audiobook folders
- **Audiobook**: The data model in `lib/models/audiobook.dart` representing a single scanned audiobook
- **Library_Controller**: The `LibraryController` class in `lib/controllers/library_controller.dart` that manages the list of scanned books and drives UI state
- **Book_Detail_Screen**: The right-hand panel (`BookDetailScreen`) showing metadata fields and actions for the selected book
- **Book_List**: The `ListView` in the sidebar showing all scanned books with title, author, and status icons
- **Read_Only_Status**: An enumeration of three states — `writable`, `folderReadOnly`, and `filesReadOnly` — describing the write-permission state of a scanned audiobook folder
- **Permission_Check**: A filesystem operation that tests whether a file or directory can be written to by the current OS user
- **Read_Only_Badge**: A small icon or chip displayed in the UI to indicate that a book's folder or files are read-only
- **Action_Bar**: The horizontal toolbar in `BookDetailScreen` containing the Apply, Undo, Rescan, and other action buttons

## Requirements

### Requirement 1: Read-Only Status Detection During Scan

**User Story:** As a user, I want the scanner to detect read-only permissions on audiobook folders and files, so that I am informed before I attempt to edit metadata.

#### Acceptance Criteria

1. WHEN the Scanner_Service scans a subfolder, THE Scanner_Service SHALL check whether the folder itself is writable by the current OS user
2. WHEN the Scanner_Service scans a subfolder, THE Scanner_Service SHALL check whether each audio file in the folder is writable by the current OS user
3. IF the folder is not writable, THEN THE Scanner_Service SHALL set the Audiobook's Read_Only_Status to `folderReadOnly`
4. IF the folder is writable but one or more audio files are not writable, THEN THE Scanner_Service SHALL set the Audiobook's Read_Only_Status to `filesReadOnly`
5. IF the folder and all audio files are writable, THEN THE Scanner_Service SHALL set the Audiobook's Read_Only_Status to `writable`
6. THE Scanner_Service SHALL perform the Permission_Check without modifying any files on disk
7. WHEN a single-book rescan is performed via `scanBook`, THE Scanner_Service SHALL apply the same Read_Only_Status detection logic

### Requirement 2: Read-Only Status Stored on the Audiobook Model

**User Story:** As a developer, I want the read-only status to be part of the Audiobook model, so that any part of the UI can access it without re-checking the filesystem.

#### Acceptance Criteria

1. THE Audiobook model SHALL include a `readOnlyStatus` field of type `ReadOnlyStatus`
2. THE `readOnlyStatus` field SHALL default to `writable` when not explicitly set
3. THE Audiobook `copyWith` method SHALL support updating the `readOnlyStatus` field
4. WHEN the Library_Controller updates a book via `onBookApplied` or `onBookRenamed`, THE Library_Controller SHALL preserve the existing `readOnlyStatus` value from the updated Audiobook

### Requirement 3: Read-Only Indicator in the Book List

**User Story:** As a user, I want to see a read-only indicator next to a book in the sidebar list, so that I can identify read-only books at a glance without opening them.

#### Acceptance Criteria

1. WHEN a book's Read_Only_Status is `folderReadOnly` or `filesReadOnly`, THE Book_List SHALL display a Read_Only_Badge icon next to that book's title row
2. WHEN a book's Read_Only_Status is `writable`, THE Book_List SHALL not display a Read_Only_Badge for that book
3. THE Read_Only_Badge SHALL use a lock icon (`Icons.lock_outline`) rendered at 12 pixels
4. THE Read_Only_Badge SHALL be visually distinct from the existing duplicate-warning and missing-cover icons
5. THE Read_Only_Badge SHALL be positioned in the subtitle row alongside the existing status icons

### Requirement 4: Read-Only Indicator in the Book Detail Panel

**User Story:** As a user, I want to see a clear read-only warning in the book detail panel, so that I understand why saving may fail before I make edits.

#### Acceptance Criteria

1. WHEN the selected book's Read_Only_Status is `folderReadOnly`, THE Book_Detail_Screen SHALL display a Read_Only_Badge with the tooltip text "Folder is read-only — metadata changes cannot be saved"
2. WHEN the selected book's Read_Only_Status is `filesReadOnly`, THE Book_Detail_Screen SHALL display a Read_Only_Badge with the tooltip text "One or more audio files are read-only — metadata changes cannot be saved"
3. WHEN the selected book's Read_Only_Status is `writable`, THE Book_Detail_Screen SHALL not display a Read_Only_Badge
4. THE Read_Only_Badge in the Book_Detail_Screen SHALL be displayed in the summary header area, near the book title
5. THE Read_Only_Badge in the Book_Detail_Screen SHALL use a lock icon (`Icons.lock_outline`) with an amber colour to draw attention

### Requirement 5: Apply Button Disabled for Read-Only Books

**User Story:** As a user, I want the Apply button to be disabled when a book is read-only, so that I am not misled into thinking my changes will be saved.

#### Acceptance Criteria

1. WHEN the selected book's Read_Only_Status is `folderReadOnly` or `filesReadOnly`, THE Action_Bar SHALL disable the Apply button
2. WHEN the selected book's Read_Only_Status is `writable`, THE Action_Bar SHALL enable the Apply button according to existing dirty-state logic
3. WHEN the Apply button is disabled due to read-only status, THE Apply button SHALL display the tooltip "Cannot save — folder or files are read-only"
4. THE disabling of the Apply button SHALL not affect the Undo, Rescan, or other action buttons

### Requirement 6: Read-Only Filter Chip in the Sidebar

**User Story:** As a user, I want to filter the book list to show only read-only books, so that I can quickly find and address permission issues across my library.

#### Acceptance Criteria

1. THE Sidebar toolbar SHALL display a "Read-only (N)" Filter_Chip where N is the count of books with a Read_Only_Status of `folderReadOnly` or `filesReadOnly`
2. WHEN the read-only count is 0, THE "Read-only (N)" Filter_Chip SHALL be displayed in a disabled state
3. WHEN the "Read-only (N)" Filter_Chip is selected, THE Book_List SHALL show only books whose Read_Only_Status is `folderReadOnly` or `filesReadOnly`
4. WHEN the "Read-only (N)" Filter_Chip is deselected, THE Book_List SHALL revert to showing all books (subject to other active filters)
5. THE Library_Controller SHALL expose a `readOnlyCount` getter returning the number of books with a non-writable Read_Only_Status
6. THE Library_Controller SHALL expose a `showReadOnlyOnly` boolean getter and a `toggleShowReadOnly` method following the same pattern as `showDuplicatesOnly`
7. WHEN a new scan completes, THE Library_Controller SHALL recompute the read-only count as part of `_recomputeFlags`

### Requirement 7: Read-Only Status Preserved Across Rescan

**User Story:** As a user, I want the read-only status to be refreshed when I rescan a book, so that the indicator reflects the current state of the filesystem.

#### Acceptance Criteria

1. WHEN `rescanSelected` is called on the Library_Controller, THE Scanner_Service SHALL re-evaluate the Read_Only_Status for the rescanned book
2. WHEN the rescanned book's Read_Only_Status changes from a previous value, THE Library_Controller SHALL update the stored Audiobook with the new Read_Only_Status
3. WHEN the rescanned book's Read_Only_Status changes to `writable`, THE Book_Detail_Screen SHALL remove the Read_Only_Badge without requiring a full library rescan

