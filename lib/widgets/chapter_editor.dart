import 'package:flutter/material.dart';
import 'package:audiovault_editor/models/audiobook.dart';
import 'package:audiovault_editor/widgets/quick_edit_dialog.dart';
import 'package:path/path.dart' as p;

/// Immutable value object representing one row in the chapter editor.
class ChapterEntry {
  final String title;
  final Duration start;

  const ChapterEntry({required this.title, required this.start});

  ChapterEntry copyWith({String? title, Duration? start}) => ChapterEntry(
        title: title ?? this.title,
        start: start ?? this.start,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChapterEntry &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          start == other.start;

  @override
  int get hashCode => title.hashCode ^ start.hashCode;

  @override
  String toString() => 'ChapterEntry(title: $title, start: $start)';
}

/// Pure Dart controller that owns the chapter list and undo/redo stacks.
///
/// No Flutter imports — fully testable without widget infrastructure.
class ChapterEditorController {
  List<ChapterEntry> entries;
  final List<List<ChapterEntry>> _undoStack = [];
  final List<List<ChapterEntry>> _redoStack = [];

  static const int _maxStackSize = 100;

  ChapterEditorController({List<ChapterEntry>? entries})
      : entries = entries ?? [];

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// True if any entries[i].start >= entries[i+1].start.
  bool get hasConflicts {
    for (int i = 0; i < entries.length - 1; i++) {
      if (entries[i].start >= entries[i + 1].start) return true;
    }
    return false;
  }

