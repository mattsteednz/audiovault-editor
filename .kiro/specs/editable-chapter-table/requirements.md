# Requirements Document

## Introduction

The Editable Chapter Table feature extends the existing read-only chapter display in AudioVault Editor's Chapters tab into a fully interactive editing surface. Users can add, insert, reorder, and delete chapters; edit start times for single-file books (M4B and MP3); paste chapter lists in bulk via a Quick Edit text area; and export chapters as a `.cue` sheet for MP3 single-file books. Duration values are always derived automatically and are never directly editable. The feature targets the common workflow of filling in missing or incorrect chapter metadata for audiobooks stored as a single audio file.

---

## Glossary

- **Chapter_Table**: The interactive table widget rendered inside the Chapters tab of `BookDetailScreen`.
- **Chapter_Row**: A single row in the Chapter_Table representing one chapter, containing an index, editable title, editable or read-only start time, derived duration, and a delete button.
- **Quick_Edit_Panel**: A text area that represents all chapters as plain text lines in `Title, HH:MM:SS` format, used for bulk paste and edit.
- **Chapter_Editor**: The combined state that owns the chapter list and mediates between the Chapter_Table and the Quick_Edit_Panel.
- **Single_File_Book**: An `Audiobook` whose `audioFiles` list contains exactly one file (M4B, M4A, or MP3) and whose chapter data is stored in `book.chapters` (embedded start times).
- **Multi_File_Book**: An `Audiobook` whose `audioFiles` list contains more than one file, using `chapterNames` and `chapterDurations` (no start times).
- **Start_Time**: The `Duration` offset from the beginning of the audio file at which a chapter begins.
- **Derived_Duration**: The duration of a chapter computed as the difference between the chapter's Start_Time and the next chapter's Start_Time, or the difference between the book's total duration and the last chapter's Start_Time.
- **CUE_Sheet**: A plain-text file in the CD-DA CUE format describing track positions within a single audio file, using `MM:SS:FF` frame notation at 75 frames per second.
- **Timestamp_Conflict**: A state where two or more chapters share the same Start_Time, or where a chapter's Start_Time is greater than or equal to the following chapter's Start_Time.
- **Undo_Stack**: The existing undo mechanism in AudioVault Editor that records `Audiobook` snapshots before each `_apply()` call.

---

## Requirements

### Requirement 1: Pre-populate Chapter_Table from existing data

**User Story:** As an editor, I want the Chapter_Table to show all existing chapter data when I open a book, so that I can see what is already embedded before making changes.

#### Acceptance Criteria

1. WHEN a Single_File_Book is opened and `book.chapters` is non-empty, THE Chapter_Editor SHALL populate the Chapter_Table with one Chapter_Row per entry in `book.chapters`, preserving title and Start_Time.
2. WHEN a Multi_File_Book is opened, THE Chapter_Editor SHALL populate the Chapter_Table with one Chapter_Row per audio file, using `chapterNames` for titles and `chapterDurations` for durations, with Start_Time cells hidden.
3. WHEN a Single_File_Book is opened and `book.chapters` is empty, THE Chapter_Editor SHALL display an empty Chapter_Table with a prompt to add the first chapter.
4. THE Chapter_Table SHALL display Derived_Duration for each Chapter_Row, computed from adjacent Start_Times and `book.duration`.

---

### Requirement 2: Editable chapter titles

**User Story:** As an editor, I want to type directly into each chapter's title cell, so that I can correct or fill in chapter names without leaving the table.

#### Acceptance Criteria

1. THE Chapter_Table SHALL render each chapter title as an inline `TextField` that accepts free-form text input.
2. WHEN a title `TextField` is modified, THE Chapter_Editor SHALL mark the form as dirty and enable the Apply button, consistent with the existing dirty-state mechanism.
3. THE Chapter_Table SHALL preserve cursor position and focus when the table re-renders due to other state changes (e.g., a row being added or deleted elsewhere in the list).

---

### Requirement 3: Editable start times for Single_File_Books

**User Story:** As an editor, I want to set the exact start time for each chapter in a single-file book, so that chapter markers land at the correct positions in the audio.

