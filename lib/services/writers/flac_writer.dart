import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:audiovault_editor/models/audiobook.dart';

class FlacWriter {
  const FlacWriter._();

  // ── Text metadata write ───────────────────────────────────────────────────

  /// Writes Vorbis comment text tags into a FLAC file.
  /// Existing PICTURE blocks and unknown comment keys are preserved.
  /// Returns without error if the file is not a valid FLAC.
  static Future<void> writeMetadata(String filePath, Audiobook book) async {
    final bytes = await File(filePath).readAsBytes();
    if (!_isFlac(bytes)) return;
    final result = _rewriteVorbisComment(bytes, book);
    await File(filePath).writeAsBytes(result);
  }

  /// Builds a Vorbis comment block payload from [book].
  /// Exposed for tests.
  static Uint8List buildVorbisCommentBlock(
      Audiobook book, {
      String vendor = 'AudioVault Editor',
      List<String> extraComments = const [],
  }) {
    final comments = <String>[
      if (book.title != null && book.title!.isNotEmpty) 'ALBUM=${book.title}',
      if (book.author != null && book.author!.isNotEmpty) 'ARTIST=${book.author}',
      if (book.narrator != null && book.narrator!.isNotEmpty) 'PERFORMER=${book.narrator}',
      if (book.releaseDate != null && book.releaseDate!.isNotEmpty) 'DATE=${book.releaseDate}',
      if (book.description != null && book.description!.isNotEmpty) 'COMMENT=${book.description}',
      if (book.publisher != null && book.publisher!.isNotEmpty) 'ORGANIZATION=${book.publisher}',
      if (book.language != null && book.language!.isNotEmpty) 'LANGUAGE=${book.language}',
      if (book.genre != null && book.genre!.isNotEmpty) 'GENRE=${book.genre}',
      ...extraComments,
    ];
    return _encodeVorbisComment(vendor, comments);
  }

  static Uint8List _rewriteVorbisComment(Uint8List bytes, Audiobook book) {
    // Parse existing blocks; collect vendor string and unknown keys from
    // any existing VORBIS_COMMENT block (type 4).
    String? existingVendor;
    final preservedComments = <String>[];

    final blocks = <(int, Uint8List)>[];
    int pos = 4;
    bool isLast = false;
    while (!isLast && pos + 4 <= bytes.length) {
      final header = bytes[pos];
      isLast = (header & 0x80) != 0;
      final type = header & 0x7F;
      final len =
          (bytes[pos + 1] << 16) | (bytes[pos + 2] << 8) | bytes[pos + 3];
      pos += 4;
      if (pos + len > bytes.length) break;
      final blockData = Uint8List.fromList(bytes.sublist(pos, pos + len));
      if (type == 4) {
        // Parse existing Vorbis comment to extract vendor and unknown keys.
        final parsed = _parseVorbisComment(blockData);
        existingVendor = parsed.$1;
        // Preserve comments whose keys we don't manage.
        const managedKeys = {
          'ALBUM', 'ARTIST', 'PERFORMER', 'DATE',
          'COMMENT', 'ORGANIZATION', 'LANGUAGE', 'GENRE',
        };
        for (final c in parsed.$2) {
          final key = c.contains('=')
              ? c.substring(0, c.indexOf('=')).toUpperCase()
              : c.toUpperCase();
          if (!managedKeys.contains(key)) preservedComments.add(c);
        }
        // Drop the old block — we'll inject a new one below.
      } else {
        blocks.add((type, blockData));
      }
      pos += len;
    }
    final audioData = bytes.sublist(pos);

    final newCommentData = buildVorbisCommentBlock(
      book,
      vendor: existingVendor ?? 'AudioVault Editor',
      extraComments: preservedComments,
    );

    final out = BytesBuilder();
    out.add([0x66, 0x4C, 0x61, 0x43]); // fLaC
    for (final (type, data) in blocks) {
      final hdr = Uint8List(4);
      hdr[0] = type & 0x7F; // not last
      hdr[1] = (data.length >> 16) & 0xFF;
      hdr[2] = (data.length >> 8) & 0xFF;
      hdr[3] = data.length & 0xFF;
      out.add(hdr);
      out.add(data);
    }
    // Vorbis comment block — not last (PICTURE may follow, or audio)
    final vcHdr = Uint8List(4);
    vcHdr[0] = 4 & 0x7F; // type 4, not last
    vcHdr[1] = (newCommentData.length >> 16) & 0xFF;
    vcHdr[2] = (newCommentData.length >> 8) & 0xFF;
    vcHdr[3] = newCommentData.length & 0xFF;
    out.add(vcHdr);
    out.add(newCommentData);
    // Padding block as last metadata block (type 1, 4 bytes of zeros)
    out.add([0x80 | 1, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00]);
    out.add(audioData);
    return out.toBytes();
  }

  /// Parses a Vorbis comment block payload.
  /// Returns (vendorString, [comment strings]).
  static (String, List<String>) _parseVorbisComment(Uint8List data) {
    if (data.length < 4) return ('', const []);
    int off = 0;
    final vendorLen = _readUint32LE(data, off); off += 4;
    if (off + vendorLen > data.length) return ('', const []);
    final vendor = utf8.decode(data.sublist(off, off + vendorLen),
        allowMalformed: true);
    off += vendorLen;
    if (off + 4 > data.length) return (vendor, const []);
    final count = _readUint32LE(data, off); off += 4;
    final comments = <String>[];
    for (int i = 0; i < count; i++) {
      if (off + 4 > data.length) break;
      final len = _readUint32LE(data, off); off += 4;
      if (off + len > data.length) break;
      comments.add(utf8.decode(data.sublist(off, off + len),
          allowMalformed: true));
      off += len;
    }
    return (vendor, comments);
  }

