import 'package:flutter/material.dart';

/// A small lock icon that signals a book's folder or files are read-only.
///
/// Use [prominent] to switch between two visual styles:
/// - `false` (default) — 12 px icon, no colour override; suited for the book
///   list sidebar where space is tight.
/// - `true` — 16 px amber icon; suited for the book detail panel header where
///   the indicator needs to draw more attention.
///
/// When [tooltip] is non-null the icon is wrapped in a [Tooltip]; otherwise it
/// is rendered directly without a wrapper.
class ReadOnlyBadge extends StatelessWidget {
  const ReadOnlyBadge({
    super.key,
    this.tooltip,
    this.prominent = false,
  });

  /// Optional tooltip text shown on hover / long-press.
  final String? tooltip;

  /// When `true`, renders a larger amber icon for the detail panel.
  /// When `false` (default), renders a small icon for the list view.
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final icon = prominent
        ? const Icon(Icons.lock_outline, size: 16, color: Colors.amber)
        : const Icon(Icons.lock_outline, size: 12);

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: icon);
    }
    return icon;
  }
}