#### Acceptance Criteria

1. WHILE the book is a Single_File_Book, THE Chapter_Table SHALL render each chapter's Start_Time as an editable `TextField` accepting `MM:SS`, `HH:MM:SS`, or `MMM:SS` format (where MMM is minutes > 99).
2. WHILE the book is a Multi_File_Book, THE Chapter_Table SHALL hide the Start_Time column entirely, showing only #, Title, Duration, and File columns.
3. THE Chapter_Table SHALL lock the first chapter's Start_Time field to `00:00:00` and prevent user edits to that field.
4. WHEN a Start_Time `TextField` loses focus or the user presses Enter, THE Chapter_Editor SHALL parse the entered text, reformat it to `HH:MM:SS` format, and update the chapter's Start_Time.
5. IF the entered Start_Time text does not match `MM:SS`, `HH:MM:SS`, or `MMM:SS` format, THEN THE Chapter_Editor SHALL display an inline validation error beneath the field and revert the field to the previous valid value.
6. WHEN a Start_Time is updated, THE Chapter_Editor SHALL recompute Derived_Duration for the affected chapter and its predecessor.
7. THE Chapter_Table SHALL display Derived_Duration as read-only text; the Derived_Duration cell SHALL NOT contain an editable field.
8. FOR Multi_File_Books, THE Chapter_Table SHALL display duration values derived from `chapterDurations` without any start time calculation.

---

### Requirement 4: Timestamp conflict resolution

**User Story:** As an editor, I want the app to prevent overlapping chapter timestamps, so that the resulting chapter list is always valid.

#### Acceptance Criteria

1. WHEN the user commits a Start_Time that is less than or equal to the preceding chapter's Start_Time, THE Chapter_Editor SHALL display an inline error on the conflicting field and prevent the value from being applied until corrected.
2. WHEN the user commits a Start_Time that is greater than or equal to the following chapter's Start_Time, THE Chapter_Editor SHALL display an inline error on the conflicting field and prevent the value from being applied until corrected.
3. THE Chapter_Editor SHALL enforce that all Start_Times in the list are strictly ascending before the Apply button becomes active.
4. IF a Timestamp_Conflict exists in the chapter list, THEN THE Chapter_Editor SHALL disable the Apply button and display a summary error message in the Chapters tab toolbar.
5. THE Chapter_Editor SHALL NOT auto-reorder chapters to resolve conflicts; the user must manually correct conflicting values.

---

### Requirement 5: Add chapter at end

**User Story:** As an editor, I want to add a new chapter at the bottom of the list, so that I can extend the chapter count for books with missing chapters.

#### Acceptance Criteria

1. THE Chapter_Table SHALL display an "Add chapter" button below the last Chapter_Row.
2. WHEN the "Add chapter" button is pressed, THE Chapter_Editor SHALL append a new Chapter_Row with an empty title and a Start_Time set to the end of the last chapter's Derived_Duration (i.e., the previous chapter's Start_Time plus its Derived_Duration), or `00:00:00` if the table is empty.
3. WHEN a new Chapter_Row is appended, THE Chapter_Editor SHALL set focus to the new row's title `TextField`.
4. WHEN a new Chapter_Row is appended to a Single_File_Book, THE Chapter_Editor SHALL mark the form as dirty.

---

### Requirement 6: Insert chapter between rows

**User Story:** As an editor, I want to insert a chapter between two existing chapters, so that I can add a missing chapter without disrupting the rest of the list.

#### Acceptance Criteria

1. THE Chapter_Table SHALL display a horizontal divider with a `(+)` icon button between each pair of adjacent Chapter_Rows.
2. WHEN the `(+)` icon button between row N and row N+1 is pressed, THE Chapter_Editor SHALL insert a new Chapter_Row at position N+1 with an empty title and a Start_Time set to the midpoint between the surrounding chapters' Start_Times (for Single_File_Books), or with an empty title and zero duration (for Multi_File_Books).
3. WHEN a Chapter_Row is inserted, THE Chapter_Editor SHALL renumber all subsequent rows and set focus to the inserted row's title `TextField`.
4. WHEN a Chapter_Row is inserted into a Single_File_Book, THE Chapter_Editor SHALL recompute Derived_Duration for the row immediately before the insertion point.

