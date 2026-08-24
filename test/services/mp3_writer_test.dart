import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiovault_editor/models/audiobook.dart';
import 'package:audiovault_editor/services/writers/id3_writer.dart';

/// Minimal ID3v2 tag parser used by these tests to verify writer output
/// independently of production code.
class _ParsedFrame {
  final String id;
  final Uint8List payload;
  _ParsedFrame(this.id, this.payload);

  /// Decodes the text payload honouring the encoding byte.
  String get text {
    final enc = payload[0];
    final body = payload.sublist(1);
    if (enc == 0x03 || enc == 0x00) {
      return utf8.decode(body); // 0x00 is Latin-1; ASCII test data overlaps.
    }
    if (enc == 0x01) return utf8.decode(body, allowMalformed: true);
    return utf8.decode(body);
  }
}

({int major, List<_ParsedFrame> frames}) _parseTag(Uint8List bytes) {
  expect(bytes[0], 0x49);
  expect(bytes[1], 0x44);
  expect(bytes[2], 0x33);
  final major = bytes[3];
  final tagSize = Mp3Writer.syncsafeDecode(bytes, 6);
  final tagEnd = 10 + tagSize;
  int pos = 10;
  if (bytes[5] & 0x40 != 0) {
    final extSize = Mp3Writer.syncsafeDecode(bytes, 10);
    pos += major >= 4 ? extSize : 4 + extSize;
  }
  final frames = <_ParsedFrame>[];
  while (pos + 10 <= tagEnd) {
    final id = String.fromCharCodes(bytes.sublist(pos, pos + 4));
    if (id == '\x00\x00\x00\x00') break;
    final size = major >= 4
        ? Mp3Writer.syncsafeDecode(bytes, pos + 4)
        : (bytes[pos + 4] << 24) |
            (bytes[pos + 5] << 16) |
            (bytes[pos + 6] << 8) |
            bytes[pos + 7];
    if (size <= 0 || pos + 10 + size > tagEnd) break;
    frames.add(_ParsedFrame(
        id, Uint8List.fromList(bytes.sublist(pos + 10, pos + 10 + size))));
    pos += 10 + size;
  }
  return (major: major, frames: frames);
}

/// Builds a synthetic MP3: ID3v2.[major] tag containing [frames]
/// (id, payload), followed by audio bytes.
Uint8List buildMp3Fixture({
  required int major,
  required Map<String, Uint8List> frames,
  bool extendedHeader = false,
  List<int> audio = const [0xFF, 0xFB, 0x90, 0x00],
}) {
  final frameBytes = <int>[];
  frames.forEach((id, payload) {
    frameBytes.addAll(id.codeUnits);
    final sz = payload.length;
    if (major >= 4) {
      final buf = Uint8List(4);
      Mp3Writer.syncsafeEncode(sz, buf, 0);
      frameBytes.addAll(buf);
    } else {
      frameBytes.addAll([(sz >> 24) & 0xFF, (sz >> 16) & 0xFF, (sz >> 8) & 0xFF, sz & 0xFF]);
    }
    frameBytes.addAll([0x00, 0x00]);
    frameBytes.addAll(payload);
  });

  final header = BytesBuilder();
  header.add([0x49, 0x44, 0x33, major, 0x00, extendedHeader ? 0x40 : 0x00]);
  // Tag size written below once known — use placeholder then patch.
  final tagContent = <int>[...frameBytes];
  final total = 10 + (extendedHeader ? 16 : 0) + tagContent.length;
  final out = BytesBuilder();
  out.add(header.toBytes());
  final sizeBuf = Uint8List(4);
  Mp3Writer.syncsafeEncode(
      total - 10, sizeBuf, 0); // everything after the 10-byte header
  out.add(sizeBuf);
  if (extendedHeader) {
    // v2.3-style extended header: size excludes its own 4-byte field.
    const extBody = 12;
    out.add([(extBody >> 24) & 0xFF, (extBody >> 16) & 0xFF, (extBody >> 8) & 0xFF, extBody]);
    out.add(Uint8List(extBody));
  }
  out.add(tagContent);
  out.add(audio);
  return out.toBytes();
}

Audiobook bookWith({
  String? title,
  String? author,
  String? narrator,
  String? date,
  String? description,
}) =>
    Audiobook(
      path: '/books/test',
      audioFiles: const [],
      title: title,
      author: author,
      narrator: narrator,
      releaseDate: date,
      description: description,
    );

