import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiovault_editor/models/audiobook.dart';
import 'package:audiovault_editor/services/writers/flac_writer.dart';

// ── Helpers ───────────────────────────────────────────────────────────────

/// Builds a minimal valid FLAC file with a STREAMINFO block and optional
/// VORBIS_COMMENT block, followed by fake audio data.
Uint8List _buildMinimalFlac({
  String? existingVendor,
  List<String> existingComments = const [],
  bool includePicture = false,
}) {
  final out = BytesBuilder();
  out.add([0x66, 0x4C, 0x61, 0x43]); // fLaC marker

  // STREAMINFO block (type 0, 34 bytes, not last)
  final streamInfo = Uint8List(34);
  out.add([0x00, 0x00, 0x00, 0x22]); // type=0, not-last, len=34
  out.add(streamInfo);

  if (existingVendor != null) {
    // VORBIS_COMMENT block (type 4)
    final vcData = _encodeVorbisComment(existingVendor, existingComments);
    final hdr = Uint8List(4);
    hdr[0] = 4; // type 4, not last
    hdr[1] = (vcData.length >> 16) & 0xFF;
    hdr[2] = (vcData.length >> 8) & 0xFF;
    hdr[3] = vcData.length & 0xFF;
    out.add(hdr);
    out.add(vcData);
  }

  if (includePicture) {
    // Minimal PICTURE block (type 6, 32 bytes of zeros)
    final picData = Uint8List(32);
    out.add([0x06, 0x00, 0x00, 0x20]); // type=6, not-last, len=32
    out.add(picData);
  }

  // Padding block as last metadata block (type 1, 4 bytes)
  out.add([0x80 | 1, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00]);

  // Fake audio data
  out.add([0xFF, 0xF8, 0x00, 0x00, 0xAA, 0xBB]);
  return out.toBytes();
}

Uint8List _encodeVorbisComment(String vendor, List<String> comments) {
  final vendorBytes = utf8.encode(vendor);
  final commentBytes = comments.map(utf8.encode).toList();
  final totalLen = 4 + vendorBytes.length +
      4 +
      commentBytes.fold<int>(0, (s, c) => s + 4 + c.length);
  final out = Uint8List(totalLen);
  int off = 0;
  _writeLE(out, off, vendorBytes.length); off += 4;
  out.setRange(off, off + vendorBytes.length, vendorBytes); off += vendorBytes.length;
  _writeLE(out, off, commentBytes.length); off += 4;
  for (final c in commentBytes) {
    _writeLE(out, off, c.length); off += 4;
    out.setRange(off, off + c.length, c); off += c.length;
  }
  return out;
}

void _writeLE(Uint8List b, int offset, int value) {
  b[offset] = value & 0xFF;
  b[offset + 1] = (value >> 8) & 0xFF;
  b[offset + 2] = (value >> 16) & 0xFF;
  b[offset + 3] = (value >> 24) & 0xFF;
}

/// Parses all FLAC metadata blocks from [bytes].
/// Returns list of (type, data).
List<(int, Uint8List)> _parseBlocks(Uint8List bytes) {
  final result = <(int, Uint8List)>[];
  int pos = 4;
  bool isLast = false;
  while (!isLast && pos + 4 <= bytes.length) {
    final header = bytes[pos];
    isLast = (header & 0x80) != 0;
    final type = header & 0x7F;
    final len = (bytes[pos + 1] << 16) | (bytes[pos + 2] << 8) | bytes[pos + 3];
    pos += 4;
    if (pos + len > bytes.length) break;
    result.add((type, Uint8List.fromList(bytes.sublist(pos, pos + len))));
    pos += len;
  }
  return result;
}