---

### Requirement 7: Delete chapter row

**User Story:** As an editor, I want to delete a chapter row, so that I can remove incorrectly split or duplicate chapters.

#### Acceptance Criteria

1. THE Chapter_Table SHALL display a delete icon button on each Chapter_Row.
2. WHEN the delete button on a Chapter_Row is pressed and the table contains more than one row, THE Chapter_Editor SHALL remove that row, renumber remaining rows, and recompute Derived_Duration for the row that now precedes the deleted row's position.
3. WHEN the delete button is pressed and the table contains exactly one row, THE Chapter_Editor SHALL ignore the action and display a tooltip stating that at least one chapter is required.
4. WHEN a Chapter_Row is deleted, THE Chapter_Editor SHALL mark the form as dirty.
5. IF the table is reduced to exactly one row, THE Chapter_Editor SHALL ensure that row has Start_Time `00:00:00` and Derived_Duration equal to `book.duration`.

---

### Requirement 8: Quick Edit Panel

**User Story:** As an editor, I want to paste a list of chapter titles and timestamps into a text area, so that I can populate many chapters at once without clicking through the table row by row.

#### Acceptance Criteria

1. THE Chapter_Table toolbar SHALL contain a "Quick Edit" button that opens the Quick_Edit_Panel as a modal dialog.
2. WHEN the Quick_Edit_Panel modal opens, THE Chapter_Editor SHALL pre-populate it with the current chapter list serialised as one line per chapter in the format `Title, HH:MM:SS`.
3. THE Quick_Edit_Panel SHALL accept lines in `Title, MM:SS`, `Title, HH:MM:SS`, or `Title, MMM:SS` format, where the timestamp is optional for Multi_File_Books.
4. THE Quick_Edit_Panel SHALL treat the right-most comma on each line as the separator between title and timestamp, so that titles containing commas are handled correctly. Quoted titles (using `"`) SHALL also be supported as an alternative.
5. WHEN the Quick_Edit_Panel text is parsed and a line does not match the expected format, THE Chapter_Editor SHALL highlight that line with an inline error annotation identifying the line number and the specific format violation.
6. WHEN the user confirms the Quick_Edit_Panel (clicks Save), THE Chapter_Editor SHALL validate the full chapter list for format errors and Timestamp_Conflicts before accepting it.
7. IF validation passes, THE Chapter_Editor SHALL replace the chapter list with the parsed entries, close the modal, mark the form as dirty, and re-render the Chapter_Table.
8. IF validation fails, THE Chapter_Editor SHALL keep the modal open, display all errors inline, and prevent saving until all errors are resolved.
9. WHEN the user cancels the Quick_Edit_Panel modal, THE Chapter_Editor SHALL discard all changes and restore the chapter list to its state before the modal was opened.
10. THE Quick_Edit_Panel SHALL support a minimum of 200 lines without performance degradation.

---

### Requirement 9: Quick Edit data integrity

**User Story:** As an editor, I want the Quick Edit modal to always reflect the current table state and save back cleanly, so that both views are always in sync.

#### Acceptance Criteria

1. WHEN the Quick_Edit_Panel modal opens, THE Chapter_Editor SHALL always regenerate its text from the current in-memory chapter list, so the modal always reflects the latest table state.
2. WHEN the user saves the Quick_Edit_Panel, THE Chapter_Editor SHALL replace the entire in-memory chapter list with the parsed result and re-render the Chapter_Table from scratch.
3. THE Quick_Edit_Panel modal SHALL NOT allow saving if any line has a format error or any Timestamp_Conflict exists in the parsed list.

---

### Requirement 10: CUE sheet export

**User Story:** As an editor, I want to export a `.cue` sheet for a single-file MP3 book, so that players that do not support embedded chapter atoms can still navigate chapters.

#### Acceptance Criteria

