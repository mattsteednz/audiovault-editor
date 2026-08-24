import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:audiovault_editor/models/audiobook.dart';
import 'package:audiovault_editor/services/app_logger.dart';
import 'package:audiovault_editor/services/writers/flac_writer.dart';
import 'package:audiovault_editor/services/writers/atomic_file_writer.dart';

/// One parsed OGG page (header fields + segment table + payload).
class _OggPage {
  /// Byte offset of this page's header in the source buffer.
  final int start;
  final int headerType;
  final int granulePosition;
  final int serial;
  final int sequence;
  final List<int> segmentTable;
  final Uint8List payload;

  _OggPage({
    required this.start,
    required this.headerType,
    required this.granulePosition,
    required this.serial,
    required this.sequence,
    required this.segmentTable,
    required this.payload,
  });

  bool get isContinuation => (headerType & 0x01) != 0;
  bool get isBos => (headerType & 0x02) != 0;

  /// Total byte offset just past this page.
  int get end =>
      start + 27 + segmentTable.length + payload.length;

  /// The last segment's lacing value — 255 means the final packet on this
  /// page continues onto the next page.
  bool get endsWithContinuation =>
      segmentTable.isNotEmpty && segmentTable.last == 255;
}

class OggWriter {
  const OggWriter._();

  static final List<int> _oggMagic = [
    0x4F, 0x67, 0x67, 0x53 // "OggS"
  ];

  // ── Text metadata write ───────────────────────────────────────────────────

  /// Writes Vorbis comment text tags into an OGG file.
  /// Existing METADATA_BLOCK_PICTURE and unknown comment keys are preserved.
  /// Comment header packets spanning multiple pages are supported; if the
  /// stream layout is too unusual to rewrite safely, nothing is written.
  static Future<void> writeMetadata(String filePath, Audiobook book) async {
    final bytes = await File(filePath).readAsBytes();
    try {
      final result =
          await compute(_rewriteCommentsJob, (bytes: bytes, book: book));
      if (result != null) {
        await writeFileAtomic(filePath, result);
      } else {
        AppLog.w('OGG metadata skipped (unsupported layout): $filePath');
      }
    } catch (e) {
      AppLog.e('OGG metadata write failed for $filePath: $e');
      rethrow;
    }
  }

  static Uint8List? _rewriteCommentsJob(
          ({Uint8List bytes, Audiobook book}) msg) =>
      _rewriteComments(msg.bytes, msg.book);

  static Uint8List? _rewriteComments(Uint8List bytes, Audiobook book) {
    const managedKeys = {
      'ALBUM', 'ARTIST', 'PERFORMER', 'DATE',
      'COMMENT', 'ORGANIZATION', 'LANGUAGE', 'GENRE',
    };
    final newComments = <String>[
      if (book.title != null && book.title!.isNotEmpty) 'ALBUM=${book.title}',
      if (book.author != null && book.author!.isNotEmpty) 'ARTIST=${book.author}',
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
      if (book.genre != null && book.genre!.isNotEmpty) 'GENRE=${book.genre}',
    ];
    return rewriteCommentPacket(bytes, newComments, managedKeys);
  }

  // ── Cover embed ───────────────────────────────────────────────────────────

  static Future<void> embedCover(String filePath, Uint8List jpeg) async {
    final bytes = await File(filePath).readAsBytes();
    try {
      final result =
          await compute(_rewriteCoverJob, (bytes: bytes, jpeg: jpeg));
      if (result != null) {
        await writeFileAtomic(filePath, result);
      } else {
        AppLog.w('OGG cover embed skipped (unsupported layout): $filePath');
      }
    } catch (e) {
      AppLog.e('OGG cover embed failed for $filePath: $e');
      rethrow;
    }
  }

  static Uint8List? _rewriteCoverJob(({Uint8List bytes, Uint8List jpeg}) msg) =>
      _rewriteCover(msg.bytes, msg.jpeg);

  static Uint8List? _rewriteCover(Uint8List bytes, Uint8List jpeg) {
    final pictureData = FlacWriter.buildPictureBlock(jpeg);
    final b64 = base64Encode(pictureData);
    final newComment = 'METADATA_BLOCK_PICTURE=$b64';
    return rewriteCommentPacket(
        bytes, [newComment], const {'METADATA_BLOCK_PICTURE'});
  }

  // ── Shared packet rewrite ─────────────────────────────────────────────────

