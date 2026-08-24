import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:audiovault_editor/models/audiobook.dart';
import 'package:audiovault_editor/services/writers/atomic_file_writer.dart';
import 'package:audiovault_editor/services/writers/id3_writer.dart';

/// Deterministic pseudo-random byte generator (no dart:random flakiness).
Uint8List _noise(int length, {int seed = 7}) {
  final out = Uint8List(length);
  var state = seed;
  for (int i = 0; i < length; i++) {
    state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
    out[i] = state >> 16 & 0xFF;
  }
  return out;
}

/// Builds a synthetic MP3 with ID3v2.3 tag + [audioTail] bytes.
Uint8List _buildMp3(Uint8List audioTail,
    {String title = 'Old', int major = 3}) {
  Uint8List frame(String id, List<int> payload) {
    final f = Uint8List(10 + payload.length);
    for (int i = 0; i < 4; i++) {
      f[i] = id.codeUnitAt(i);
    }
    if (major >= 4) {
      Mp3Writer.syncsafeEncode(payload.length, f, 4);
    } else {
      f[4] = (payload.length >> 24) & 0xFF;
      f[5] = (payload.length >> 16) & 0xFF;
      f[6] = (payload.length >> 8) & 0xFF;
      f[7] = payload.length & 0xFF;
    }
    f.setRange(10, f.length, payload);
    return f;
  }

  final frames = [
    frame('TIT2', [0x03, ...utf8Bytes(title)]),
  ];
  final framesLen = frames.fold<int>(0, (s, f) => s + f.length);
  final header = BytesBuilder();
  header.add([0x49, 0x44, 0x33, major, 0x00, 0x00]);
  final sizeBuf = Uint8List(4);
  Mp3Writer.syncsafeEncode(framesLen, sizeBuf, 0);
  header.add(sizeBuf);

  final out = BytesBuilder();
  out.add(header.toBytes());
  for (final f in frames) {
    out.add(f);
  }
  out.add(audioTail);
  return out.toBytes();
}

List<int> utf8Bytes(String s) => s.codeUnits; // ASCII titles only here

void main() {
  late Directory tmpDir;
  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('av_stream_test_');
  });
  tearDown(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  group('writeFileAtomicSplice', () {
    test('mid-file splice matches execute() exactly (multi-chunk tail)',
        () async {
      // 2.5 MiB source -> head/tail copies cross the 1 MiB chunk boundary.
      final original = _noise(2621440);
      final replacement = _noise(1000, seed: 99);
      final target = p.join(tmpDir.path, 'big.bin');
      await File(target).writeAsBytes(original);

      const start = 500000;
      const end = 1500000;
      await writeFileAtomicSplice(
          target,
          SplicePlan(
            replaceStart: start,
            replaceEnd: end,
            replacement: replacement,
          ));

      final result = await File(target).readAsBytes();
      final expected =
          SplicePlan(replaceStart: start, replaceEnd: end, replacement: replacement)
              .execute(original);
      expect(result, expected);
      expect(result.length,
          original.length - (end - start) + replacement.length);
    });

    test('appendix lands after the streamed tail', () async {
      final original = _noise(300000);
      final target = p.join(tmpDir.path, 'app.bin');
      await File(target).writeAsBytes(original);
      final appendix = _noise(777, seed: 5);

      await writeFileAtomicSplice(
        target,
        SplicePlan(
          replaceStart: 10,
          replaceEnd: 20,
          replacement: _noise(50, seed: 6),
          appendix: appendix,
        ),
      );

      final result = await File(target).readAsBytes();
      expect(result.sublist(result.length - 777), appendix);
      expect(
          result.length,
          original.length - 10 + 50 + 777);
    });
  });

  group('streaming writer end-to-end (MP3)', () {
    test('public writeMetadata produces identical bytes to the pure seam',
        () async {
      final audio = _noise(2 * 1024 * 1024 + 12345); // > 1 MiB
      final mp3 = _buildMp3(audio);
      final target = p.join(tmpDir.path, 'book.mp3');
      await File(target).writeAsBytes(mp3);

      const book = Audiobook(
        path: '/books/x',
        audioFiles: [],
        title: 'Streaming Book',
        author: 'Author',
      );
      await Mp3Writer.writeMetadata(target, book);

      final written = await File(target).readAsBytes();
      final expected = Mp3Writer.rewriteForTest(mp3, book);
      expect(written, expected,
          reason: 'streamed output must match buffered plan execution');

      // Audio tail must be byte-identical after the new tag.
      final newTagSize = Mp3Writer.syncsafeDecode(written, 6);
      expect(written.sublist(10 + newTagSize), audio);

      // No orphan temp files.
      expect(await tmpDir.list().toList(), hasLength(1));
    });
  });
}