1. WHILE the book is a Single_File_Book with an MP3 audio file, THE Chapter_Table toolbar SHALL display an "Export CUE" button.
2. WHEN the "Export CUE" button is pressed, THE Chapter_Editor SHALL write a `.cue` file to the book's folder using the filename `<book_title>.cue`.
3. THE CUE_Sheet SHALL contain a `FILE` directive referencing the MP3 filename, one `TRACK` block per chapter with an `INDEX 01` position in `MM:SS:FF` format at 75 frames per second, and a `TITLE` field per track populated from the chapter title.
4. WHEN converting a chapter's Start_Time to CUE frame notation, THE Chapter_Editor SHALL compute frames as `round(milliseconds_remainder * 75 / 1000)`, clamped to the range [0, 74].
5. WHEN the CUE file is written successfully, THE Chapter_Editor SHALL update `book.hasCue` to `true` and display a success snackbar.
6. IF the CUE file cannot be written due to a filesystem error, THEN THE Chapter_Editor SHALL display an error snackbar with the error message.
7. WHILE the book is a Multi_File_Book or a Single_File_Book with a non-MP3 file, THE Chapter_Table toolbar SHALL NOT display the "Export CUE" button.

---

### Requirement 11: Undo/redo for chapter edits

**User Story:** As an editor, I want to undo and redo chapter edits before saving, so that I can experiment with chapter structures without committing to disk.

#### Acceptance Criteria

1. THE Chapter_Editor SHALL maintain a local undo/redo stack of chapter list snapshots, separate from the global Undo_Stack.
2. WHEN the user makes any change to the chapter list (add, insert, delete, title edit, start time edit, or Quick Edit save), THE Chapter_Editor SHALL push the previous chapter list state onto the local undo stack and clear the redo stack.
3. THE Chapter_Table toolbar SHALL display Undo and Redo icon buttons for the local chapter undo/redo stack.
4. WHEN the Undo button is pressed and the local undo stack is non-empty, THE Chapter_Editor SHALL restore the previous chapter list state and push the current state onto the redo stack.
5. WHEN the Redo button is pressed and the redo stack is non-empty, THE Chapter_Editor SHALL restore the next chapter list state and push the current state onto the undo stack.
6. WHEN the Undo or Redo button is pressed, THE Chapter_Editor SHALL recompute all Derived_Durations and re-render the Chapter_Table.
7. THE local undo/redo stack SHALL be cleared when the user clicks Apply (changes are committed) or when a different book is selected.
8. WHEN the Apply button is pressed, THE Chapter_Editor SHALL pass the final chapter list to `widget.onApply`, which records the snapshot on the global Undo_Stack as before.

---

### Requirement 12: Large chapter list performance

**User Story:** As an editor, I want the chapter table to remain responsive for books with 50 or more chapters, so that editing large audiobooks is not sluggish.

#### Acceptance Criteria

1. THE Chapter_Table SHALL render chapter rows inside a scrollable viewport so that the table does not overflow the screen for any chapter count.
2. WHEN the Chapter_Table contains 50 or more Chapter_Rows, THE Chapter_Table SHALL remain interactive (title edits, row insertion, deletion) with no perceptible input lag on a standard desktop machine.
3. THE Quick_Edit_Panel SHALL use a single `TextField` widget (not one widget per line) to avoid widget-tree overhead for large chapter counts.

---

### Requirement 13: Adding chapters to a book that had none

**User Story:** As an editor, I want to add chapters to a Single_File_Book that has no embedded chapter data, so that I can create a chapter structure from scratch.

#### Acceptance Criteria

1. WHEN a Single_File_Book has an empty `book.chapters` list, THE Chapter_Table SHALL display the "Add chapter" button and the Quick_Edit_Panel toggle, enabling the user to create chapters from scratch.
2. WHEN the first chapter is added to a previously chapter-less Single_File_Book, THE Chapter_Editor SHALL initialise that chapter with title `""` and Start_Time `00:00:00`.
3. WHEN the Apply button is pressed after chapters have been added to a previously chapter-less Single_File_Book, THE Chapter_Editor SHALL include the new chapters in the `Audiobook` passed to `widget.onApply`, so that downstream writers (e.g., `Mp4Writer`) can embed them.
