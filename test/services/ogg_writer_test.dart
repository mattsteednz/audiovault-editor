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

/// Splits [packet] across pages of at most [maxSegs] segments each.
/// With all-255 segments except the terminator, intermediate pages end
/// with a 255 segment (continuation) naturally.
List<Uint8List> _packetToPages(Uint8List packet,
    {required int firstSeq, int serial = 1, int maxSegs = 255}) {
  final segs = <int>[];
  int remaining = packet.length;
  while (remaining >= 255) {
    segs.add(255);
    remaining -= 255;
  }
  segs.add(remaining);

  final pages = <Uint8List>[];
  int segPos = 0;
  int bytePos = 0;
  while (segPos < segs.length) {
    final take =
        (segs.length - segPos) > maxSegs ? maxSegs : (segs.length - segPos);
    final pageSegs = segs.sublist(segPos, segPos + take);
    final payloadLen = pageSegs.fold<int>(0, (s, v) => s + v);
    final headerSize = 27 + pageSegs.length;
    final page = Uint8List(headerSize + payloadLen);
    page[0] = 0x4F; page[1] = 0x67; page[2] = 0x67; page[3] = 0x53;
    page[4] = 0;
    page[5] = pages.isEmpty ? 0 : 0x01; // continuation bit
    _writeLE(page, 14, serial);
    _writeLE(page, 18, firstSeq + pages.length);
    page[26] = pageSegs.length;
    page.setRange(27, 27 + pageSegs.length, pageSegs);
    page.setRange(headerSize, headerSize + payloadLen,
        packet.sublist(bytePos, bytePos + payloadLen));
    final crc = _oggCrc32(page);
    page[22] = crc & 0xFF;
    page[23] = (crc >> 8) & 0xFF;
    page[24] = (crc >> 16) & 0xFF;
    page[25] = (crc >> 24) & 0xFF;
    pages.add(page);
    segPos += take;
    bytePos += payloadLen;
  }
  return pages;
}

/// Builds a minimal OGG file with an identification page (page 0) and a
/// comment header carried on one or more pages.
Uint8List _buildMinimalOgg(String vendor, List<String> comments) {
  // Page 0: Vorbis identification header (type 0x01)
  final idPacket = Uint8List(30);
  idPacket[0] = 0x01;
  idPacket.setRange(1, 7, [0x76, 0x6F, 0x72, 0x62, 0x69, 0x73]);
  final page0 = _buildOggPage(idPacket, pageSeq: 0);

  // Comment header pages.
  final commentPacket = _buildVorbisCommentPacket(vendor, comments);
  final commentPages =
      _packetToPages(commentPacket, firstSeq: 1);

  return Uint8List.fromList([
    ...page0,
    for (final pg in commentPages) ...pg,
  ]);
}

/// Extracts the Vorbis comment packet from an OGG file, reassembling it
/// across continuation pages when needed.
Map<String, String> _extractComments(Uint8List bytes) {
  final packet = _extractCommentPacket(bytes);
  if (packet == null) return {};
  int off = 7;
  int readLE() {
    final v = packet[off] |
        (packet[off + 1] << 8) |
        (packet[off + 2] << 16) |
        (packet[off + 3] << 24);
    off += 4;
    return v;
  }

  final vendorLen = readLE();
  off += vendorLen;
  final count = readLE();
  final result = <String, String>{};
  for (int i = 0; i < count; i++) {
    final len = readLE();
    final str =
        utf8.decode(packet.sublist(off, off + len), allowMalformed: true);
    off += len;
    final eq = str.indexOf('=');
    if (eq > 0) {
      result[str.substring(0, eq).toUpperCase()] = str.substring(eq + 1);
    }
  }
  return result;
}