  static Uint8List _encodeVorbisComment(
      String vendor, List<String> comments) {
    final vendorBytes = utf8.encode(vendor);
    final commentBytes = comments.map(utf8.encode).toList();
    final totalLen = 4 + vendorBytes.length +
        4 +
        commentBytes.fold<int>(0, (s, c) => s + 4 + c.length);
    final out = Uint8List(totalLen);
    int off = 0;
    _writeUint32LE(out, off, vendorBytes.length); off += 4;
    out.setRange(off, off + vendorBytes.length, vendorBytes); off += vendorBytes.length;
    _writeUint32LE(out, off, commentBytes.length); off += 4;
    for (final c in commentBytes) {
      _writeUint32LE(out, off, c.length); off += 4;
      out.setRange(off, off + c.length, c); off += c.length;
    }
    return out;
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

  // ── Cover embed ───────────────────────────────────────────────────────────

  static Future<void> embedCover(String filePath, Uint8List jpeg) async {
    final bytes = await File(filePath).readAsBytes();
    if (!_isFlac(bytes)) return;
    final result = _rewriteMetadata(bytes, buildPictureBlock(jpeg));
    await File(filePath).writeAsBytes(result);
  }

  static bool _isFlac(Uint8List bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x66 &&
      bytes[1] == 0x4C &&
      bytes[2] == 0x61 &&
      bytes[3] == 0x43;

  /// Builds a raw FLAC PICTURE block payload. Exposed for tests.
  static Uint8List buildPictureBlock(Uint8List jpeg) {
    const mime = 'image/jpeg';
    final mimeBytes = Uint8List.fromList(mime.codeUnits);
    final data =
        Uint8List(4 + 4 + mimeBytes.length + 4 + 4 * 5 + jpeg.length);
    int off = 0;
    _writeUint32BE(data, off, 3); off += 4; // cover (front)
    _writeUint32BE(data, off, mimeBytes.length); off += 4;
    data.setRange(off, off + mimeBytes.length, mimeBytes);
    off += mimeBytes.length;
    _writeUint32BE(data, off, 0); off += 4; // description length
    _writeUint32BE(data, off, 0); off += 4; // width
    _writeUint32BE(data, off, 0); off += 4; // height
    _writeUint32BE(data, off, 0); off += 4; // color depth
    _writeUint32BE(data, off, 0); off += 4; // color count
    _writeUint32BE(data, off, jpeg.length); off += 4;
    data.setRange(off, off + jpeg.length, jpeg);
    return data;
  }

  static Uint8List _rewriteMetadata(
      Uint8List bytes, Uint8List pictureData) {
    final blocks = <(int, Uint8List)>[];
    int pos = 4;
    bool isLast = false;
    while (!isLast && pos + 4 <= bytes.length) {
      final header = bytes[pos];
      isLast = (header & 0x80) != 0;
      final type = header & 0x7F;
      final len =
          (bytes[pos + 1] << 16) | (bytes[pos + 2] << 8) | bytes[pos + 3];
      pos += 4;
      if (pos + len > bytes.length) break;
      if (type != 6) {
        blocks.add(
            (type, Uint8List.fromList(bytes.sublist(pos, pos + len))));
      }
      pos += len;
    }
    final audioData = bytes.sublist(pos);

    final out = BytesBuilder();
    out.add([0x66, 0x4C, 0x61, 0x43]); // fLaC
    for (final (type, data) in blocks) {
      final hdr = Uint8List(4);
      hdr[0] = type & 0x7F;
      hdr[1] = (data.length >> 16) & 0xFF;
      hdr[2] = (data.length >> 8) & 0xFF;
      hdr[3] = data.length & 0xFF;
      out.add(hdr);
      out.add(data);
    }
    final picHdr = Uint8List(4);
    picHdr[0] = 0x80 | 6; // last=true, type=6
    picHdr[1] = (pictureData.length >> 16) & 0xFF;
    picHdr[2] = (pictureData.length >> 8) & 0xFF;
    picHdr[3] = pictureData.length & 0xFF;
    out.add(picHdr);
    out.add(pictureData);
    out.add(audioData);
    return out.toBytes();
  }

  static void _writeUint32BE(Uint8List b, int offset, int value) {
    b[offset] = (value >> 24) & 0xFF;
    b[offset + 1] = (value >> 16) & 0xFF;
    b[offset + 2] = (value >> 8) & 0xFF;
    b[offset + 3] = value & 0xFF;
  }

  // ── Test helpers (exposed for unit tests only) ────────────────────────────

  /// Parses a Vorbis comment block payload. Exposed for tests.
  static (String, List<String>) parseVorbisCommentForTest(Uint8List data) =>
      _parseVorbisComment(data);

  /// Runs the rewrite logic on raw bytes. Exposed for tests.
  static Uint8List rewriteForTest(Uint8List bytes, Audiobook book) {
    if (!_isFlac(bytes)) return bytes;
    return _rewriteVorbisComment(bytes, book);
  }
}