void main() {
  group('Mp3Writer syncsafe integers', () {
    test('round-trips small value', () {
      final buf = Uint8List(4);
      Mp3Writer.syncsafeEncode(127, buf, 0);
      expect(Mp3Writer.syncsafeDecode(buf, 0), 127);
    });

    test('round-trips large value', () {
      final buf = Uint8List(4);
      Mp3Writer.syncsafeEncode(268435455, buf, 0); // max 28-bit syncsafe
      expect(Mp3Writer.syncsafeDecode(buf, 0), 268435455);
    });

    test('round-trips zero', () {
      final buf = Uint8List(4);
      Mp3Writer.syncsafeEncode(0, buf, 0);
      expect(Mp3Writer.syncsafeDecode(buf, 0), 0);
    });

    test('encodes to correct bytes for value 1000', () {
      final buf = Uint8List(4);
      Mp3Writer.syncsafeEncode(1000, buf, 0);
      expect(buf[2], 7);
      expect(buf[3], 104);
    });

    test('offset parameter is respected', () {
      final buf = Uint8List(8);
      Mp3Writer.syncsafeEncode(500, buf, 4);
      expect(Mp3Writer.syncsafeDecode(buf, 4), 500);
      expect(buf[0], 0);
      expect(buf[1], 0);
    });
  });

  group('Mp3Writer yearOnly', () {
    test('extracts years from ISO dates', () {
      expect(Mp3Writer.yearOnlyForTest('2026-04-21'), '2026');
      expect(Mp3Writer.yearOnlyForTest('2026/04/21'), '2026');
      expect(Mp3Writer.yearOnlyForTest('2026'), '2026');
    });
    test('extracts day-first years', () {
      expect(Mp3Writer.yearOnlyForTest('21-04-2026'), '2026');
      expect(Mp3Writer.yearOnlyForTest('21/04/2026'), '2026');
    });
    test('falls back to original when no year parseable', () {
      expect(Mp3Writer.yearOnlyForTest('unknown'), 'unknown');
    });
  });

  group('Mp3Writer rewrite (ID3v2.3)', () {
    test('writes UTF-8 encoded text frames for non-Latin-1 titles', () {
      final mp3 = buildMp3Fixture(major: 3, frames: {});
      const title = 'Café ☕ 日本語';
      final result = Mp3Writer.rewriteForTest(mp3, bookWith(title: title));

      final parsed = _parseTag(result);
      final tit2 = parsed.frames.firstWhere((f) => f.id == 'TIT2');
      expect(tit2.payload[0], 0x03, reason: 'text encoding byte must be UTF-8');
      expect(utf8.decode(tit2.payload.sublist(1)), title);
    });

    test('prepends a v2.3 tag when no tag exists', () {
      final raw = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
      final result =
          Mp3Writer.rewriteForTest(raw, bookWith(title: 'T', author: 'A'));

      final parsed = _parseTag(result);
      expect(parsed.major, 3);
      expect(parsed.frames.map((f) => f.id),
          containsAll(['TIT2', 'TPE1']));
      // Audio data preserved after the tag.
      final tagSize = Mp3Writer.syncsafeDecode(result, 6);
      expect(result.sublist(10 + tagSize), [0xDE, 0xAD, 0xBE, 0xEF]);
    });

    test('replaces managed frames but preserves unmanaged ones', () {
      final preservedPayload =
          Uint8List.fromList([0x00, ...ascii.encode('128')]); // TBPM=128
      final mp3 = buildMp3Fixture(major: 3, frames: {
        'TBPM': preservedPayload,
        'TIT2': Uint8List.fromList([0x00, ...ascii.encode('Old Title')]),
        'TPE1': Uint8List.fromList([0x00, ...ascii.encode('Old Author')]),
      });

      final result =
          Mp3Writer.rewriteForTest(mp3, bookWith(title: 'New', author: 'Auth'));
      final parsed = _parseTag(result);

      expect(parsed.frames.where((f) => f.id == 'TIT2'), hasLength(1));
      expect(
          parsed.frames.firstWhere((f) => f.id == 'TIT2').text, 'New');
      expect(
          parsed.frames.firstWhere((f) => f.id == 'TPE1').text, 'Auth');
      final tbpm = parsed.frames.firstWhere((f) => f.id == 'TBPM');
      expect(tbpm.payload, preservedPayload);
    });

    test('audio data survives rewrite intact', () {
      final audio = List<int>.generate(64, (i) => i * 3 % 256);
      final mp3 = buildMp3Fixture(
          major: 3,
          frames: {'TIT2': Uint8List.fromList([0x00])},
          audio: audio);
      final result =
          Mp3Writer.rewriteForTest(mp3, bookWith(title: 'X'));
      final tagSize = Mp3Writer.syncsafeDecode(result, 6);
      expect(result.sublist(10 + tagSize), audio);
    });
  });

  group('Mp3Writer rewrite (ID3v2.4)', () {
    test('preserves v2.4 version and syncsafe-sized preserved frames', () {
      final bpmPayload =
          Uint8List.fromList([0x03, ...utf8.encode('96')]);
      final mp3 = buildMp3Fixture(major: 4, frames: {
        'TBPM': bpmPayload,
        'TYER': Uint8List.fromList([0x03, ...utf8.encode('1999')]),
      });

      final result = Mp3Writer.rewriteForTest(
          mp3, bookWith(title: 'V4 Book', date: '2007-03-01'));
      final parsed = _parseTag(result);

      expect(parsed.major, 4, reason: 'tag must stay v2.4 when it was v2.4');
      // TYER stripped (managed in v2.4), TDRC written instead.
      expect(parsed.frames.every((f) => f.id != 'TYER'), isTrue);
      expect(parsed.frames.firstWhere((f) => f.id == 'TDRC').text, '2007');
      // TBPM preserved byte-for-byte.
      expect(parsed.frames.firstWhere((f) => f.id == 'TBPM').payload,
          bpmPayload);
      // The TBPM frame's stored size must be syncsafe-parseable.
      for (int i = 0; i < result.length - 10; i++) {
        if (result[i] == 0x54 &&
            result[i + 1] == 0x42 &&
            result[i + 2] == 0x50 &&
            result[i + 3] == 0x4D) {
          expect(Mp3Writer.syncsafeDecode(result, i + 4), bpmPayload.length,
              reason: 'v2.4 frame sizes are syncsafe');
          break;
        }
      }
    });

    test('handles v2.3 extended header without losing frames', () {
      final mp3 = buildMp3Fixture(major: 3, extendedHeader: true, frames: {
        'TIT2': Uint8List.fromList([0x00, ...ascii.encode('Old')]),
      });
      final result = Mp3Writer.rewriteForTest(mp3, bookWith(title: 'Ext'));
      final parsed = _parseTag(result);
      expect(parsed.frames.firstWhere((f) => f.id == 'TIT2').text, 'Ext');
    });
  });
}