/// Walks OGG pages, finds the comment header packet (starting at offset 0 of
/// a non-continued page), and reassembles it across continuation pages.
Uint8List? _extractCommentPacket(Uint8List bytes) {
  // (headerStart, payloadStart, payloadLen)
  final bounds = <(int, int, int)>[];
  int pos = 0;
  while (pos + 27 <= bytes.length) {
    if (bytes[pos] != 0x4F || bytes[pos + 1] != 0x67) return null;
    final numSegs = bytes[pos + 26];
    final segTable = bytes.sublist(pos + 27, pos + 27 + numSegs);
    final payloadLen = segTable.fold<int>(0, (s, v) => s + v);
    final payloadStart = pos + 27 + numSegs;
    if (payloadStart + payloadLen > bytes.length) return null;
    bounds.add((pos, payloadStart, payloadLen));
    pos = payloadStart + payloadLen;
  }

  for (int i = 0; i < bounds.length; i++) {
    final (hdr, start, len) = bounds[i];
    final first = bytes[start];
    if (first != 0x03) continue;
    if (len < 7) continue;
    const vorbis = [0x76, 0x6F, 0x72, 0x62, 0x69, 0x73];
    var markerOk = true;
    for (int j = 0; j < 6; j++) {
      if (bytes[start + 1 + j] != vorbis[j]) markerOk = false;
    }
    if (!markerOk) continue;

    // Reassemble across continuation pages while lacing chains on.
    final packetBytes = BytesBuilder();
    int pageIdx = i;
    while (true) {
      final (h, ps, pl) = bounds[pageIdx];
      packetBytes.add(bytes.sublist(ps, ps + pl));
      final numSegs = bytes[h + 26];
      final lastSeg = bytes[h + 27 + numSegs - 1];
      final continues = lastSeg == 255;
      pageIdx++;
      if (!continues) break;
      if (pageIdx >= bounds.length) return null;
    }
    return packetBytes.toBytes();
  }
  return null;
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

  group('OggWriter multi-page comment packets', () {
    test('rewrites a comment packet spanning two pages', () {
      // Vendor long enough to push the packet past one page (~65 KB).
      final bigVendor = 'V' * 70000;
      final ogg = _buildMinimalOgg(bigVendor, ['ALBUM=Old', 'KEEPME=yes']);
      expect(_extractComments(ogg)['ALBUM'], 'Old',
          reason: 'sanity: fixture must be readable');

      final result = OggWriter.rewriteCommentsForTest(
          ogg, _book(title: 'New', author: 'Auth'));
      expect(result, isNotNull);

      final map = _extractComments(result!);
      expect(map['ALBUM'], 'New');
      expect(map['ARTIST'], 'Auth');
      expect(map['KEEPME'], 'yes');
    });

    test('emits multi-page output for oversized comments', () {
      final ogg = _buildMinimalOgg('Enc', []);
      // 100 KB description -> new packet far exceeds a single page.
      final book = _book(
          title: 'T', author: 'A', description: 'D' * 100000);

      final result = OggWriter.rewriteCommentsForTest(ogg, book);
      expect(result, isNotNull);
      expect(result!.length, greaterThan(100000));

      final map = _extractComments(result);
      expect(map['COMMENT'], 'D' * 100000);
      expect(map['ALBUM'], 'T');
    });

    test('all output pages carry valid CRCs and contiguous sequences', () {
      final ogg = _buildMinimalOgg('Enc', []);
      final book = _book(title: 'T', author: 'A', description: 'C' * 150000);
      final result = OggWriter.rewriteCommentsForTest(ogg, book)!;

      int pos = 0;
      final seqs = <int>[];
      while (pos + 27 <= result.length) {
        expect(result[pos], 0x4F, reason: 'page magic at $pos');
        expect(result[pos + 1], 0x67);
        expect(result[pos + 2], 0x67);
        expect(result[pos + 3], 0x53);
        final numSegs = result[pos + 26];
        final segSum = result
            .sublist(pos + 27, pos + 27 + numSegs)
            .fold<int>(0, (s, v) => s + v);
        final pageEnd = pos + 27 + numSegs + segSum;
        expect(pageEnd, lessThanOrEqualTo(result.length));

        // CRC check: read stored value, zero field, compute, compare.
        final stored = result.sublist(pos + 22, pos + 26);
        result[pos + 22] = 0;
        result[pos + 23] = 0;
        result[pos + 24] = 0;
        result[pos + 25] = 0;
        final expected = _oggCrc32(result.sublist(pos, pageEnd));
        expect(stored[0], expected & 0xFF, reason: 'CRC byte 0 @$pos');
        expect(stored[1], (expected >> 8) & 0xFF);
        expect(stored[2], (expected >> 16) & 0xFF);
        expect(stored[3], (expected >> 24) & 0xFF);

        seqs.add(result[pos + 18]);
        pos = pageEnd;
      }
      for (int i = 1; i < seqs.length; i++) {
        expect(seqs[i], (seqs[i - 1] + 1) % 256,
            reason: 'sequence numbers must stay contiguous');
      }
    });
  });
}
