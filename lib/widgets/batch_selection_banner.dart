import 'package:flutter/material.dart';

/// Banner shown when 2+ books are selected in batch mode.
/// Displays selection count and provides Clear / Edit all actions.
class BatchSelectionBanner extends StatelessWidget {
  final int selectionCount;
  final VoidCallback onClearSelection;
  final VoidCallback onEditAll;

  const BatchSelectionBanner({
    super.key,
    required this.selectionCount,
    required this.onClearSelection,
    required this.onEditAll,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline,
              size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            '$selectionCount books selected',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: onClearSelection,
            child: const Text('Clear selection'),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: onEditAll,
            child: const Text('Edit all \u2192'),
          ),
        ],
      ),
    );
  }
}
