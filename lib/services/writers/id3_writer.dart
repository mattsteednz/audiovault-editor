import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:audiovault_editor/models/audiobook.dart';
import 'package:audiovault_editor/services/writers/atomic_file_writer.dart';

class Mp3Writer {
  const Mp3Writer._();

  /// Frame IDs this writer manages, per ID3v2 major version.
  /// v2.3 uses TYER for the date; v2.4 uses TDRC.
  static const Set<String> managedIdsV23 = {
    'TIT2', 'TIT3', 'TPE1', 'TPE2', 'TYER', 'TDRC', 'COMM', 'TPUB', 'TLAN', 'TCON',
  };
  static const Set<String> managedIdsV24 = {
    'TIT2', 'TIT3', 'TPE1', 'TPE2', 'TDRC', 'TYER', 'COMM', 'TPUB', 'TLAN', 'TCON',
  };

  /// Builds the managed text frames for [book], sized/encoded according to
  /// the given ID3v2 [major] version.
  static List<Uint8List> _managedFrames(Audiobook book, int major) {
    final dateFrameId = major >= 4 ? 'TDRC' : 'TYER';
    return <Uint8List>[
      if (book.title != null && book.title!.isNotEmpty)
        _buildTextField('TIT2', book.title!, major),
      if (book.subtitle != null) _buildTextField('TIT3', book.subtitle!, major),
      if (book.author != null) _buildTextField('TPE1', book.author!, major),
      if (book.narrator != null) _buildTextField('TPE2', book.narrator!, major),
      if (book.releaseDate != null)
        _buildTextField(dateFrameId, _yearOnly(book.releaseDate!), major),
      if (book.description != null) _buildCommFrame(book.description!, major),
      if (book.publisher != null) _buildTextField('TPUB', book.publisher!, major),
      if (book.language != null) _buildTextField('TLAN', book.language!, major),
      if (book.genre != null) _buildTextField('TCON', book.genre!, major),
    ];
  }

  static Future<void> writeMetadata(String filePath, Audiobook book) async {
    final bytes = await File(filePath).readAsBytes();
    final plan = buildPlanForBytes(bytes, book);
    if (plan == null) return;
    await writeFileAtomicSplice(filePath, plan);
  }

  /// Pure core: builds the splice plan for raw MP3 bytes (null → skip).
  @visibleForTesting
  static SplicePlan? planForTest(Uint8List bytes, Audiobook book) =>
      buildPlanForBytes(bytes, book);

  /// Legacy seam retained for existing tests.
  @visibleForTesting
  static Uint8List rewriteForTest(Uint8List bytes, Audiobook book) {
    final plan = buildPlanForBytes(bytes, book)!;
    return plan.execute(bytes);
  }

  static SplicePlan? buildPlanForBytes(Uint8List bytes, Audiobook book) {
    final major = id3MajorVersion(bytes);
    final newFrames = _managedFrames(book, major >= 4 ? 4 : 3);
    if (_hasId3(bytes)) {
      final newTag = _rewriteWithFrames(bytes, newFrames,
          stripIds: major >= 4 ? managedIdsV24 : managedIdsV23);
      final tagSize = syncsafeDecode(bytes, 6);
      // Replace only the tag region; the audio tail is stream-copied.
      return SplicePlan(
          replaceStart: 0, replaceEnd: 10 + tagSize, replacement: newTag);
    }
    // No tag: prepend one. Replacement is tag-only; the whole original file
    // becomes the streamed tail.
    return SplicePlan(
        replaceStart: 0,
        replaceEnd: 0,
        replacement: _buildTag(newFrames, Uint8List(0)));
  }

  static Future<void> embedCover(String filePath, Uint8List jpeg) async {
    final bytes = await File(filePath).readAsBytes();
    final major = id3MajorVersion(bytes);
    final apic = _buildApicFrame(jpeg, major >= 4 ? 4 : 3);
    final newTag = _hasId3(bytes)
        ? _rewriteId3(bytes, apic)
        : _buildTag([apic], Uint8List(0));
    final oldTagSize = _hasId3(bytes) ? 10 + syncsafeDecode(bytes, 6) : 0;
    await writeFileAtomicSplice(
        filePath,
        SplicePlan(
            replaceStart: 0, replaceEnd: oldTagSize, replacement: newTag));
  }

