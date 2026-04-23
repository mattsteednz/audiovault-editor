import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audiovault_editor/services/silence_detection_service.dart';
import 'package:audiovault_editor/widgets/chapter_editor.dart';

// ---------------------------------------------------------------------------
// Dialog state machine
// ---------------------------------------------------------------------------

enum _DialogState { params, detecting, preview }

// ---------------------------------------------------------------------------
// Auto-retry parameter table
// ---------------------------------------------------------------------------

/// Returns the parameter set for [attempt] (0-based), given the user's
/// original [baseFloor] and [baseDuration].
///
/// Attempt 0 = user values (no change).
/// Attempts 1–4 progressively reduce sensitivity.
({double noiseFloor, double minSilence}) _retryParams(
    int attempt, double baseFloor, double baseDuration) {
  const double maxFloor = -20.0;
  const double maxDuration = 10.0;

  switch (attempt) {
    case 0:
      return (noiseFloor: baseFloor, minSilence: baseDuration);
    case 1:
      return (
        noiseFloor: baseFloor,
        minSilence: (baseDuration * 2).clamp(0.1, maxDuration),
      );
    case 2:
      return (
        noiseFloor: baseFloor,
        minSilence: (baseDuration * 4).clamp(0.1, maxDuration),
      );
    case 3:
      return (
        noiseFloor: (baseFloor + 10).clamp(-90.0, maxFloor),
        minSilence: (baseDuration * 2).clamp(0.1, maxDuration),
      );
    case 4:
      return (
        noiseFloor: (baseFloor + 10).clamp(-90.0, maxFloor),
        minSilence: (baseDuration * 4).clamp(0.1, maxDuration),
      );
    default:
      return (
        noiseFloor: (baseFloor + 10).clamp(-90.0, maxFloor),
        minSilence: (baseDuration * 4).clamp(0.1, maxDuration),
      );
  }
}

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Shows the Detect Chapters dialog and returns the accepted [ChapterEntry]
/// list, or null if the user cancelled.
Future<List<ChapterEntry>?> showDetectChaptersDialog({
  required BuildContext context,
  required String filePath,
  required Duration? totalDuration,
  required int existingChapterCount,
}) {
  return showDialog<List<ChapterEntry>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => DetectChaptersDialog(
      filePath: filePath,
      totalDuration: totalDuration,
      existingChapterCount: existingChapterCount,
    ),
  );
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

class DetectChaptersDialog extends StatefulWidget {
  final String filePath;
  final Duration? totalDuration;
  final int existingChapterCount;

  const DetectChaptersDialog({
    super.key,
    required this.filePath,
    required this.totalDuration,
    required this.existingChapterCount,
  });

  @override
  State<DetectChaptersDialog> createState() => _DetectChaptersDialogState();
}

class _DetectChaptersDialogState extends State<DetectChaptersDialog> {
  // ── Form state ─────────────────────────────────────────────────────────────
  final _floorCtrl = TextEditingController(text: '-45');
  final _durationCtrl = TextEditingController(text: '1.5');
  final _floorFocus = FocusNode();
  final _durationFocus = FocusNode();
  String? _floorError;
  String? _durationError;

  // ── Dialog state ───────────────────────────────────────────────────────────
  _DialogState _state = _DialogState.params;
  String? _retryMessage;
  bool _showExcessWarning = false;

  // ── Detection results ──────────────────────────────────────────────────────
  List<ChapterEntry> _detected = [];
  double _usedFloor = -45;
  double _usedDuration = 1.5;

  // ── Stream subscription ────────────────────────────────────────────────────
  StreamSubscription<SilenceDetectionProgress>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    _floorCtrl.dispose();
    _durationCtrl.dispose();
    _floorFocus.dispose();
    _durationFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Parsing helpers
  // ---------------------------------------------------------------------------

  double? _parseFloor(String s) {
    final v = double.tryParse(s.trim());
    if (v == null) return null;
    if (v < -90 || v > -20) return null;
    return v;
  }

  double? _parseDuration(String s) {
    final v = double.tryParse(s.trim());
    if (v == null) return null;
    if (v < 0.1 || v > 10.0) return null;
    return v;
  }

