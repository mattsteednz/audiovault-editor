import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:audiovault_editor/services/writers/atomic_file_writer.dart';

void main() {
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('av_atomic_test_');
  });

  tearDown(() async {
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
    }
  });

  group('writeFileAtomic', () {
    test('creates a new file with the given bytes', () async {
      final target = p.join(tmpDir.path, 'book.mp3');
      await writeFileAtomic(target, Uint8List.fromList([1, 2, 3]));
      expect(await File(target).readAsBytes(), [1, 2, 3]);
    });

    test('replaces an existing file entirely', () async {
      final target = p.join(tmpDir.path, 'book.mp3');
      await File(target).writeAsBytes(Uint8List.fromList(List.filled(500, 9)));
      await writeFileAtomic(target, Uint8List.fromList([7]));
      expect(await File(target).readAsBytes(), [7]);
    });

    test('leaves no temp files behind on success', () async {
      final target = p.join(tmpDir.path, 'book.mp3');
      for (int i = 0; i < 5; i++) {
        await writeFileAtomic(
            target, Uint8List.fromList([i, i, i, i, i]));
      }
      final entries = await tmpDir.list().toList();
      expect(entries, hasLength(1), reason: 'only the target file should exist');
      expect(p.basename(entries.first.path), 'book.mp3');
    });

    test('original file survives a failed write', () async {
      // Write to a directory that does not exist -> writeAsBytes throws.
      final target = p.join(tmpDir.path, 'nope', 'missing', 'x.mp3');
      await expectLater(
        writeFileAtomic(target, Uint8List.fromList([1])),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('writeStringAtomic', () {
    test('writes UTF-8 string content', () async {
      final target = p.join(tmpDir.path, 'metadata.opf');
      const content = '<?xml version="1.0"?><title>Café ☕</title>';
      await writeStringAtomic(target, content);
      expect(await File(target).readAsString(), content);
    });
  });
}