  /// Returns the ID3v2 major version of the tag at the start of [bytes]
  /// (0 when no tag is present). v2.4 tags use syncsafe frame sizes and must
  /// not be reparsed as plain big-endian uint32 sizes.
  static int id3MajorVersion(Uint8List bytes) =>
      _hasId3(bytes) ? bytes[3] : 0;

  // ── Frame builders ────────────────────────────────────────────────────────

  /// Extracts a 4-digit year from a date string.
  /// Accepts bare years ("2026"), ISO dates ("2026-04-21"),
  /// and locale short dates ("21-04-2026" or "21/04/2026").
  /// Falls back to the original string if no year can be parsed.
  static String _yearOnly(String date) => yearOnlyForTest(date);

  /// Test-visible implementation of [_yearOnly].
  @visibleForTesting
  static String yearOnlyForTest(String date) {
    final trimmed = date.trim();
    // Already a bare year
    if (RegExp(r'^\d{4}$').hasMatch(trimmed)) return trimmed;
    // ISO / YYYY-first: 2026-04-21 or 2026/04/21
    final isoMatch = RegExp(r'^(\d{4})[-/]').firstMatch(trimmed);
    if (isoMatch != null) return isoMatch.group(1)!;
    // Day-first: DD-MM-YYYY or DD/MM/YYYY
    final dmyMatch = RegExp(r'^\d{1,2}[-/]\d{1,2}[-/](\d{4})$').firstMatch(trimmed);
    if (dmyMatch != null) return dmyMatch.group(1)!;
    return trimmed;
  }

  static Uint8List _buildApicFrame(Uint8List jpeg, [int major = 3]) {
    const mime = 'image/jpeg';
    final mimeBytes = mime.codeUnits;
    final payload = Uint8List(1 + mimeBytes.length + 1 + 1 + 1 + jpeg.length);
    int off = 0;
    payload[off++] = 0x00;
    for (final b in mimeBytes) {
      payload[off++] = b;
    }
    payload[off++] = 0x00;
    payload[off++] = 0x03;
    payload[off++] = 0x00;
    payload.setRange(off, off + jpeg.length, jpeg);
    return _buildFrame('APIC', payload, major);
  }

  /// Builds a text frame. Text is UTF-8 encoded (encoding byte 0x03, valid in
  /// ID3v2.3 and v2.4), so non-Latin-1 characters survive round-trips.
  static Uint8List _buildTextField(String id, String value,
      [int major = 3]) {
    final encoded = Uint8List.fromList([0x03, ...utf8.encode(value)]);
    return _buildFrame(id, encoded, major);
  }

  static Uint8List _buildCommFrame(String text, [int major = 3]) {
    final textBytes =
        Uint8List.fromList([0x03, 0x65, 0x6E, 0x67, 0x00, ...utf8.encode(text)]);
    return _buildFrame('COMM', textBytes, major);
  }

  static Uint8List _buildFrame(String id, Uint8List payload, int major) {
    final frame = Uint8List(10 + payload.length);
    for (int i = 0; i < 4; i++) {
      frame[i] = id.codeUnitAt(i);
    }
    if (major >= 4) {
      syncsafeEncode(payload.length, frame, 4);
    } else {
      final sz = payload.length;
      frame[4] = (sz >> 24) & 0xFF;
      frame[5] = (sz >> 16) & 0xFF;
      frame[6] = (sz >> 8) & 0xFF;
      frame[7] = sz & 0xFF;
    }
    frame[8] = 0x00;
    frame[9] = 0x00;
    frame.setRange(10, frame.length, payload);
    return frame;
  }

  // ── Tag rewriting ─────────────────────────────────────────────────────────

  static bool _hasId3(Uint8List bytes) =>
      bytes.length >= 3 &&
      bytes[0] == 0x49 &&
      bytes[1] == 0x44 &&
      bytes[2] == 0x33;

  /// Reads a frame size at [pos] honouring the tag's major version:
  /// v2.4 stores syncsafe sizes, v2.3 (and earlier) plain big-endian uint32.
  static int _frameSizeAt(Uint8List bytes, int pos, int major) =>
      major >= 4 ? syncsafeDecode(bytes, pos) : _plainSizeAt(bytes, pos);

