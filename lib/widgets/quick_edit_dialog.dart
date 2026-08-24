import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:audiovault_editor/widgets/chapter_editor.dart';

/// The three editing modes available in [QuickEditDialog].
enum QuickEditMode {
  /// One chapter title per line. Timestamps are preserved unchanged on save.
  namesOnly,

  /// One "Title, HH:MM:SS" per line. Both fields are editable and validated.
  both,

  /// One HH:MM:SS per line. Titles are preserved unchanged on save.
  timesOnly,
}

class QuickEditDialog extends StatefulWidget {
  /// The chapter list at the time the dialog was opened.
  final List<ChapterEntry> initialEntries;

  /// True for single-file books (timestamps are meaningful).
  final bool isSingleFile;

  /// Total duration of the book, used to validate that start times don't
  /// exceed the end of the file. Null when unknown.
  final Duration? bookDuration;

  final void Function(List<ChapterEntry> result) onSave;

  const QuickEditDialog({
    super.key,
    required this.initialEntries,
    required this.isSingleFile,
    this.bookDuration,
    required this.onSave,
  });

  @override
  State<QuickEditDialog> createState() => _QuickEditDialogState();
}

class _QuickEditDialogState extends State<QuickEditDialog> {
  late TextEditingController _textCtrl;
  late QuickEditMode _mode;

  /// The last successfully parsed entries — used as the merge base when
  /// switching modes and when saving in namesOnly / timesOnly modes.
  late List<ChapterEntry> _lastParsed;

  List<int> _errorLines = [];
  bool _hasConflicts = false;
  List<int> _beyondEndLines = [];
  Timer? _debounce;