  bool _validateForm() {
    final floor = _parseFloor(_floorCtrl.text);
    final dur = _parseDuration(_durationCtrl.text);
    setState(() {
      _floorError =
          floor == null ? 'Enter a value between -90 and -20' : null;
      _durationError =
          dur == null ? 'Enter a value between 0.1 and 10.0' : null;
    });
    return floor != null && dur != null;
  }

  // ---------------------------------------------------------------------------
  // Detection logic
  // ---------------------------------------------------------------------------

  void _startDetection({int attempt = 0, double? baseFloor, double? baseDur}) {
    if (!_validateForm()) return;

    final userFloor = _parseFloor(_floorCtrl.text)!;
    final userDur = _parseDuration(_durationCtrl.text)!;
    final bf = baseFloor ?? userFloor;
    final bd = baseDur ?? userDur;

    final params = _retryParams(attempt, bf, bd);

    setState(() {
      _state = _DialogState.detecting;
      _retryMessage = attempt > 0
          ? 'Adjusting parameters and retrying (attempt ${attempt + 1}/5)…'
          : null;
    });

    final service = SilenceDetectionService();
    _sub?.cancel();
    _sub = service
        .detect(
          filePath: widget.filePath,
          noiseFloorDb: params.noiseFloor,
          minSilenceSecs: params.minSilence,
          totalDuration: widget.totalDuration,
        )
        .listen(
          (event) => _onProgress(
              event, attempt, bf, bd, params.noiseFloor, params.minSilence),
          onError: (Object e) {
            if (mounted) {
              setState(() => _state = _DialogState.params);
              _showError(e.toString());
            }
          },
        );
  }

  void _onProgress(
    SilenceDetectionProgress event,
    int attempt,
    double baseFloor,
    double baseDur,
    double usedFloor,
    double usedDur,
  ) {
    if (!mounted) return;

    switch (event) {
      case SilenceDetectionProgressUpdate():
        // Progress percentage not available — spinner handles feedback
        break;

      case SilenceDetectionComplete(:final boundaries):
        // Build chapter entries: Chapter 1 at 00:00:00, then one per boundary
        final entries = <ChapterEntry>[
          const ChapterEntry(title: 'Chapter 1', start: Duration.zero),
          for (int i = 0; i < boundaries.length; i++)
            ChapterEntry(
              title: 'Chapter ${i + 2}',
              start: boundaries[i],
            ),
        ];

        final count = entries.length;

        if (count > 100 && attempt < 4) {
          // Auto-retry
          final nextAttempt = attempt + 1;
          final nextParams = _retryParams(nextAttempt, baseFloor, baseDur);
          setState(() {
            _retryMessage =
                'Found $count chapters — adjusting parameters and retrying '
                '(attempt ${nextAttempt + 1}/5)…';
          });
          _startDetection(
              attempt: nextAttempt, baseFloor: baseFloor, baseDur: baseDur);
          // Update fields to show what's being tried
          _floorCtrl.text = nextParams.noiseFloor.toStringAsFixed(1);
          _durationCtrl.text = nextParams.minSilence.toStringAsFixed(2);
          return;
        }

        // Show preview (possibly with excess warning)
        setState(() {
          _detected = entries;
          _usedFloor = usedFloor;
          _usedDuration = usedDur;
          _showExcessWarning = count > 100;
          _state = _DialogState.preview;
          _retryMessage = null;
        });

      case SilenceDetectionError(:final message):
        setState(() {
          _state = _DialogState.params;
          _retryMessage = null;
        });
        _showError(message);

      case SilenceDetectionCancelled():
        // Handled by _cancel() — subscription cancelled before this fires
        break;
    }
  }

