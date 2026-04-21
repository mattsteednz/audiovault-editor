import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:audiovault_editor/models/audiobook.dart';
import 'package:audiovault_editor/services/writers/flac_writer.dart';

class OggWriter {
  const OggWriter._();

  // ── Text metadata write ───────────────────────────────────────────────────

  /// Writes Vorbis comment text tags into an OGG file.
  /// Existing METADATA_BLOCK_PICTURE and unknown comment keys are preserved.
  static Future<void> writeMetadata(String filePath, Audiobook book) async {
    final bytes = await File(filePath).readAsBytes();
    final result = _rewriteComments(bytes, book);
    if (result != null) await File(filePath).writeAsBytes(result);
  }

  static Uint8List? _rewriteComments(Uint8List bytes, Audiobook book) {
    const managedKeys = {
      'ALBUM', 'ARTIST', 'PERFORMER', 'DATE',
      'COMMENT', 'ORGANIZATION', 'LANGUAGE', 'GENRE',
    };

    int pos = 0;
    while (pos + 27 <= bytes.length) {
      if (bytes[pos] != 0x4F ||
          bytes[pos + 1] != 0x67 ||
          bytes[pos + 2] != 0x67 ||
          bytes[pos + 3] != 0x53) {
        return null;
      }
      final numSegs = bytes[pos + 26];
      if (pos + 27 + numSegs > bytes.length) return null;
      final segTable = bytes.sublist(pos + 27, pos + 27 + numSegs);
      final pageDataLen = segTable.fold(0, (s, v) => s + v);
      final pageStart = pos + 27 + numSegs;
      if (pageStart + pageDataLen > bytes.length) return null;
      final pageData = bytes.sublist(pageStart, pageStart + pageDataLen);
      final pageEnd = pageStart + pageDataLen;

      if (pageData.length >= 7 &&
          pageData[0] == 0x03 &&
          pageData[1] == 0x76 &&
          pageData[2] == 0x6F &&
          pageData[3] == 0x72 &&
          pageData[4] == 0x62 &&
          pageData[5] == 0x69 &&
          pageData[6] == 0x73) {
        final newComments = <String>[
          if (book.title != null && book.title!.isNotEmpty)
            'ALBUM=${book.title}',
          if (book.author != null && book.author!.isNotEmpty)
            'ARTIST=${book.author}',
          if (book.narrator != null && book.narrator!.isNotEmpty)
            'PERFORMER=${book.narrator}',
          if (book.releaseDate != null && book.releaseDate!.isNotEmpty)
            'DATE=${book.releaseDate}',
          if (book.description != null && book.description!.isNotEmpty)
            'COMMENT=${book.description}',
          if (book.publisher != null && book.publisher!.isNotEmpty)
            'ORGANIZATION=${book.publisher}',
          if (book.language != null && book.language!.isNotEmpty)
            'LANGUAGE=${book.language}',
          if (book.genre != null && book.genre!.isNotEmpty)
            'GENRE=${book.genre}',
        ];
        final newPageData =
            _rewriteVorbisCommentPacket(pageData, newComments, managedKeys);
        if (newPageData == null) return null;
        final newPage = _rebuildOggPage(bytes, pos, segTable, newPageData);
        final result =
            Uint8List(bytes.length - (pageEnd - pos) + newPage.length);
        result.setRange(0, pos, bytes.sublist(0, pos));
        result.setRange(pos, pos + newPage.length, newPage);
        result.setRange(
            pos + newPage.length, result.length, bytes.sublist(pageEnd));
        return result;
      }

      pos = pageEnd;
    }
    return null;
  }

  // ── Cover embed ───────────────────────────────────────────────────────────

  static Future<void> embedCover(String filePath, Uint8List jpeg) async {
    final bytes = await File(filePath).readAsBytes();
    final result = _rewriteCover(bytes, jpeg);
    if (result != null) await File(filePath).writeAsBytes(result);
  }

  static Uint8List? _rewriteCover(Uint8List bytes, Uint8List jpeg) {
    final pictureData = FlacWriter.buildPictureBlock(jpeg);
    final b64 = base64Encode(pictureData);
    final newComment = 'METADATA_BLOCK_PICTURE=$b64';

    int pos = 0;
    while (pos + 27 <= bytes.length) {
      if (bytes[pos] != 0x4F ||
          bytes[pos + 1] != 0x67 ||
          bytes[pos + 2] != 0x67 ||
          bytes[pos + 3] != 0x53) {
        return null;
      }
      final numSegs = bytes[pos + 26];
      if (pos + 27 + numSegs > bytes.length) return null;
      final segTable = bytes.sublist(pos + 27, pos + 27 + numSegs);
      final pageDataLen = segTable.fold(0, (s, v) => s + v);
      final pageStart = pos + 27 + numSegs;
      if (pageStart + pageDataLen > bytes.length) return null;
      final pageData = bytes.sublist(pageStart, pageStart + pageDataLen);
      final pageEnd = pageStart + pageDataLen;

      if (pageData.length >= 7 &&
          pageData[0] == 0x03 &&
          pageData[1] == 0x76 &&
          pageData[2] == 0x6F &&
          pageData[3] == 0x72 &&
          pageData[4] == 0x62 &&
          pageData[5] == 0x69 &&
          pageData[6] == 0x73) {
        final newPageData = _rewriteVorbisCommentPacket(
            pageData, [newComment], const {'METADATA_BLOCK_PICTURE'});
        if (newPageData == null) return null;
        final newPage = _rebuildOggPage(bytes, pos, segTable, newPageData);
        final result =
            Uint8List(bytes.length - (pageEnd - pos) + newPage.length);
        result.setRange(0, pos, bytes.sublist(0, pos));
        result.setRange(pos, pos + newPage.length, newPage);
        result.setRange(
            pos + newPage.length, result.length, bytes.sublist(pageEnd));
        return result;
      }

      pos = pageEnd;
    }
    return null;
  }

