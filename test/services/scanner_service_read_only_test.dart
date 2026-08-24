import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:audiovault_editor/models/audiobook.dart';
import 'package:audiovault_editor/services/scanner_service.dart';

// ---------------------------------------------------------------------------
// Platform helpers
// ---------------------------------------------------------------------------

/// Makes [path] read-only using the platform-appropriate command.
/// Returns true if the operation succeeded, false if it should be skipped.
Future<bool> _makeReadOnly(String path) async {
  if (Platform.isWindows) {
    final r = await Process.run('attrib', ['+R', path]);
    return r.exitCode == 0;
  } else {
    final r = await Process.run('chmod', ['444', path]);
    return r.exitCode == 0;
  }
}

/// Makes [path] (a directory) non-writable.
/// Returns true if the operation succeeded, false if it should be skipped.
Future<bool> _makeDirReadOnly(String path) async {
  if (Platform.isWindows) {
    // On Windows, deny write access to the directory via icacls.
    final user = Platform.environment['USERNAME'] ?? Platform.environment['USER'] ?? '';
    if (user.isEmpty) return false;
    final r = await Process.run(
        'icacls', [path, '/deny', '$user:(W,AD,WD,WA)']);
    return r.exitCode == 0;
  } else {
    final r = await Process.run('chmod', ['555', path]);
    return r.exitCode == 0;
  }
}

/// Restores write permissions on [path] so cleanup can proceed.
Future<void> _restorePermissions(String path) async {
  if (Platform.isWindows) {
    final user = Platform.environment['USERNAME'] ?? Platform.environment['USER'] ?? '';
    if (user.isNotEmpty) {
      await Process.run('icacls', [path, '/remove:d', user]);
    }
    await Process.run('attrib', ['-R', path, '/S']);
  } else {
    await Process.run('chmod', ['-R', '755', path]);
  }
}

void main() {
  late Directory tempDir;
  late ScannerService scanner;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('scanner_ro_test_');
    scanner = ScannerService();
  });

  tearDown(() async {
    await _restorePermissions(tempDir.path);
    await tempDir.delete(recursive: true);
  });

  // Helper: create a real audio-like file in [dir].
  Future<File> createAudioFile(Directory dir, String name) async {
    final f = File('${dir.path}/$name');
    await f.writeAsBytes([0x00, 0x01, 0x02]);
    return f;
  }

  group('_checkReadOnlyStatus (via checkReadOnlyStatusForTesting)', () {
    test('returns writable when folder and all files are writable', () async {
      final file = await createAudioFile(tempDir, 'track.mp3');

      final status = await scanner.checkReadOnlyStatusForTesting(
          tempDir, [file.path]);

      expect(status, ReadOnlyStatus.writable);
    });

    test('returns folderReadOnly when folder is not writable', () async {
      final file = await createAudioFile(tempDir, 'track.mp3');

      final ok = await _makeDirReadOnly(tempDir.path);
      if (!ok) {
        // Permission manipulation not available in this environment — skip.
        return;
      }

      final status = await scanner.checkReadOnlyStatusForTesting(
          tempDir, [file.path]);

      expect(status, ReadOnlyStatus.folderReadOnly);
    });

    test('returns filesReadOnly when folder is writable but a file is not',
        () async {
      final file = await createAudioFile(tempDir, 'track.mp3');

      final ok = await _makeReadOnly(file.path);
      if (!ok) return;

      final status = await scanner.checkReadOnlyStatusForTesting(
          tempDir, [file.path]);

      expect(status, ReadOnlyStatus.filesReadOnly);
    });

    test(
        'returns filesReadOnly when at least one of multiple files is read-only',
        () async {
      final writable = await createAudioFile(tempDir, 'track1.mp3');
      final readOnly = await createAudioFile(tempDir, 'track2.mp3');

      final ok = await _makeReadOnly(readOnly.path);
      if (!ok) return;

      final status = await scanner.checkReadOnlyStatusForTesting(
          tempDir, [writable.path, readOnly.path]);

      expect(status, ReadOnlyStatus.filesReadOnly);
    });

    test('returns writable when audio file list is empty', () async {
      final status = await scanner.checkReadOnlyStatusForTesting(tempDir, []);
      expect(status, ReadOnlyStatus.writable);
    });
  });
}