  /// Computed derived duration — never stored.
  ///
  /// For index < entries.length - 1: entries[index+1].start - entries[index].start
  /// For last entry: bookDuration - entries[index].start (or null if bookDuration is null)
  Duration? derivedDuration(int index, Duration? bookDuration) {
    if (index < entries.length - 1) {
      return entries[index + 1].start - entries[index].start;
    }
    if (bookDuration != null) {
      return bookDuration - entries[index].start;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  void _pushUndo() {
    _undoStack.add(List.of(entries));
    if (_undoStack.length > _maxStackSize) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------

  /// Appends a new entry with empty title.
  ///
  /// Start = last entry's start + derivedDuration(last, bookDuration),
  /// or Duration.zero if the list is empty.
  void addChapter(Duration? bookDuration) {
    _pushUndo();
    if (entries.isEmpty) {
      entries = [...entries, const ChapterEntry(title: '', start: Duration.zero)];
    } else {
      final lastIndex = entries.length - 1;
      final derived = derivedDuration(lastIndex, bookDuration);
      final newStart = derived != null
          ? entries[lastIndex].start + derived
          : entries[lastIndex].start;
      entries = [...entries, ChapterEntry(title: '', start: newStart)];
    }
  }

  /// Inserts a new entry at afterIndex+1 with empty title.
  ///
  /// Start = midpoint of surrounding entries' starts (integer division of microseconds).
  void insertChapter(int afterIndex) {
    _pushUndo();
    final insertAt = afterIndex + 1;
    final prevStart = entries[afterIndex].start;
    final nextStart = insertAt < entries.length
        ? entries[insertAt].start
        : prevStart; // fallback (shouldn't happen in normal use)
    final midMicros =
        (prevStart.inMicroseconds + nextStart.inMicroseconds) ~/ 2;
    final newEntry = ChapterEntry(
      title: '',
      start: Duration(microseconds: midMicros),
    );
    final newList = List<ChapterEntry>.of(entries);
    newList.insert(insertAt, newEntry);
    entries = newList;
  }

  /// Removes the entry at [index]. No-op if entries.length == 1.
  void deleteChapter(int index) {
    if (entries.length <= 1) return;
    _pushUndo();
    final newList = List<ChapterEntry>.of(entries);
    newList.removeAt(index);
    entries = newList;
  }

  /// Updates the title at [index].
  void updateTitle(int index, String title) {
    _pushUndo();
    final newList = List<ChapterEntry>.of(entries);
    newList[index] = newList[index].copyWith(title: title);
    entries = newList;
  }

  /// Updates the start time at [index].
  ///
  /// Index 0 is silently clamped to Duration.zero.
  void updateStart(int index, Duration start) {
    _pushUndo();
    final newList = List<ChapterEntry>.of(entries);
    newList[index] =
        newList[index].copyWith(start: index == 0 ? Duration.zero : start);
    entries = newList;
  }

  /// Replaces the entire list (used by Quick Edit save).
  void replaceAll(List<ChapterEntry> newEntries) {
    _pushUndo();
    entries = List.of(newEntries);
  }

  // ---------------------------------------------------------------------------
  // Undo / redo
  // ---------------------------------------------------------------------------

  void undo() {
    if (_undoStack.isEmpty) return;
    final snapshot = _undoStack.removeLast();
    _redoStack.add(List.of(entries));
    if (_redoStack.length > _maxStackSize) {
      _redoStack.removeAt(0);
    }
    entries = snapshot;
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    final snapshot = _redoStack.removeLast();
    _undoStack.add(List.of(entries));
    if (_undoStack.length > _maxStackSize) {
      _undoStack.removeAt(0);
    }
    entries = snapshot;
  }

  void clearHistory() {
    _undoStack.clear();
    _redoStack.clear();
  }

  // ---------------------------------------------------------------------------
  // Serialisation
  // ---------------------------------------------------------------------------

  /// Serialises entries to Quick Edit text.
  ///
  /// One line per entry:
  ///   - if includeTimestamps: "Title, HH:MM:SS"
  ///   - else: "Title"
  ///
  /// If title contains a comma, it is wrapped in double quotes.
  /// Placeholder entries (empty title + Duration.zero start) are emitted as
  /// blank lines.
  String toQuickEditText(bool includeTimestamps) {
    final buffer = StringBuffer();
    for (int i = 0; i < entries.length; i++) {
      if (i > 0) buffer.write('\n');
      final entry = entries[i];
      // Placeholder entry (empty title + zero start) → blank line
      if (entry.title.isEmpty && entry.start == Duration.zero) {
        continue; // blank line already written by the '\n' above
      }
      final title =
          entry.title.contains(',') ? '"${entry.title}"' : entry.title;
      if (includeTimestamps) {
        buffer.write('$title, ${formatTimestamp(entry.start)}');
      } else {
        buffer.write(title);
      }
    }
    return buffer.toString();
  }

  /// True if any entry has an empty title, or (when [requireTimestamps] is
  /// true) any non-first entry has a zero start time.
  ///
  /// Used by [ChapterEditor] to block Apply when the chapter list is
  /// incomplete.
  bool hasIncompleteEntries({bool requireTimestamps = false}) {
    for (int i = 0; i < entries.length; i++) {
      if (entries[i].title.trim().isEmpty) return true;
      if (requireTimestamps && i > 0 && entries[i].start == Duration.zero) {
        return true;
      }
    }
    return false;
  }

  /// Parses Quick Edit text back into entries.
  ///
  /// Returns a record with the parsed entries and the 0-based indices of lines
  /// that failed to parse.
  static ({List<ChapterEntry> entries, List<int> errorLines}) parseQuickEditText(
      String text, bool expectTimestamps) {
    // Empty input → no entries
    if (text.isEmpty) {
      return (entries: [], errorLines: []);
    }
    final lines = text.split('\n');
    final resultEntries = <ChapterEntry>[];
    final errorLines = <int>[];
    int lineIndex = 0;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        // Blank line → placeholder entry (empty title, zero start)
        resultEntries.add(const ChapterEntry(title: '', start: Duration.zero));
        lineIndex++;
        continue;
      }

      if (!expectTimestamps) {
        // Title only — strip optional quotes
        final title = _stripQuotes(line);
        resultEntries.add(ChapterEntry(title: title, start: Duration.zero));
        lineIndex++;
        continue;
      }

      // Find the rightmost comma as separator between title and timestamp.
      final lastComma = line.lastIndexOf(',');
      if (lastComma == -1) {
        errorLines.add(lineIndex);
        resultEntries
            .add(ChapterEntry(title: line, start: Duration.zero));
        lineIndex++;
        continue;
      }

      final rawTitle = line.substring(0, lastComma).trim();
      final rawTimestamp = line.substring(lastComma + 1).trim();

      final title = _stripQuotes(rawTitle);
      final duration = parseTimestamp(rawTimestamp);

      if (duration == null) {
        errorLines.add(lineIndex);
        resultEntries
            .add(ChapterEntry(title: title, start: Duration.zero));
      } else {
        resultEntries.add(ChapterEntry(title: title, start: duration));
      }
      lineIndex++;
    }

    return (entries: resultEntries, errorLines: errorLines);
  }

  static String _stripQuotes(String s) {
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }

  // ---------------------------------------------------------------------------
  // Timestamp helpers
  // ---------------------------------------------------------------------------

  /// Parses a timestamp string into a Duration.
  ///
  /// Accepts:
  ///   MM:SS   — one colon, left part ≤ 99: minutes 0-99, seconds 0-59
  ///   MMM:SS  — one colon, left part > 99: minutes ≥ 100, seconds 0-59
  ///   H:MM:SS or HH:MM:SS — two colons
  ///
  /// Returns null if format doesn't match or values are out of range.
  static Duration? parseTimestamp(String s) {
    s = s.trim();
    final colonCount = ':'.allMatches(s).length;

    if (colonCount == 1) {
      // MM:SS or MMM:SS
      final parts = s.split(':');
      if (parts.length != 2) return null;
      final minutes = int.tryParse(parts[0]);
      final seconds = int.tryParse(parts[1]);
      if (minutes == null || seconds == null) return null;
      if (minutes < 0) return null;
      if (seconds < 0 || seconds > 59) return null;
      return Duration(minutes: minutes, seconds: seconds);
    } else if (colonCount == 2) {
      // H:MM:SS or HH:MM:SS
      final parts = s.split(':');
      if (parts.length != 3) return null;
      final hours = int.tryParse(parts[0]);
      final minutes = int.tryParse(parts[1]);
      final seconds = int.tryParse(parts[2]);
      if (hours == null || minutes == null || seconds == null) return null;
      if (hours < 0) return null;
      if (minutes < 0 || minutes > 59) return null;
      if (seconds < 0 || seconds > 59) return null;
      return Duration(hours: hours, minutes: minutes, seconds: seconds);
    }

    return null;
  }

  /// Formats a Duration as HH:MM:SS (always zero-padded).
  static String formatTimestamp(Duration d) {
    final totalSeconds = d.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------------------
// Flutter widget — ChapterEditor
// ---------------------------------------------------------------------------

/// The interactive chapter editing widget rendered inside the Chapters tab.
///
/// Owns all chapter editing state: in-memory list, undo/redo stack,
/// validation errors, hover state. Calls [onChanged] after every mutation
/// so [BookDetailScreen] can update its dirty state.
class ChapterEditor extends StatefulWidget {
  final Audiobook book;
  final void Function(List<ChapterEntry> chapters) onChanged;

  /// Called by BookDetailScreen after apply, to clearHistory.
  final void Function()? onApplied;

  /// Called whenever the validation state changes.
  ///
  /// [hasErrors] is true when there are timestamp conflicts or incomplete
  /// entries (empty title, or zero start on a non-first row for single-file
  /// books).
  final void Function(bool hasErrors)? onHasErrors;

  const ChapterEditor({
    super.key,
    required this.book,
    required this.onChanged,
    this.onApplied,
    this.onHasErrors,
  });

  @override
  State<ChapterEditor> createState() => _ChapterEditorState();
}

class _ChapterEditorState extends State<ChapterEditor> {
  late ChapterEditorController _ctrl;
  late bool _isSingleFile;
  // ignore: unused_field — will be used in task 7 for CUE export button
  late bool _isMp3;

  List<TextEditingController> _titleCtrls = [];
  List<TextEditingController> _startCtrls = [];
  List<FocusNode> _startFocusNodes = [];
  List<String?> _startErrors = [];
  List<bool> _rowHovered = [];
  List<bool> _dividerHovered = [];

  @override
  void initState() {
    super.initState();
    _initFromBook();
  }

  void _initFromBook() {
    _isSingleFile = widget.book.audioFiles.length == 1;
    _isMp3 = _isSingleFile &&
        widget.book.audioFiles.isNotEmpty &&
        p.extension(widget.book.audioFiles[0]).toLowerCase() == '.mp3';

    List<ChapterEntry> entries;
    if (_isSingleFile) {
      entries = widget.book.chapters
          .map((c) => ChapterEntry(title: c.title, start: c.start))
          .toList();
    } else {
      entries = List.generate(
        widget.book.audioFiles.length,
        (i) => ChapterEntry(
          title: i < widget.book.chapterNames.length
              ? widget.book.chapterNames[i]
              : p.basenameWithoutExtension(widget.book.audioFiles[i]),
          start: Duration.zero,
        ),
      );
    }

    _ctrl = ChapterEditorController(entries: entries);
    _ctrl.clearHistory();
    _rebuildTextControllers();
  }

  void _rebuildTextControllers() {
    // Dispose existing
    for (final c in _titleCtrls) {
      c.dispose();
    }
    for (final c in _startCtrls) {
      c.dispose();
    }
    for (final fn in _startFocusNodes) {
      fn.dispose();
    }

    final n = _ctrl.entries.length;
    _titleCtrls = List.generate(
      n,
      (i) => TextEditingController(text: _ctrl.entries[i].title),
    );
    _startCtrls = List.generate(
      n,
      (i) => TextEditingController(
          text: ChapterEditorController.formatTimestamp(_ctrl.entries[i].start)),
    );
    _startFocusNodes = List.generate(n, (i) {
      final fn = FocusNode();
      fn.addListener(() {
        if (!fn.hasFocus) {
          _onStartBlur(i);
        }
      });
      return fn;
    });
    _startErrors = List.filled(n, null);
    _rowHovered = List.filled(n, false);
    _dividerHovered = n > 1 ? List.filled(n - 1, false) : [];
  }

  void _onStartBlur(int index) {
    final text = _startCtrls[index].text;
    final parsed = ChapterEditorController.parseTimestamp(text);

    if (parsed == null) {
      setState(() {
        _startErrors[index] = 'Invalid format (e.g. 1:05:30)';
        _startCtrls[index].text =
            ChapterEditorController.formatTimestamp(_ctrl.entries[index].start);
      });
      return;
    }

    // Check neighbours for conflicts
    if (index > 0 && parsed <= _ctrl.entries[index - 1].start) {
      setState(() {
        _startErrors[index] = 'Must be after previous chapter';
      });
      return;
    }
    if (index < _ctrl.entries.length - 1 &&
        parsed >= _ctrl.entries[index + 1].start) {
      setState(() {
        _startErrors[index] = 'Must be before next chapter';
      });
      return;
    }

    // Valid — update controller and reformat
    _ctrl.updateStart(index, parsed);
    setState(() {
      _startErrors[index] = null;
      _startCtrls[index].text =
          ChapterEditorController.formatTimestamp(parsed);
    });
    _notify();
  }

  void _notify() {
    widget.onChanged(_ctrl.entries);
    final hasErrors = _ctrl.hasConflicts ||
        _ctrl.hasIncompleteEntries(requireTimestamps: _isSingleFile);
    widget.onHasErrors?.call(hasErrors);
  }

  /// Calls [fn], then rebuilds text controllers, then setState, then notifies.
  void _mutate(void Function() fn) {
    fn();
    _rebuildTextControllers();
    setState(() {});
    _notify();
  }

  @override
  void didUpdateWidget(ChapterEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.book.path != widget.book.path) {
      _disposeAllControllers();
      _initFromBook();
    }
  }

  void _disposeAllControllers() {
    for (final c in _titleCtrls) {
      c.dispose();
    }
    for (final c in _startCtrls) {
      c.dispose();
    }
    for (final fn in _startFocusNodes) {
      fn.dispose();
    }
    _titleCtrls = [];
    _startCtrls = [];
    _startFocusNodes = [];
  }

  @override
  void dispose() {
    _disposeAllControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildToolbar(),
        if (_ctrl.hasConflicts) _buildConflictBanner(),
        if (!_ctrl.hasConflicts &&
            _ctrl.hasIncompleteEntries(requireTimestamps: _isSingleFile))
          _buildIncompleteBanner(),
        _buildColumnHeaders(),
        Expanded(child: _buildChapterList()),
      ],
    );
  }