  /// Rewrites the Vorbis comment header packet, replacing comments whose keys
  /// are in [replaceKeys] with [newComments], preserving all others.
  ///
  /// Handles packets spanning multiple OGG pages. Returns null when the
  /// layout cannot be rewritten safely (caller should skip the write rather
  /// than risk corruption).
  static Uint8List? rewriteCommentPacket(
      Uint8List bytes, List<String> newComments, Set<String> replaceKeys) {
    final pages = _parsePages(bytes);
    if (pages == null || pages.isEmpty) return null;

    // Locate the non-continued page whose payload starts with \x03"vorbis".
    int startIdx = -1;
    for (int i = 0; i < pages.length; i++) {
      final pg = pages[i];
      if (!pg.isContinuation &&
          pg.payload.length >= 7 &&
          pg.payload[0] == 0x03 &&
          _startsWithVorbis(pg.payload, 1)) {
        startIdx = i;
        break;
      }
    }
    if (startIdx == -1) return null;

    // Gather every page the comment packet touches.
    int endIdx = startIdx;
    while (pages[endIdx].endsWithContinuation) {
      endIdx++;
      if (endIdx >= pages.length) return null;
      if (!pages[endIdx].isContinuation) return null; // broken chain
    }

    final oldPacket = BytesBuilder();
    for (int i = startIdx; i <= endIdx; i++) {
      oldPacket.add(pages[i].payload);
    }
    final parsed =
        _rewriteVorbisCommentPacket(oldPacket.toBytes(), newComments, replaceKeys);
    if (parsed == null) return null;

    // Bytes on the final packet page that belong to following packets (e.g.
    // the setup header). They keep their original segmentation verbatim.
    final endPage = pages[endIdx];
    Uint8List trailingBytes;
    List<int> trailingSegs;
    if (!endPage.endsWithContinuation && endIdx == startIdx) {
      // Single-page fast path: packet ends inside its own page.
      final packetLen = _packetLengthFromSegs(endPage.segmentTable);
      trailingBytes = Uint8List.sublistView(
          endPage.payload, packetLen, endPage.payload.length);
      trailingSegs = endPage.segmentTable
          .sublist(_segmentsUsedByPacket(endPage.segmentTable));
    } else if (!endPage.endsWithContinuation && endIdx > startIdx) {
      // Multi-page packet ending mid-page.
      final lastSegs = endPage.segmentTable;
      final used = _segmentsUsedByPacket(lastSegs);
      trailingSegs = lastSegs.sublist(used);
      trailingBytes = Uint8List.sublistView(
          endPage.payload, _sumSegs(lastSegs.take(used)), endPage.payload.length);
    } else {
      trailingBytes = Uint8List(0);
      trailingSegs = const [];
    }

    final newPages = _buildPagesForPacket(
      base: pages[startIdx],
      packet: parsed,
      trailingBytes: trailingBytes,
      trailingSegs: trailingSegs,
    );

    // Renumber subsequent pages of the same stream by the page-count delta.
    final delta = newPages.length - (endIdx - startIdx + 1);
    var out = BytesBuilder();
    out.add(bytes.sublist(0, pages[startIdx].start));
    for (final pg in newPages) {
      out.add(_serializePage(pg));
    }
    if (endIdx + 1 < pages.length) {
      final suffixStart = pages[endIdx].end;
      final suffix = Uint8List.sublistView(bytes, suffixStart);
      if (delta != 0) {
        out.add(_renumberSubsequentPages(suffix, pages[startIdx].serial, delta));
      } else {
        out.add(suffix);
      }
    }
    return out.toBytes();
  }

  static bool _startsWithVorbis(Uint8List b, int off) {
    const marker = [0x76, 0x6F, 0x72, 0x62, 0x69, 0x73]; // "vorbis"
    for (int i = 0; i < marker.length; i++) {
      if (b[off + i] != marker[i]) return false;
    }
    return true;
  }

  /// Parses the buffer into pages; null on structural problems.
  static List<_OggPage>? _parsePages(Uint8List bytes) {
    final pages = <_OggPage>[];
    int pos = 0;
    while (pos + 27 <= bytes.length) {
      for (int i = 0; i < 4; i++) {
        if (bytes[pos + i] != _oggMagic[i]) {
          return pages.isEmpty ? null : pages;
        }
      }
      final numSegs = bytes[pos + 26];
      if (pos + 27 + numSegs > bytes.length) return null;
      final segTable = bytes.sublist(pos + 27, pos + 27 + numSegs).toList();
      final payloadLen = _sumSegs(segTable);
      final payloadStart = pos + 27 + numSegs;
      if (payloadStart + payloadLen > bytes.length) return null;
      pages.add(_OggPage(
        start: pos,
        headerType: bytes[pos + 5],
        granulePosition: _readU64(bytes, pos + 6),
        serial: readUint32LE(bytes, pos + 14),
        sequence: readUint32LE(bytes, pos + 18),
        segmentTable: segTable,
        payload: Uint8List.sublistView(bytes, payloadStart,
            payloadStart + payloadLen),
      ));
      pos = payloadStart + payloadLen;
    }
    return pages;
  }

