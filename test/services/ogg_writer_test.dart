import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiovault_editor/models/audiobook.dart';
import 'package:audiovault_editor/services/writers/ogg_writer.dart';

// ── Helpers ───────────────────────────────────────────────────────────────

void _writeLE(Uint8List b, int offset, int value) {
  b[offset] = value & 0xFF;
  b[offset + 1] = (value >> 8) & 0xFF;
  b[offset + 2] = (value >> 16) & 0xFF;
  b[offset + 3] = (value >> 24) & 0xFF;
}

/// Builds a minimal Vorbis comment packet (type 0x03).
Uint8List _buildVorbisCommentPacket(String vendor, List<String> comments) {
  final vendorBytes = utf8.encode(vendor);
  final commentBytes = comments.map(utf8.encode).toList();
  final out = BytesBuilder();
  // Vorbis comment header: 0x03 + 'vorbis'
  out.add([0x03, 0x76, 0x6F, 0x72, 0x62, 0x69, 0x73]);
  final vl = Uint8List(4);
  _writeLE(vl, 0, vendorBytes.length);
  out.add(vl);
  out.add(vendorBytes);
  final cl = Uint8List(4);
  _writeLE(cl, 0, commentBytes.length);
  out.add(cl);
  for (final c in commentBytes) {
    final ll = Uint8List(4);
    _writeLE(ll, 0, c.length);
    out.add(ll);
    out.add(c);
  }
  out.addByte(0x01); // framing bit
  return out.toBytes();
}

/// Computes the OGG CRC-32 checksum.
int _oggCrc32(Uint8List data) {
  const poly = 0x04C11DB7;
  final table = List<int>.filled(256, 0);
  for (int i = 0; i < 256; i++) {
    int r = i << 24;
    for (int j = 0; j < 8; j++) {
      r = (r & 0x80000000) != 0 ? (r << 1) ^ poly : r << 1;
      r &= 0xFFFFFFFF;
    }
    table[i] = r;
  }
  int crc = 0;
  for (final b in data) {
    crc = ((crc << 8) ^ table[((crc >> 24) ^ b) & 0xFF]) & 0xFFFFFFFF;
  }
  return crc;
}

/// Wraps [packet] in a single OGG page.
Uint8List _buildOggPage(Uint8List packet, {int pageSeq = 1}) {
  final segs = <int>[];
  int remaining = packet.length;
  while (remaining >= 255) {
    segs.add(255);
    remaining -= 255;
  }
  segs.add(remaining);

  final headerSize = 27 + segs.length;
  final page = Uint8List(headerSize + packet.length);
  // Capture magic
  page[0] = 0x4F; page[1] = 0x67; page[2] = 0x67; page[3] = 0x53;
  page[4] = 0; // version
  page[5] = 0; // header type
  // granule position (8 bytes) = 0
  // serial number (4 bytes) = 1
  page[14] = 1;
  // page sequence number
  page[18] = pageSeq & 0xFF;
  // CRC placeholder = 0
  page[26] = segs.length;
  page.setRange(27, 27 + segs.length, segs);
  page.setRange(headerSize, headerSize + packet.length, packet);
  final crc = _oggCrc32(page);
  page[22] = crc & 0xFF;
  page[23] = (crc >> 8) & 0xFF;
  page[24] = (crc >> 16) & 0xFF;
  page[25] = (crc >> 24) & 0xFF;
  return page;
}

/// Builds a minimal OGG file with an identification page (page 0) and a
/// comment page (page 1) containing [vendor] and [comments].
Uint8List _buildMinimalOgg(String vendor, List<String> comments) {
  // Page 0: Vorbis identification header (type 0x01)
  final idPacket = Uint8List(30);
  idPacket[0] = 0x01;
  idPacket.setRange(1, 7, [0x76, 0x6F, 0x72, 0x62, 0x69, 0x73]);
  final page0 = _buildOggPage(idPacket, pageSeq: 0);

  // Page 1: Vorbis comment header
  final commentPacket = _buildVorbisCommentPacket(vendor, comments);
  final page1 = _buildOggPage(commentPacket);

  return Uint8List.fromList([...page0, ...page1]);
}