  Widget _buildToolbar() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.undo),
          tooltip: 'Undo',
          onPressed: _ctrl.canUndo ? () => _mutate(_ctrl.undo) : null,
        ),
        IconButton(
          icon: const Icon(Icons.redo),
          tooltip: 'Redo',
          onPressed: _ctrl.canRedo ? () => _mutate(_ctrl.redo) : null,
        ),
        const Spacer(),
        OutlinedButton.icon(
          icon: const Icon(Icons.edit_note, size: 18),
          label: const Text('Quick Edit'),
          onPressed: _openQuickEdit,
        ),
        // CUE export button — only for MP3 single-file books, wired in task 7
      ],
    );
  }

  Widget _buildConflictBanner() {
    return Container(
      color: Colors.orange[900]!.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.warning_amber, size: 16, color: Colors.orange[700]),
          const SizedBox(width: 8),
          Text(
            'Fix timestamp conflicts before applying',
            style: TextStyle(fontSize: 12, color: Colors.orange[700]),
          ),
        ],
      ),
    );
  }

  Widget _buildIncompleteBanner() {
    return Container(
      color: Colors.orange[900]!.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.warning_amber, size: 16, color: Colors.orange[700]),
          const SizedBox(width: 8),
          Text(
            'Fill in all chapter titles before applying',
            style: TextStyle(fontSize: 12, color: Colors.orange[700]),
          ),
        ],
      ),
    );
  }

  Widget _buildColumnHeaders() {
    const headerStyle = TextStyle(color: Colors.grey, fontSize: 12);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const SizedBox(width: 36, child: Text('#', style: headerStyle)),
          const Expanded(child: Text('Title', style: headerStyle)),
          if (_isSingleFile) ...[
            const SizedBox(width: 8),
            const SizedBox(
                width: 100, child: Text('Start', style: headerStyle)),
            const SizedBox(width: 8),
          ],
          const SizedBox(
              width: 90, child: Text('Duration', style: headerStyle)),
          if (!_isSingleFile) ...[
            const SizedBox(width: 8),
            const SizedBox(
                width: 120, child: Text('File', style: headerStyle)),
          ],
          const SizedBox(width: 32), // delete button placeholder
        ],
      ),
    );
  }

  Widget _buildChapterList() {
    return SingleChildScrollView(
      child: Column(
        children: [
          for (int i = 0; i < _ctrl.entries.length; i++) ...[
            // Each row has a fixed top gap. The insert divider floats inside
            // that gap via a Stack so rows never shift when it appears.
            if (i > 0)
              _buildInsertDivider(i - 1),
            _buildChapterRow(i),
          ],
          const SizedBox(height: 8),
          _buildAddButton(),
        ],
      ),
    );
  }

  Widget _buildInsertDivider(int afterIndex) {
    // Fixed-height gap that always occupies the same space.
    // The (+) row appears inside it on hover — no layout shift.
    return MouseRegion(
      onEnter: (_) => setState(() => _dividerHovered[afterIndex] = true),
      onExit: (_) => setState(() => _dividerHovered[afterIndex] = false),
      child: SizedBox(
        height: 20,
        child: AnimatedOpacity(
          opacity: _dividerHovered[afterIndex] ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 120),
          child: Row(
            children: [
              const Expanded(child: Divider(height: 1)),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 16),
                tooltip: 'Insert chapter here',
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: _dividerHovered[afterIndex]
                    ? () => _mutate(() => _ctrl.insertChapter(afterIndex))
                    : null,
              ),
              const Expanded(child: Divider(height: 1)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChapterRow(int index) {
    return MouseRegion(
      onEnter: (_) => setState(() => _rowHovered[index] = true),
      onExit: (_) => setState(() => _rowHovered[index] = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Index
            SizedBox(
              width: 36,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
            ),
            // Title
            Expanded(
              child: TextField(
                controller: _titleCtrls[index],
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  border: const OutlineInputBorder(),
                  hintText: _ctrl.entries[index].title.isEmpty
                      ? 'Enter chapter title'
                      : null,
                  hintStyle:
                      const TextStyle(color: Colors.grey, fontSize: 12),
                  // Orange border only when the title is empty (placeholder row)
                  enabledBorder: _ctrl.entries[index].title.isEmpty
                      ? OutlineInputBorder(
                          borderSide:
                              BorderSide(color: Colors.orange[300]!))
                      : null,
                ),
                onChanged: (v) {
                  _ctrl.updateTitle(index, v);
                  _notify();
                  // Update conflict banner without rebuilding text controllers
                  setState(() {});
                },
              ),
            ),
            const SizedBox(width: 8),
            // Start time (single-file only, row 0 is read-only)
            if (_isSingleFile) ...[
              SizedBox(
                width: 100,
                child: index == 0
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          ChapterEditorController.formatTimestamp(
                              _ctrl.entries[0].start),
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 13),
                        ),
                      )
                    : TextField(
                        controller: _startCtrls[index],
                        focusNode: _startFocusNodes[index],
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          border: const OutlineInputBorder(),
                          errorText: _startErrors[index],
                          errorStyle: const TextStyle(fontSize: 10),
                          // Orange border only when start is still zero (placeholder)
                          enabledBorder: (_startErrors[index] == null &&
                                  _ctrl.entries[index].start == Duration.zero)
                              ? OutlineInputBorder(
                                  borderSide: BorderSide(
                                      color: Colors.orange[300]!))
                              : null,
                        ),
                        onEditingComplete: () =>
                            _startFocusNodes[index].unfocus(),
                      ),
              ),
              const SizedBox(width: 8),
            ],
            // Duration
            SizedBox(
              width: 90,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _formatDuration(
                      _ctrl.derivedDuration(index, widget.book.duration)),
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
            ),
            // File (multi-file only)
            if (!_isSingleFile) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    index < widget.book.audioFiles.length
                        ? p.basename(widget.book.audioFiles[index])
                        : '',
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            // Delete button (hover-reveal)
            SizedBox(
              width: 32,
              child: _rowHovered[index] || _ctrl.entries.length == 1
                  ? Tooltip(
                      message: _ctrl.entries.length == 1
                          ? 'At least one chapter is required'
                          : 'Delete chapter',
                      child: IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 32, minHeight: 32),
                        color: _ctrl.entries.length == 1
                            ? Colors.grey
                            : Colors.red[400],
                        onPressed: _ctrl.entries.length == 1
                            ? null
                            : () =>
                                _mutate(() => _ctrl.deleteChapter(index)),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    return TextButton.icon(
      icon: const Icon(Icons.add, size: 16),
      label: const Text('Add chapter'),
      onPressed: () => _mutate(() => _ctrl.addChapter(widget.book.duration)),
    );
  }

  void _openQuickEdit() {
    showDialog<void>(
      context: context,
      builder: (ctx) => QuickEditDialog(
        initialText: _ctrl.toQuickEditText(_isSingleFile),
        includeTimestamps: _isSingleFile,
        onSave: (entries) {
          _mutate(() => _ctrl.replaceAll(entries));
        },
      ),
    );
  }

  String _formatDuration(Duration? d) {
    if (d == null) return '—';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}