  static int _plainSizeAt(Uint8List bytes, int pos) =>
      (bytes[pos] << 24) |
      (bytes[pos + 1] << 16) |
      (bytes[pos + 2] << 8) |
      bytes[pos + 3];

  static Uint8List _rewriteId3(Uint8List bytes, Uint8List apic) {
    final major = id3MajorVersion(bytes);
    final tagSize = syncsafeDecode(bytes, 6);
    final tagEnd = 10 + tagSize;
    // Plan model: replacement is tag-only � the caller streams the tail.
    final Uint8List audioData = Uint8List(0);
    final frames = <Uint8List>[];
    int pos = 10;
    if (bytes[5] & 0x40 != 0) {
      // v2.3: stored size excludes the 4-byte size field itself.
      // v2.4: stored size includes the whole extended header.
      final extSize = syncsafeDecode(bytes, 10);
      pos += major >= 4 ? extSize : 4 + extSize;
    }
    while (pos + 10 <= tagEnd) {
      final frameId = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      if (frameId == '\x00\x00\x00\x00') break;
      final frameSize = _frameSizeAt(bytes, pos + 4, major);
      if (frameSize <= 0 || pos + 10 + frameSize > tagEnd) break;
      if (frameId != 'APIC') {
        frames.add(
            Uint8List.fromList(bytes.sublist(pos, pos + 10 + frameSize)));
      }
      pos += 10 + frameSize;
    }
    frames.add(apic);
    return _buildTag(frames, audioData, major);
  }

  static Uint8List _rewriteWithFrames(
      Uint8List bytes, List<Uint8List> newFrames,
      {required Set<String> stripIds}) {
    final major = id3MajorVersion(bytes);
    final tagSize = syncsafeDecode(bytes, 6);
    final tagEnd = 10 + tagSize;
    // Plan model: replacement is tag-only � the caller streams the tail.
    final Uint8List audioData = Uint8List(0);
    final frames = <Uint8List>[];
    int pos = 10;
    if (bytes[5] & 0x40 != 0) {
      final extSize = syncsafeDecode(bytes, 10);
      pos += major >= 4 ? extSize : 4 + extSize;
    }
    while (pos + 10 <= tagEnd) {
      final frameId = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      if (frameId == '\x00\x00\x00\x00') break;
      final frameSize = _frameSizeAt(bytes, pos + 4, major);
      if (frameSize <= 0 || pos + 10 + frameSize > tagEnd) break;
      if (!stripIds.contains(frameId)) {
        frames.add(
            Uint8List.fromList(bytes.sublist(pos, pos + 10 + frameSize)));
      }
      pos += 10 + frameSize;
    }
    frames.addAll(newFrames);
    return _buildTag(frames, audioData, major);
  }

  static Uint8List _buildTag(List<Uint8List> frames, Uint8List audioData,
      [int major = 3]) {
    final framesSize = frames.fold(0, (s, f) => s + f.length);
    final tag = Uint8List(10 + framesSize);
    tag[0] = 0x49; tag[1] = 0x44; tag[2] = 0x33;
    tag[3] = major; tag[4] = 0x00;
    tag[5] = 0x00;
    syncsafeEncode(framesSize, tag, 6);
    int off = 10;
    for (final f in frames) {
      tag.setRange(off, off + f.length, f);
      off += f.length;
    }
    final result = Uint8List(tag.length + audioData.length);
    result.setRange(0, tag.length, tag);
    result.setRange(tag.length, result.length, audioData);
    return result;
  }

  // ── Syncsafe integers (internal + exposed for tests) ─────────────────────

  /// Decodes a 4-byte syncsafe integer from [b] at [offset].
  static int syncsafeDecode(Uint8List b, int offset) =>
      (b[offset] << 21) |
      (b[offset + 1] << 14) |
      (b[offset + 2] << 7) |
      b[offset + 3];

  /// Encodes [value] as a 4-byte syncsafe integer into [b] at [offset].
  static void syncsafeEncode(int value, Uint8List b, int offset) {
    b[offset + 3] = value & 0x7F; value >>= 7;
    b[offset + 2] = value & 0x7F; value >>= 7;
    b[offset + 1] = value & 0x7F; value >>= 7;
    b[offset] = value & 0x7F;
  }
}
