import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audiovault_editor/widgets/chapter_editor.dart';

class QuickEditDialog extends StatefulWidget {
  final String initialText;
  final bool includeTimestamps;
  final void Function(List<ChapterEntry> result) onSave;

  const QuickEditDialog({
    super.key,
    required this.initialText,
    required this.includeTimestamps,
    required this.onSave,
  });

  @override
  State<QuickEditDialog> createState() => _QuickEditDialogState();
}

class _QuickEditDialogState extends State<QuickEditDialog> {
  late TextEditingController _textCtrl;
  List<int> _errorLines = [];
  bool _hasConflicts = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(text: widget.initialText);
    _textCtrl.addListener(_onTextChanged);
    _parseNow();
  }

  void _onTextChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _parseNow);
  }

  void _parseNow() {
    final result = ChapterEditorController.parseQuickEditText(
      _textCtrl.text,
      widget.includeTimestamps,
    );
    setState(() {
      _errorLines = result.errorLines;
      _hasConflicts = _checkConflicts(result.entries);
    });
  }

  bool _checkConflicts(List<ChapterEntry> entries) {
    // Placeholder entries (zero start at index > 0) are skipped in conflict
    // detection. Only entries with actual timestamps are checked.
    Duration? lastNonZero;
    for (int i = 0; i < entries.length; i++) {
      final start = entries[i].start;
      if (i == 0) {
        lastNonZero = start; // always Duration.zero
        continue;
      }
      if (start == Duration.zero) continue; // placeholder, skip
      if (lastNonZero != null && start <= lastNonZero) return true;
      lastNonZero = start;
    }
    return false;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSave = _errorLines.isEmpty && !_hasConflicts;

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
              const SizedBox(height: 8),
              // Hint text
              Text(
                widget.includeTimestamps
                    ? 'One chapter per line: Title, HH:MM:SS  (blank lines = placeholder rows)'
                    : 'One chapter per line: Title  (blank lines = placeholder rows)',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 12),
              // Main editing area: gutter + text field
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildGutter(),
                    const SizedBox(width: 8),
                    Expanded(child: _buildTextField(theme)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Bottom action row
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!canSave && (_errorLines.isNotEmpty || _hasConflicts))
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(
                        _hasConflicts && _errorLines.isEmpty
                            ? 'Timestamp conflicts detected'
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

  Widget _buildGutter() {
    final lines = _textCtrl.text.split('\n');
    final lineCount = lines.length;

    return SizedBox(
      width: 32,
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: lineCount,
        itemBuilder: (context, i) {
          final isError = _errorLines.contains(i);
          return SizedBox(
            height: 28, // approximate line height matching TextField
            child: Center(
              child: isError
                  ? Icon(Icons.error_outline, size: 14, color: Colors.red[400])
                  : Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.right,
                    ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTextField(ThemeData theme) {
    return TextField(
      controller: _textCtrl,
      maxLines: null,
      expands: true,
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
      ),
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.all(12),
      ),
      textAlignVertical: TextAlignVertical.top,
    );
  }

  void _save() {
    // Final validation before saving
    final result = ChapterEditorController.parseQuickEditText(
      _textCtrl.text,
      widget.includeTimestamps,
    );
    if (result.errorLines.isNotEmpty || _checkConflicts(result.entries)) {
      setState(() {
        _errorLines = result.errorLines;
        _hasConflicts = _checkConflicts(result.entries);
      });
      return;
    }
    widget.onSave(result.entries);
    Navigator.of(context).pop();
  }
}