  /// Serialises a page back to bytes, recomputing the CRC.
  static Uint8List _serializePage(_OggPage pg) {
    final headerSize = 27 + pg.segmentTable.length;
    final page = Uint8List(headerSize + pg.payload.length);
    page.setRange(0, 4, _oggMagic);
    page[4] = 0; // stream structure version
    page[5] = pg.headerType;
    _writeU64(page, 6, pg.granulePosition);
    _writeU32LE(page, 14, pg.serial);
    _writeU32LE(page, 18, pg.sequence);
    // CRC at 22..25 written last.
    page[26] = pg.segmentTable.length;
    page.setRange(27, headerSize, pg.segmentTable);
    page.setRange(headerSize, page.length, pg.payload);

    final crc = _oggCrc32(page);
    page[22] = crc & 0xFF;
    page[23] = (crc >> 8) & 0xFF;
    page[24] = (crc >> 16) & 0xFF;
    page[25] = (crc >> 24) & 0xFF;
    return page;
  }

  /// Builds one or more pages carrying [packet], then [trailingBytes]
  /// (with its original [trailingSegs]) appended to the final page when it
  /// fits within the 255-segment limit.
  static List<_OggPage> _buildPagesForPacket({
    required _OggPage base,
    required Uint8List packet,
    required Uint8List trailingBytes,
    required List<int> trailingSegs,
  }) {
    // Segment the new packet into 255-byte chunks.
    final segs = <int>[];
    int remaining = packet.length;
    while (remaining >= 255) {
      segs.add(255);
      remaining -= 255;
    }
    segs.add(remaining); // terminator (guaranteed < 255)

    // Distribute segments across pages of at most 255 segments.
    final pages = <_OggPage>[];
    int segPos = 0;
    int bytePos = 0;
    while (segPos < segs.length) {
      final take = (segs.length - segPos) > 255 ? 255 : (segs.length - segPos);
      final pageSegs = segs.sublist(segPos, segPos + take);
      final pageBytes = _sumSegs(pageSegs);
      final headerType = pages.isEmpty
          ? (base.headerType & ~0x01) // clear continuation on first page
          : 0x01; // continuation
      pages.add(_OggPage(
        start: 0,
        headerType: headerType,
        granulePosition: base.granulePosition,
        serial: base.serial,
        sequence: 0, // patched during serialization below
        segmentTable: pageSegs.toList(),
        payload: Uint8List.sublistView(packet, bytePos, bytePos + pageBytes),
      ));
      segPos += take;
      bytePos += pageBytes;
    }

    // Append the trailing packets to the last page when possible.
    if (trailingSegs.isNotEmpty) {
      final last = pages.last;
      final fitsSegments = last.segmentTable.length + trailingSegs.length <= 255;
      if (fitsSegments) {
        final mergedSegs = [...last.segmentTable, ...trailingSegs];
        final mergedPayload = BytesBuilder();
        mergedPayload.add(last.payload);
        mergedPayload.add(trailingBytes);
        pages[pages.length - 1] = _OggPage(
          start: 0,
          headerType: last.headerType,
          granulePosition: last.granulePosition,
          serial: last.serial,
          sequence: 0,
          segmentTable: mergedSegs,
          payload: mergedPayload.toBytes(),
        );
      } else {
        pages.add(_OggPage(
          start: 0,
          headerType: 0,
          granulePosition: 0,
          serial: base.serial,
          sequence: 0,
          segmentTable: trailingSegs.toList(),
          payload: Uint8List.fromList(trailingBytes),
        ));
      }
    }

    // Assign sequence numbers.
    for (int i = 0; i < pages.length; i++) {
      pages[i] = _OggPage(
        start: 0,
        headerType: pages[i].headerType,
        granulePosition: pages[i].granulePosition,
        serial: pages[i].serial,
        sequence: base.sequence + i,
        segmentTable: pages[i].segmentTable,
        payload: pages[i].payload,
      );
    }
    return pages;
  }