/// Extracts the Vorbis comment packet from an OGG file.
Map<String, String> _extractComments(Uint8List bytes) {
  int pos = 0;
  while (pos + 27 <= bytes.length) {
    final numSegs = bytes[pos + 26];
    if (pos + 27 + numSegs > bytes.length) break;
    final segTable = bytes.sublist(pos + 27, pos + 27 + numSegs);
    final pageDataLen = segTable.fold(0, (s, v) => s + v);
    final pageStart = pos + 27 + numSegs;
    if (pageStart + pageDataLen > bytes.length) break;
    final pageData = bytes.sublist(pageStart, pageStart + pageDataLen);
    if (pageData.length >= 7 &&
        pageData[0] == 0x03 &&
        pageData[1] == 0x76 &&
        pageData[2] == 0x6F &&
        pageData[3] == 0x72 &&
        pageData[4] == 0x62 &&
        pageData[5] == 0x69 &&
        pageData[6] == 0x73) {
      int off = 7;
      final vendorLen = pageData[off] |
          (pageData[off + 1] << 8) |
          (pageData[off + 2] << 16) |
          (pageData[off + 3] << 24);
      off += 4 + vendorLen;
      final count = pageData[off] |
          (pageData[off + 1] << 8) |
          (pageData[off + 2] << 16) |
          (pageData[off + 3] << 24);
      off += 4;
      final result = <String, String>{};
      for (int i = 0; i < count; i++) {
        final len = pageData[off] |
            (pageData[off + 1] << 8) |
            (pageData[off + 2] << 16) |
            (pageData[off + 3] << 24);
        off += 4;
        final str = utf8.decode(pageData.sublist(off, off + len),
            allowMalformed: true);
        off += len;
        final eq = str.indexOf('=');
        if (eq > 0) result[str.substring(0, eq).toUpperCase()] = str.substring(eq + 1);
      }
      return result;
    }
    pos = pageStart + pageDataLen;
  }
  return {};
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
      audioFiles: const ['/fake/test.ogg'],
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
  group('OggWriter.writeMetadata (via rewriteCommentsForTest)', () {
    test('writes all supported fields', () {
      final ogg = _buildMinimalOgg('Encoder', []);
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
      final result = OggWriter.rewriteCommentsForTest(ogg, book);
      expect(result, isNotNull);
      final map = _extractComments(result!);
      expect(map['ALBUM'], 'My Album');
      expect(map['ARTIST'], 'My Artist');
      expect(map['PERFORMER'], 'My Narrator');
      expect(map['DATE'], '2024');
      expect(map['COMMENT'], 'A description');
      expect(map['ORGANIZATION'], 'My Publisher');
      expect(map['LANGUAGE'], 'en');
      expect(map['GENRE'], 'Audiobook');
    });

    test('replaces existing managed keys', () {
      final ogg = _buildMinimalOgg('Encoder', ['ALBUM=Old', 'ARTIST=Old Artist']);
      final book = _book(title: 'New Title', author: 'New Author');
      final result = OggWriter.rewriteCommentsForTest(ogg, book);
      expect(result, isNotNull);
      final map = _extractComments(result!);
      expect(map['ALBUM'], 'New Title');
      expect(map['ARTIST'], 'New Author');
    });

    test('preserves unknown comment keys', () {
      final ogg = _buildMinimalOgg('Encoder', ['ALBUM=Old', 'CUSTOM=keep me']);
      final book = _book(title: 'New Title', author: 'New Author');
      final result = OggWriter.rewriteCommentsForTest(ogg, book);
      expect(result, isNotNull);
      final map = _extractComments(result!);
      expect(map['CUSTOM'], 'keep me');
    });

    test('preserves METADATA_BLOCK_PICTURE', () {
      const picValue = 'METADATA_BLOCK_PICTURE=AAAA';
      final ogg = _buildMinimalOgg('Encoder', [picValue]);
      final book = _book(title: 'Title', author: 'Author');
      final result = OggWriter.rewriteCommentsForTest(ogg, book);
      expect(result, isNotNull);
      final map = _extractComments(result!);
      expect(map['METADATA_BLOCK_PICTURE'], 'AAAA');
    });

    test('omits null fields', () {
      final ogg = _buildMinimalOgg('Encoder', []);
      final book = _book(title: 'Title', author: 'Author');
      final result = OggWriter.rewriteCommentsForTest(ogg, book);
      expect(result, isNotNull);
      final map = _extractComments(result!);
      expect(map.containsKey('PERFORMER'), isFalse);
      expect(map.containsKey('DATE'), isFalse);
    });

    test('returns null for invalid OGG', () {
      final notOgg = Uint8List.fromList([0x00, 0x01, 0x02, 0x03]);
      final book = _book();
      final result = OggWriter.rewriteCommentsForTest(notOgg, book);
      expect(result, isNull);
    });
  });
}
