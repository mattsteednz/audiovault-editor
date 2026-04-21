import 'package:flutter/material.dart';
import 'package:audiovault_editor/controllers/library_controller.dart';

/// A button that displays the current sort order and opens a dropdown to change it.
/// Shows label format: "Sort: Title A-Z ▼"
class SortButton extends StatelessWidget {
  final SortOrder currentOrder;
  final ValueChanged<SortOrder> onOrderChanged;

  const SortButton({
    super.key,
    required this.currentOrder,
    required this.onOrderChanged,
  });

  static const _labels = {
    SortOrder.titleAsc: 'Title A-Z',
    SortOrder.titleDesc: 'Title Z-A',
    SortOrder.authorAsc: 'Author A-Z',
    SortOrder.authorDesc: 'Author Z-A',
    SortOrder.seriesAsc: 'Series A-Z',
    SortOrder.narratorAsc: 'Narrator A-Z',
    SortOrder.durationAsc: 'Duration \u2191',
    SortOrder.durationDesc: 'Duration \u2193',
  };

  @override
  Widget build(BuildContext context) {
    final label = _labels[currentOrder] ?? 'Title A-Z';
    return PopupMenuButton<SortOrder>(
      tooltip: 'Sort order',
      onSelected: onOrderChanged,
      itemBuilder: (_) => [
        for (final entry in _labels.entries)
          PopupMenuItem(
            value: entry.key,
            child: Row(
              children: [
                if (entry.key == currentOrder)
                  const Icon(Icons.check, size: 16)
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 8),
                Text(entry.value),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Sort: $label',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 16),
          ],
        ),
      ),
    );
  }
}