  /// Adjusts page sequence numbers of the same logical stream in [suffix] by
  /// [delta]. Stops at a new stream's BOS page.
  static Uint8List _renumberSubsequentPages(
      Uint8List suffix, int serial, int delta) {
    final out = Uint8List.fromList(suffix);
    int pos = 0;
    while (pos + 27 <= out.length) {
      bool magicOk = true;
      for (int i = 0; i < 4; i++) {
        if (out[pos + i] != _oggMagic[i]) {
          magicOk = false;
          break;
        }
      }
      if (!magicOk) break;
      final numSegs = out[pos + 26];
      if (pos + 27 + numSegs > out.length) break;
      final segSum = _sumSegs(out.sublist(pos + 27, pos + 27 + numSegs));
      final pageEnd = pos + 27 + numSegs + segSum;
      if (pageEnd > out.length) break;

      final pageSerial = readUint32LE(out, pos + 14);
      final headerType = out[pos + 5];
      if (pageSerial == serial) {
        final seq = readUint32LE(out, pos + 18);
        _writeU32LE(out, pos + 18, seq + delta);
        _fixCrc(out, pos, pageEnd);
      } else if ((headerType & 0x02) != 0) {
        break; // a different stream begins — stop renumbering
      }
      pos = pageEnd;
    }
    return out;
  }

  static void _fixCrc(Uint8List bytes, int start, int end) {
    // Zero the CRC field, recompute over the page range.
    bytes[start + 22] = 0;
    bytes[start + 23] = 0;
    bytes[start + 24] = 0;
    bytes[start + 25] = 0;
    final crc = _oggCrc32(Uint8List.sublistView(bytes, start, end));
    bytes[start + 22] = crc & 0xFF;
    bytes[start + 23] = (crc >> 8) & 0xFF;
    bytes[start + 24] = (crc >> 16) & 0xFF;
    bytes[start + 25] = (crc >> 24) & 0xFF;
  }

  /// Rewrites the Vorbis comment packet body (replacing [replaceKeys] with
  /// [newComments], preserving others). Returns null on malformed input.
  static Uint8List? _rewriteVorbisCommentPacket(
      Uint8List packet, List<String> newComments, Set<String> replaceKeys) {
    if (packet.length < 11) return null;
    if (!(packet[0] == 0x03 && _startsWithVorbis(packet, 1))) return null;
    int off = 7;
    if (off + 4 > packet.length) return null;
    final vendorLen = readUint32LE(packet, off);
    off += 4;
    if (off + vendorLen > packet.length) return null;
    final vendor = packet.sublist(off, off + vendorLen);
    off += vendorLen;
    if (off + 4 > packet.length) return null;
    final commentCount = readUint32LE(packet, off);
    off += 4;

    final preserved = <Uint8List>[];
    for (int i = 0; i < commentCount; i++) {
      if (off + 4 > packet.length) return null;
      final len = readUint32LE(packet, off);
      off += 4;
      if (len < 0 || off + len > packet.length) return null;
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

  // ── Numeric / CRC helpers ─────────────────────────────────────────────────

  static int _sumSegs(Iterable<int> segs) =>
      segs.fold(0, (s, v) => s + v);

  /// Number of segments consumed by the FIRST packet in a page whose final
  /// segment terminates it (last taken segment < 255).
  static int _segmentsUsedByPacket(List<int> segTable) {
    for (int i = 0; i < segTable.length; i++) {
      if (segTable[i] != 255) return i + 1;
    }
    return segTable.length;
  }

  static int _packetLengthFromSegs(List<int> segTable) {
    int total = 0;
    final used = _segmentsUsedByPacket(segTable);
    for (int i = 0; i < used; i++) {
      total += segTable[i];
    }
    return total;
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

  static int readUint32LE(Uint8List b, int offset) =>
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

  static void _writeU32LE(Uint8List b, int offset, int value) =>
      _writeUint32LE(b, offset, value);

  static int _readU64(Uint8List b, int offset) =>
      (readUint32LE(b, offset) |
          (readUint32LE(b, offset + 4) << 32)) &
      0xFFFFFFFFFFFFFFFF;

  static void _writeU64(Uint8List b, int offset, int value) {
    _writeUint32LE(b, offset, value & 0xFFFFFFFF);
    _writeUint32LE(b, offset + 4, (value >> 32) & 0xFFFFFFFF);
  }

  // ── Test helper ───────────────────────────────────────────────────────────

  /// Runs the comment rewrite logic on raw bytes. Exposed for tests.
  static Uint8List? rewriteCommentsForTest(Uint8List bytes, Audiobook book) =>
      _rewriteComments(bytes, book);
}
