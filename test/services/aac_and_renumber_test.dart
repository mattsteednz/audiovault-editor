import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:audiovault_editor/models/audiobook.dart';
import 'package:audiovault_editor/services/metadata_writer.dart';
import 'package:audiovault_editor/widgets/chapter_editor.dart';

void main() {
  group('ChapterEditorController.renumberTitles', () {
    test('renumbers titles while preserving start times', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'garbage_01', start: Duration.zero),
        const ChapterEntry(title: 'Part II (final)', start: Duration(minutes: 5)),
        const ChapterEntry(title: '', start: Duration(minutes: 9)),
      ]);

      ctrl.renumberTitles();

      expect(ctrl.entries.map((e) => e.title).toList(),
          ['Chapter 1', 'Chapter 2', 'Chapter 3']);
      expect(
          ctrl.entries.map((e) => e.start).toList(),
          [Duration.zero, const Duration(minutes: 5), const Duration(minutes: 9)]);
    });

    test('is a single undo step', () {
      final ctrl = ChapterEditorController(entries: [
        const ChapterEntry(title: 'A', start: Duration.zero),
      ]);
      ctrl.renumberTitles();
      expect(ctrl.canUndo, isTrue);
      ctrl.undo();
      expect(ctrl.entries.single.title, 'A');
    });
  });

  group('MetadataWriter AAC honesty', () {
    test('applyMetadata reports unsupported instead of silent no-op',
        () async {
      const book = Audiobook(
        path: '/books/x',
        audioFiles: ['/books/x/audio.aac'],
        title: 'T',
      );
      final errors = await MetadataWriter.applyMetadata(book);
      expect(errors, hasLength(1));
      expect(errors.single, contains('.aac'));
      expect(errors.single, contains('not supported'));
    });

    test('applyCover reports unsupported for .aac', () async {
      final dir = await Directory.systemTemp.createTemp('av_aac_test_');
      addTearDown(() => dir.delete(recursive: true));
      final png = File('${dir.path}/c.png');
      // Generate a real 1x1 image so toJpeg can decode it.
      png.writeAsBytesSync(
          img.encodePng(img.Image(width: 2, height: 2)));
      final book = Audiobook(path: dir.path, audioFiles: ['/x/a.aac']);
      final errors = await MetadataWriter.applyCover(book, png.path);
      expect(errors.where((e) => e.contains('.aac')), hasLength(1));
      expect(File('${dir.path}/cover.jpg').existsSync(), isTrue);
    });
  });
}