  void _cancel() {
    _sub?.cancel();
    _sub = null;
    if (mounted) Navigator.of(context).pop();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Detection failed: $message'),
        backgroundColor: Colors.red[700],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Apply
  // ---------------------------------------------------------------------------

  void _applyChapters() {
    if (widget.existingChapterCount > 0) {
      _showReplaceConfirmation();
    } else {
      Navigator.of(context).pop(_detected);
    }
  }

  void _showReplaceConfirmation() {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace existing chapters?'),
        content: Text(
          'This will replace the ${widget.existingChapterCount} existing '
          'chapter${widget.existingChapterCount == 1 ? '' : 's'} with '
          '${_detected.length} detected chapters. '
          'This can be undone with Ctrl+Z in the chapter editor.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Replace'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true && mounted) {
        Navigator.of(context).pop(_detected);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 460,
          maxWidth: 520,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: switch (_state) {
            _DialogState.params => _buildParamsView(),
            _DialogState.detecting => _buildDetectingView(),
            _DialogState.preview => _buildPreviewView(),
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Params view
  // ---------------------------------------------------------------------------

  Widget _buildParamsView() {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title
        Row(
          children: [
            Text('Detect Chapters', style: theme.textTheme.titleLarge),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cancel',
              onPressed: _cancel,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Detects chapter boundaries by finding silent gaps in the audio.',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
        ),
        const SizedBox(height: 20),

        // Noise floor
        _buildNumberField(
          label: 'Noise floor (dB)',
          hint: 'e.g. -45',
          controller: _floorCtrl,
          focusNode: _floorFocus,
          errorText: _floorError,
          helperText: 'Range: -90 to -20',
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*')),
          ],
        ),
        const SizedBox(height: 16),

        // Min silence duration
        _buildNumberField(
          label: 'Min silence (s)',
          hint: 'e.g. 1.5',
          controller: _durationCtrl,
          focusNode: _durationFocus,
          errorText: _durationError,
          helperText: 'Range: 0.1 to 10.0',
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
          ],
        ),
        const SizedBox(height: 24),

        // Actions
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _cancel,
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              icon: const Icon(Icons.search, size: 16),
              label: const Text('Detect'),
              onPressed: _startDetection,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNumberField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required FocusNode focusNode,
    String? errorText,
    String? helperText,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: const TextInputType.numberWithOptions(
              signed: true, decimal: true),
          inputFormatters: inputFormatters,
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            errorText: errorText,
            helperText: helperText,
            border: const OutlineInputBorder(),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Detecting view
  // ---------------------------------------------------------------------------

  Widget _buildDetectingView() {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Detecting chapters…', style: theme.textTheme.titleLarge),
        const SizedBox(height: 20),

        const LinearProgressIndicator(),
        const SizedBox(height: 8),
        Text(
          'Scanning audio…',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
        ),

        // Retry message
        if (_retryMessage != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: Colors.orange[600]),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _retryMessage!,
                  style: TextStyle(fontSize: 12, color: Colors.orange[700]),
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _cancel,
            child: const Text('Cancel'),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Preview view
  // ---------------------------------------------------------------------------

  Widget _buildPreviewView() {
    final theme = Theme.of(context);
    final count = _detected.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title
        Row(
          children: [
            Text('Detect Chapters', style: theme.textTheme.titleLarge),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cancel',
              onPressed: _cancel,
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Excess warning
        if (_showExcessWarning) ...[
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange[900]!.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber, size: 16, color: Colors.orange[700]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '⚠ Could not reduce below 100 chapters automatically. '
                    'Showing best result ($count chapters). '
                    'You may want to adjust the parameters manually.',
                    style:
                        TextStyle(fontSize: 12, color: Colors.orange[700]),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Result summary
        Row(
          children: [
            Icon(Icons.check_circle_outline,
                size: 16, color: Colors.green[600]),
            const SizedBox(width: 6),
            Text(
              'Found $count chapter${count == 1 ? '' : 's'}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Chapter list
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _detected.length,
              itemBuilder: (ctx, i) {
                final entry = _detected[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 5),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 28,
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12),
                        ),
                      ),
                      Expanded(
                        child: Text(entry.title,
                            style: const TextStyle(fontSize: 13)),
                      ),
                      Text(
                        ChapterEditorController.formatTimestamp(entry.start),
                        style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                            fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Parameters used
        Text(
          'Noise floor: ${_usedFloor.toStringAsFixed(1)} dB   '
          '·   Min silence: ${_usedDuration.toStringAsFixed(2)} s',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
        ),
        const SizedBox(height: 20),

        // Actions
        Row(
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Re-detect'),
              onPressed: () {
                setState(() {
                  _state = _DialogState.params;
                  _floorCtrl.text = _usedFloor.toStringAsFixed(1);
                  _durationCtrl.text = _usedDuration.toStringAsFixed(2);
                  _showExcessWarning = false;
                });
              },
            ),
            const Spacer(),
            TextButton(
              onPressed: _cancel,
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _applyChapters,
              child: const Text('Apply chapters'),
            ),
          ],
        ),
      ],
    );
  }
}
