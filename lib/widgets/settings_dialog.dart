import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:audiovault_editor/services/app_logger.dart';
import 'package:audiovault_editor/services/preferences_service.dart';
import 'package:audiovault_editor/services/silence_detection_service.dart';
import 'package:audiovault_editor/services/writers/atomic_file_writer.dart';

/// Application settings dialog.
///
/// Changes are applied immediately (services read live statics) and
/// persisted via [PreferencesService].
Future<void> showSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _SettingsDialog(),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog();

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final TextEditingController _ffmpegCtrl;
  bool? _advanceAfterApply;
  bool? _keepBackups;
  String? _ffmpegError;

  @override
  void initState() {
    super.initState();
    _ffmpegCtrl =
        TextEditingController(text: SilenceDetectionService.customPath ?? '');
    _load();
  }

  Future<void> _load() async {
    final advance = await PreferencesService.loadAdvanceAfterApply();
    final backups = await PreferencesService.loadKeepBackups();
    if (!mounted) return;
    setState(() {
      _advanceAfterApply = advance;
      _keepBackups = backups;
      AtomicWriteConfig.keepBackups = backups;
    });
  }

  @override
  void dispose() {
    _ffmpegCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ffmpeg location',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ffmpegCtrl,
                    decoration: InputDecoration(
                      isDense: true,
                      border: const OutlineInputBorder(),
                      hintText: 'Leave empty to auto-detect',
                      errorText: _ffmpegError,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _browseFfmpeg,
                  child: const Text('Browse…'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Advance to next book after Apply'),
              subtitle: const Text(
                  'Apply-and-next: jump to the following book in the current '
                  'view after a successful Apply.'),
              value: _advanceAfterApply ?? true,
              onChanged: (v) {
                setState(() => _advanceAfterApply = v);
                PreferencesService.saveAdvanceAfterApply(v);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Keep .bak backups when writing'),
              subtitle: const Text(
                  'Before overwriting an audio file for the first time, save '
                  'the original as <name>.bak in the same folder. Uses extra '
                  'disk space.'),
              value: _keepBackups ?? false,
              onChanged: (v) {
                setState(() => _keepBackups = v);
                AtomicWriteConfig.keepBackups = v;
                PreferencesService.saveKeepBackups(v);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => AppLog.revealLogsFolder(),
          child: const Text('Open log folder'),
        ),
        TextButton(
          onPressed: () {
            SilenceDetectionService.setCustomPath(null);
            PreferencesService.saveFfmpegOverride(null);
            _ffmpegCtrl.clear();
          },
          child: const Text('Reset ffmpeg path'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Future<void> _browseFfmpeg() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Select ffmpeg.exe',
    );
    final path = result?.files.singleOrNull?.path;
    if (path == null) return;
    if (!File(path).existsSync()) {
      setState(() => _ffmpegError = 'File does not exist');
      return;
    }
    setState(() {
      _ffmpegError = null;
      _ffmpegCtrl.text = path;
    });
    SilenceDetectionService.setCustomPath(path);
    await PreferencesService.saveFfmpegOverride(path);
  }
}