Audiobook _book({
  String title = 'Test Album',
  String author = 'Test Artist',
  String? narrator,
  String? releaseDate,
  String? description,
  String? publisher,
  String? language,
  String? genre,
}) =>
    Audiobook(
      path: '/fake',
      audioFiles: const ['/fake/test.flac'],
      title: title,
      author: author,
      narrator: narrator,
      releaseDate: releaseDate,
      description: description,
      publisher: publisher,
      language: language,
      genre: genre,
    );

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  group('FlacWriter.buildVorbisCommentBlock', () {
    test('encodes all supported fields', () {
      final book = _book(
        title: 'My Album',
        author: 'My Artist',
        narrator: 'My Narrator',
        releaseDate: '2024',
        description: 'A description',
        publisher: 'My Publisher',
        language: 'en',
        genre: 'Audiobook',
      );
      final data = FlacWriter.buildVorbisCommentBlock(book);
      final (vendor, comments) = FlacWriter.parseVorbisCommentForTest(data);
      expect(vendor, 'AudioVault Editor');
      final map = {
        for (final c in comments)
          c.substring(0, c.indexOf('=')): c.substring(c.indexOf('=') + 1),
      };
      expect(map['ALBUM'], 'My Album');
      expect(map['ARTIST'], 'My Artist');
      expect(map['PERFORMER'], 'My Narrator');
      expect(map['DATE'], '2024');
      expect(map['COMMENT'], 'A description');
      expect(map['ORGANIZATION'], 'My Publisher');
      expect(map['LANGUAGE'], 'en');
      expect(map['GENRE'], 'Audiobook');
    });

    test('omits null fields', () {
      final book = _book(title: 'Only Title', author: 'Only Author');
      final data = FlacWriter.buildVorbisCommentBlock(book);
      final (_, comments) = FlacWriter.parseVorbisCommentForTest(data);
      final keys = comments.map((c) => c.substring(0, c.indexOf('='))).toSet();
      expect(keys, containsAll(['ALBUM', 'ARTIST']));
      expect(keys, isNot(contains('PERFORMER')));
      expect(keys, isNot(contains('DATE')));
    });

    test('preserves custom vendor string', () {
      final book = _book();
      final data = FlacWriter.buildVorbisCommentBlock(book, vendor: 'MyEncoder');
      final (vendor, _) = FlacWriter.parseVorbisCommentForTest(data);
      expect(vendor, 'MyEncoder');
    });

    test('includes extraComments', () {
      final book = _book();
      final data = FlacWriter.buildVorbisCommentBlock(
          book, extraComments: ['CUSTOM=value']);
      final (_, comments) = FlacWriter.parseVorbisCommentForTest(data);
      expect(comments, contains('CUSTOM=value'));
    });
  });

  group('FlacWriter._rewriteVorbisComment (via writeMetadata bytes)', () {
    test('injects new VORBIS_COMMENT when none exists', () {
      final flac = _buildMinimalFlac();
      final book = _book(title: 'New Title', author: 'New Author');
      final result = FlacWriter.rewriteForTest(flac, book);
      final blocks = _parseBlocks(result);
      final vcBlock = blocks.where((b) => b.$1 == 4).firstOrNull;
      expect(vcBlock, isNotNull);
      final (_, comments) = FlacWriter.parseVorbisCommentForTest(vcBlock!.$2);
      final map = {
        for (final c in comments)
          c.substring(0, c.indexOf('=')): c.substring(c.indexOf('=') + 1),
      };
      expect(map['ALBUM'], 'New Title');
      expect(map['ARTIST'], 'New Author');
    });

    test('replaces existing VORBIS_COMMENT managed keys', () {
      final flac = _buildMinimalFlac(
        existingVendor: 'OldEncoder',
        existingComments: ['ALBUM=Old Title', 'ARTIST=Old Artist'],
      );
      final book = _book(title: 'New Title', author: 'New Author');
      final result = FlacWriter.rewriteForTest(flac, book);
      final blocks = _parseBlocks(result);
      final vcBlock = blocks.where((b) => b.$1 == 4).firstOrNull;
      expect(vcBlock, isNotNull);
      final (vendor, comments) =
          FlacWriter.parseVorbisCommentForTest(vcBlock!.$2);
      expect(vendor, 'OldEncoder'); // vendor preserved
      final map = {
        for (final c in comments)
          c.substring(0, c.indexOf('=')): c.substring(c.indexOf('=') + 1),
      };
      expect(map['ALBUM'], 'New Title');
      expect(map['ARTIST'], 'New Author');
    });

    test('preserves unknown comment keys', () {
      final flac = _buildMinimalFlac(
        existingVendor: 'Encoder',
        existingComments: ['ALBUM=Old', 'CUSTOM_KEY=keep me'],
      );
      final book = _book(title: 'New Title', author: 'New Author');
      final result = FlacWriter.rewriteForTest(flac, book);
      final blocks = _parseBlocks(result);
      final vcBlock = blocks.where((b) => b.$1 == 4).firstOrNull!;
      final (_, comments) = FlacWriter.parseVorbisCommentForTest(vcBlock.$2);
      expect(comments, contains('CUSTOM_KEY=keep me'));
    });

    test('preserves PICTURE block after rewrite', () {
      final flac = _buildMinimalFlac(includePicture: true);
      final book = _book();
      final result = FlacWriter.rewriteForTest(flac, book);
      final blocks = _parseBlocks(result);
      expect(blocks.any((b) => b.$1 == 6), isTrue);
    });

    test('audio data is preserved after rewrite', () {
      final flac = _buildMinimalFlac();
      final book = _book();
      final result = FlacWriter.rewriteForTest(flac, book);
      // Fake audio bytes are [0xFF, 0xF8, 0x00, 0x00, 0xAA, 0xBB]
      expect(result.sublist(result.length - 6),
          equals([0xFF, 0xF8, 0x00, 0x00, 0xAA, 0xBB]));
    });

    test('returns unchanged bytes for non-FLAC input', () {
      final notFlac = Uint8List.fromList([0x00, 0x01, 0x02, 0x03]);
      final book = _book();
      final result = FlacWriter.rewriteForTest(notFlac, book);
      expect(result, equals(notFlac));
    });
  });
}
