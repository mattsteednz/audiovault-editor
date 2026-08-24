import 'package:flutter/material.dart';

/// Dialog for entering a new folder name.
///
/// Returns the trimmed new name, or null when cancelled/unchanged.
/// Collision checks and the actual filesystem rename stay with the caller.
Future<String?> showRenameFolderDialog(
  BuildContext context, {
  required String currentName,
  required String proposedName,
}) async {
  final controller = TextEditingController(text: proposedName);

  final confirmed = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Rename folder'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Current name:', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 4),
          Text(currentName, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          const Text('New name:', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Enter new folder name',
            ),
            autofocus: true,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: const Text('Rename'),
        ),
      ],
    ),
  );

  controller.dispose();
  return confirmed;
}