  // ── Shared packet rewrite ─────────────────────────────────────────────────

  /// Rewrites the Vorbis comment packet, replacing comments whose keys are in
  /// [replaceKeys] with [newComments], and preserving all others.
  static Uint8List? _rewriteVorbisCommentPacket(
      Uint8List packet, List<String> newComments, Set<String> replaceKeys) {
    if (packet.length < 11) return null;
    int off = 7;
    if (off + 4 > packet.length) return null;
    final vendorLen = _readUint32LE(packet, off);
    off += 4;
    if (off + vendorLen > packet.length) return null;
    final vendor = packet.sublist(off, off + vendorLen);
    off += vendorLen;
    if (off + 4 > packet.length) return null;
    final commentCount = _readUint32LE(packet, off);
    off += 4;

    final preserved = <Uint8List>[];
    for (int i = 0; i < commentCount; i++) {
      if (off + 4 > packet.length) return null;
      final len = _readUint32LE(packet, off);
      off += 4;
      if (off + len > packet.length) return null;
      final comment = packet.sublist(off, off + len);
      off += len;
      final str = String.fromCharCodes(comment);
      final key = str.contains('=')
          ? str.substring(0, str.indexOf('=')).toUpperCase()
          : str.toUpperCase();
      if (!replaceKeys.contains(key)) preserved.add(comment);
    }
    final allComments = [
      ...preserved,
      ...newComments.map((c) => Uint8List.fromList(utf8.encode(c))),
    ];

    final out = BytesBuilder();
    out.add(packet.sublist(0, 7));
    final vl = Uint8List(4);
    _writeUint32LE(vl, 0, vendorLen);
    out.add(vl);
    out.add(vendor);
    final cl = Uint8List(4);
    _writeUint32LE(cl, 0, allComments.length);
    out.add(cl);
    for (final c in allComments) {
      final ll = Uint8List(4);
      _writeUint32LE(ll, 0, c.length);
      out.add(ll);
      out.add(c);
    }
    out.addByte(0x01);
    return out.toBytes();
  }

  static Uint8List _rebuildOggPage(Uint8List original, int pagePos,
      Uint8List oldSegTable, Uint8List newPacket) {
    final newSegs = <int>[];
    int remaining = newPacket.length;
    while (remaining >= 255) {
      newSegs.add(255);
      remaining -= 255;
    }
    newSegs.add(remaining);

    final headerSize = 27 + newSegs.length;
    final page = Uint8List(headerSize + newPacket.length);
    page.setRange(0, 23, original.sublist(pagePos, pagePos + 23));
    page[22] = 0;
    page[23] = 0;
    page[24] = 0;
    page[25] = 0;
    page[26] = newSegs.length;
    page.setRange(27, 27 + newSegs.length, newSegs);
    page.setRange(headerSize, headerSize + newPacket.length, newPacket);

    final crc = _oggCrc32(page);
    page[22] = crc & 0xFF;
    page[23] = (crc >> 8) & 0xFF;
    page[24] = (crc >> 16) & 0xFF;
    page[25] = (crc >> 24) & 0xFF;
    return page;
  }

  static final List<int> _oggCrcTable = () {
    final t = List<int>.filled(256, 0);
    for (int i = 0; i < 256; i++) {
      int r = i << 24;
      for (int j = 0; j < 8; j++) {
        r = (r & 0x80000000) != 0 ? (r << 1) ^ 0x04C11DB7 : r << 1;
        r &= 0xFFFFFFFF;
      }
      t[i] = r;
    }
    return t;
  }();

  static int _oggCrc32(Uint8List data) {
    int crc = 0;
    for (final b in data) {
      crc =
          ((crc << 8) ^ _oggCrcTable[((crc >> 24) ^ b) & 0xFF]) & 0xFFFFFFFF;
    }
    return crc;
  }

  static int _readUint32LE(Uint8List b, int offset) =>
      b[offset] |
      (b[offset + 1] << 8) |
      (b[offset + 2] << 16) |
      (b[offset + 3] << 24);

  static void _writeUint32LE(Uint8List b, int offset, int value) {
    b[offset] = value & 0xFF;
    b[offset + 1] = (value >> 8) & 0xFF;
    b[offset + 2] = (value >> 16) & 0xFF;
    b[offset + 3] = (value >> 24) & 0xFF;
  }

  // ── Test helper ───────────────────────────────────────────────────────────

  /// Runs the comment rewrite logic on raw bytes. Exposed for tests.
  static Uint8List? rewriteCommentsForTest(Uint8List bytes, Audiobook book) =>
      _rewriteComments(bytes, book);
}