  /// Y offsets (in the gutter's local coordinate space) for each line,
  /// measured from the live RenderEditable after each frame.
  List<double> _lineYOffsets = [];
  final _textFieldKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _mode = widget.isSingleFile ? QuickEditMode.both : QuickEditMode.namesOnly;
    _lastParsed = List.of(widget.initialEntries);
    _textCtrl = TextEditingController(text: _serialise(_mode, _lastParsed));
    _textCtrl.addListener(_onTextChanged);
    _parseNow();
    // Measure line positions after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureLineOffsets());
  }

  /// Walks the render tree under [_textFieldKey] to find the [RenderEditable],
  /// then samples the Y centre of each line by querying selection boxes.
  void _measureLineOffsets() {
    if (!mounted) return;
    final renderBox =
        _textFieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    // Find the RenderEditable nested inside the TextField's render subtree.
    RenderEditable? editable;
    void visitor(RenderObject obj) {
      if (obj is RenderEditable) {
        editable = obj;
        return;
      }
      obj.visitChildren(visitor);
    }
    renderBox.visitChildren(visitor);
    if (editable == null) return;

    final text = _textCtrl.text;
    final lines = text.isEmpty ? [''] : text.split('\n');
    final offsets = <double>[];

    // For each line, find the Y centre of the first character (or the caret
    // position for empty lines) in the editable's local coordinates, then
    // convert to the gutter's coordinate space (same origin as the TextField
    // render box, offset by the border width).
    int charOffset = 0;
    for (int i = 0; i < lines.length; i++) {
      // Use the start of the line (or end-of-text for the last empty line).
      final pos = TextPosition(offset: charOffset);
      final caretOffset = editable!.getLocalRectForCaret(pos);
      // Convert from editable-local to renderBox-local coordinates.
      final editableOffset =
          editable!.localToGlobal(Offset.zero, ancestor: renderBox);
      final y = editableOffset.dy + caretOffset.top;
      offsets.add(y);
      // Advance past this line's characters + the newline.
      charOffset += lines[i].length + 1;
    }

    if (mounted) {
      setState(() => _lineYOffsets = offsets);
    }
  }

  // ---------------------------------------------------------------------------
  // Serialisation helpers
  // ---------------------------------------------------------------------------

  String _serialise(QuickEditMode mode, List<ChapterEntry> entries) {
    final ctrl = ChapterEditorController(entries: entries);
    switch (mode) {
      case QuickEditMode.namesOnly:
        return ctrl.toQuickEditText(false);
      case QuickEditMode.both:
        return ctrl.toQuickEditText(true);
      case QuickEditMode.timesOnly:
        return ctrl.toTimesOnlyText();
    }
  }

  ({List<ChapterEntry> entries, List<int> errorLines}) _parse(
      QuickEditMode mode, String text) {
    switch (mode) {
      case QuickEditMode.namesOnly:
        return ChapterEditorController.parseQuickEditText(text, false);
      case QuickEditMode.both:
        return ChapterEditorController.parseQuickEditText(text, true);
      case QuickEditMode.timesOnly:
        return ChapterEditorController.parseTimesOnlyText(
            text, widget.initialEntries);
    }
  }

  // ---------------------------------------------------------------------------
  // Text change / parse
  // ---------------------------------------------------------------------------

  void _onTextChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _parseNow();
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureLineOffsets());
    });
  }

  void _parseNow() {
    final result = _parse(_mode, _textCtrl.text);
    final conflicts =
        _mode != QuickEditMode.namesOnly && _checkConflicts(result.entries);
    final beyondEnd = _mode != QuickEditMode.namesOnly
        ? _checkBeyondEnd(result.entries)
        : <int>[];
    setState(() {
      _errorLines = result.errorLines;
      _hasConflicts = conflicts;
      _beyondEndLines = beyondEnd;
      if (result.errorLines.isEmpty) {
        _lastParsed = result.entries;
      }
    });
  }

  /// Returns 0-based line indices where the start time is at or beyond
  /// [bookDuration]. Skips placeholder entries (zero start at index > 0).
  List<int> _checkBeyondEnd(List<ChapterEntry> entries) {
    final duration = widget.bookDuration;
    if (duration == null) return [];
    final bad = <int>[];
    for (int i = 0; i < entries.length; i++) {
      final start = entries[i].start;
      if (i > 0 && start == Duration.zero) continue; // placeholder
      if (start >= duration) bad.add(i);
    }
    return bad;
  }

  bool _checkConflicts(List<ChapterEntry> entries) {
    Duration? lastNonZero;
    for (int i = 0; i < entries.length; i++) {
      final start = entries[i].start;
      if (i == 0) {
        lastNonZero = start;
        continue;
      }
      if (start == Duration.zero) continue;
      if (lastNonZero != null && start <= lastNonZero) return true;
      lastNonZero = start;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Mode switching
  // ---------------------------------------------------------------------------

  void _switchMode(QuickEditMode newMode) {
    if (newMode == _mode) return;

    // Parse current text with the old mode to capture any unsaved edits.
    final current = _parse(_mode, _textCtrl.text);
    final mergedEntries = _mergeForSwitch(current.entries, newMode);

    setState(() {
      _mode = newMode;
      _lastParsed = mergedEntries;
      _errorLines = [];
      _hasConflicts = false;
      _beyondEndLines = [];
    });

    _textCtrl.removeListener(_onTextChanged);
    _textCtrl.text = _serialise(newMode, mergedEntries);
    _textCtrl.addListener(_onTextChanged);
    _parseNow();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureLineOffsets());
  }

  /// Builds the entry list to display after switching to [newMode].
  ///
  /// - Titles come from [current] when switching away from timesOnly,
  ///   otherwise from [widget.initialEntries].
  /// - Timestamps come from [current] when switching away from namesOnly,
  ///   otherwise from [widget.initialEntries].
  List<ChapterEntry> _mergeForSwitch(
      List<ChapterEntry> current, QuickEditMode newMode) {
    final base = widget.initialEntries;
    final len = base.length;

    return List.generate(len, (i) {
      final baseEntry = base[i];
      final curEntry = i < current.length ? current[i] : baseEntry;

      final title = (_mode == QuickEditMode.timesOnly)
          ? baseEntry.title // titles weren't editable, use originals
          : curEntry.title;

      final start = (_mode == QuickEditMode.namesOnly)
          ? baseEntry.start // timestamps weren't editable, use originals
          : curEntry.start;

      return ChapterEntry(title: title, start: start);
    });
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _debounce?.cancel();
    _textCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Save
  // ---------------------------------------------------------------------------

  void _save() {
    final result = _parse(_mode, _textCtrl.text);
    final conflicts =
        _mode != QuickEditMode.namesOnly && _checkConflicts(result.entries);
    final beyondEnd = _mode != QuickEditMode.namesOnly
        ? _checkBeyondEnd(result.entries)
        : <int>[];

    if (result.errorLines.isNotEmpty || conflicts || beyondEnd.isNotEmpty) {
      setState(() {
        _errorLines = result.errorLines;
        _hasConflicts = conflicts;
        _beyondEndLines = beyondEnd;
      });
      return;
    }

    final base = widget.initialEntries;
    final parsed = result.entries;

    List<ChapterEntry> finalEntries;
    switch (_mode) {
      case QuickEditMode.namesOnly:
        // Merge new titles onto original timestamps.
        finalEntries = List.generate(
          parsed.length,
          (i) => ChapterEntry(
            title: parsed[i].title,
            start: i < base.length ? base[i].start : Duration.zero,
          ),
        );
      case QuickEditMode.timesOnly:
        // Merge new timestamps onto original titles.
        finalEntries = List.generate(
          parsed.length,
          (i) => ChapterEntry(
            title: i < base.length ? base[i].title : '',
            start: parsed[i].start,
          ),
        );
      case QuickEditMode.both:
        finalEntries = parsed;
    }

    widget.onSave(finalEntries);
    Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  // Font metrics used only for the gutter number text size.
  static const _editorFontSize = 13.0;
  static const _editorFontFamily = 'monospace';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSave = _errorLines.isEmpty && !_hasConflicts && _beyondEndLines.isEmpty;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 500,
          maxWidth: 700,
          minHeight: 400,
          maxHeight: 600,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row
              Row(
                children: [
                  Text('Quick Edit', style: theme.textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Cancel',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Mode toggle — only shown for single-file books where timestamps
              // are meaningful.
              if (widget.isSingleFile) ...[
                _buildModeToggle(theme),
                const SizedBox(height: 10),
              ],
              // Hint text
              Text(
                _hintText,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 12),
              // Main editing area: gutter + text field
              Expanded(
                child: _buildEditorArea(theme),
              ),
              const SizedBox(height: 16),
              // Bottom action row
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!canSave && (_errorLines.isNotEmpty || _hasConflicts || _beyondEndLines.isNotEmpty))
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(
                        _hasConflicts && _errorLines.isEmpty && _beyondEndLines.isEmpty
                            ? 'Timestamp conflicts detected'
                            : _beyondEndLines.isNotEmpty && _errorLines.isEmpty && !_hasConflicts
                                ? 'Start time exceeds book duration'
                                : '${_errorLines.length} error${_errorLines.length == 1 ? '' : 's'}',
                        style: TextStyle(color: Colors.red[400], fontSize: 12),
                      ),
                    ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: canSave ? _save : null,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the gutter + text field as a [Stack] so the gutter is painted
  /// using the same font metrics as the TextField — guaranteeing alignment.
  Widget _buildEditorArea(ThemeData theme) {
    // Gutter width: enough for 3 digits + icon + a little breathing room.
    const gutterWidth = 36.0;

    return Stack(
      children: [
        // The actual TextField, indented to leave room for the gutter.
        Positioned.fill(
          child: TextField(
            key: _textFieldKey,
            controller: _textCtrl,
            maxLines: null,
            expands: true,
            style: const TextStyle(
              fontFamily: _editorFontFamily,
              fontSize: _editorFontSize,
            ),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              // Push text right so it doesn't overlap the gutter.
              // gutterWidth(36) + contentPadding(12) = 48
              contentPadding: EdgeInsets.only(
                left: 48,
                right: 12,
                top: 12,
                bottom: 12,
              ),
            ),
            textAlignVertical: TextAlignVertical.top,
          ),
        ),
        // Gutter painted on top of the left edge of the TextField.
        Positioned(
          left: 1, // sit just inside the border
          top: 1,
          bottom: 1,
          width: gutterWidth,
          child: ClipRect(
            child: CustomPaint(
              painter: _GutterPainter(
                lineYOffsets: _lineYOffsets,
                errorLines: _errorLines,
                beyondEndLines: _beyondEndLines,
                gutterWidth: gutterWidth,
                errorColor: Colors.red[400]!,
                warningColor: Colors.orange[600]!,
                numberColor: Colors.grey[600]!,
                backgroundColor: theme.colorScheme.surface,
              ),
            ),
          ),
        ),
      ],
    );
  }

  String get _hintText {
    switch (_mode) {
      case QuickEditMode.namesOnly:
        return 'One chapter title per line  (blank lines = placeholder rows)';
      case QuickEditMode.both:
        return 'One chapter per line: Title, HH:MM:SS  (blank lines = placeholder rows)';
      case QuickEditMode.timesOnly:
        return 'One start time per line: HH:MM:SS  (blank lines = placeholder rows)';
    }
  }

  Widget _buildModeToggle(ThemeData theme) {
    return SegmentedButton<QuickEditMode>(
      segments: const [
        ButtonSegment(
          value: QuickEditMode.namesOnly,
          label: Text('Names'),
          icon: Icon(Icons.title, size: 16),
        ),
        ButtonSegment(
          value: QuickEditMode.both,
          label: Text('Names + Times'),
          icon: Icon(Icons.list_alt, size: 16),
        ),
        ButtonSegment(
          value: QuickEditMode.timesOnly,
          label: Text('Times'),
          icon: Icon(Icons.schedule, size: 16),
        ),
      ],
      selected: {_mode},
      onSelectionChanged: (selection) => _switchMode(selection.first),
      style: const ButtonStyle(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

}

// ---------------------------------------------------------------------------
// Gutter painter
// ---------------------------------------------------------------------------

/// Paints line numbers (or error icons) at the Y positions measured directly
/// from the live [RenderEditable], so they always align with the TextField.
class _GutterPainter extends CustomPainter {
  final List<double> lineYOffsets;
  final List<int> errorLines;
  final List<int> beyondEndLines;
  final double gutterWidth;
  final Color errorColor;
  final Color warningColor;
  final Color numberColor;
  final Color backgroundColor;

  _GutterPainter({
    required this.lineYOffsets,
    required this.errorLines,
    required this.beyondEndLines,
    required this.gutterWidth,
    required this.errorColor,
    required this.warningColor,
    required this.numberColor,
    required this.backgroundColor,
  });

  // Estimated line height used only to vertically centre icons/numbers within
  // a line when we don't yet have measured offsets.
  static const _fallbackLineHeight = 20.0;

  @override
  void paint(Canvas canvas, Size size) {
    // Fill background so the gutter covers the TextField text beneath it.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = backgroundColor,
    );

    if (lineYOffsets.isEmpty) return;

    // Estimate line height from the gap between consecutive offsets, falling
    // back to a constant if there's only one line.
    final lineHeight = lineYOffsets.length > 1
        ? (lineYOffsets[1] - lineYOffsets[0])
        : _fallbackLineHeight;

    const numberStyle = TextStyle(
      fontSize: 11,
      fontFamily: 'monospace',
    );

    for (int i = 0; i < lineYOffsets.length; i++) {
      final y = lineYOffsets[i];
      final isError = errorLines.contains(i);
      final isBeyondEnd = beyondEndLines.contains(i);

      if (isError || isBeyondEnd) {
        final icon = isError ? Icons.error_outline : Icons.warning_amber;
        final color = isError ? errorColor : warningColor;
        final iconPainter = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(icon.codePoint),
            style: TextStyle(
              fontSize: 14,
              color: color,
              fontFamily: icon.fontFamily,
              package: icon.fontPackage,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        iconPainter.paint(
          canvas,
          Offset(
            (gutterWidth - iconPainter.width) / 2,
            y + (lineHeight - iconPainter.height) / 2,
          ),
        );
      } else {
        final tp = TextPainter(
          text: TextSpan(
            text: '${i + 1}',
            style: numberStyle.copyWith(color: numberColor),
          ),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.right,
        )..layout(maxWidth: gutterWidth - 4);
        tp.paint(
          canvas,
          Offset(
            gutterWidth - tp.width - 4,
            y + (lineHeight - tp.height) / 2,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_GutterPainter old) =>
      old.lineYOffsets != lineYOffsets ||
      old.errorLines != errorLines ||
      old.beyondEndLines != beyondEndLines ||
      old.numberColor != numberColor ||
      old.errorColor != errorColor ||
      old.warningColor != warningColor ||
      old.backgroundColor != backgroundColor;
}
