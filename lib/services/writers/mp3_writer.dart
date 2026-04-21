import 'dart:io';
import 'dart:typed_data';
import 'package:audiovault_editor/models/audiobook.dart';

class Mp3Writer {
  const Mp3Writer._();

  static Future<void> writeMetadata(String filePath, Audiobook book) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();

    final newFrames = <Uint8List>[
      if (book.title != null && book.title!.isNotEmpty)
        _buildTextField('TIT2', book.title!),
      if (book.subtitle != null) _buildTextField('TIT3', book.subtitle!),
      if (book.author != null) _buildTextField('TPE1', book.author!),
      if (book.narrator != null) _buildTextField('TPE2', book.narrator!),
      if (book.releaseDate != null) _buildTextField('TYER', book.releaseDate!),
      if (book.description != null) _buildCommFrame(book.description!),
      if (book.publisher != null) _buildTextField('TPUB', book.publisher!),
      if (book.language != null) _buildTextField('TLAN', book.language!),
      if (book.genre != null) _buildTextField('TCON', book.genre!),
    ];

    final result = _hasId3(bytes)
        ? _rewriteWithFrames(bytes, newFrames,
            stripIds: {'TIT2', 'TIT3', 'TPE1', 'TPE2', 'TYER', 'COMM', 'TPUB', 'TLAN', 'TCON'})
        : _prepend(bytes, _mergeFrames(newFrames));
    await file.writeAsBytes(result);
  }

  static Future<void> embedCover(String filePath, Uint8List jpeg) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final apic = _buildApicFrame(jpeg);
    final result =
        _hasId3(bytes) ? _rewriteId3(bytes, apic) : _prepend(bytes, apic);
    await file.writeAsBytes(result);
  }

  // ── Frame builders ────────────────────────────────────────────────────────

  static Uint8List _buildApicFrame(Uint8List jpeg) {
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
    return _buildFrame('APIC', payload);
  }

  static Uint8List _buildTextField(String id, String value) {
    final encoded = Uint8List.fromList([0x00, ...value.codeUnits]);
    return _buildFrame(id, encoded);
  }

  static Uint8List _buildCommFrame(String text) {
    final textBytes = Uint8List.fromList(
        [0x00, 0x65, 0x6E, 0x67, 0x00, ...text.codeUnits]);
    return _buildFrame('COMM', textBytes);
  }

  static Uint8List _buildFrame(String id, Uint8List payload) {
    final frame = Uint8List(10 + payload.length);
    for (int i = 0; i < 4; i++) {
      frame[i] = id.codeUnitAt(i);
    }
    final sz = payload.length;
    frame[4] = (sz >> 24) & 0xFF;
    frame[5] = (sz >> 16) & 0xFF;
    frame[6] = (sz >> 8) & 0xFF;
    frame[7] = sz & 0xFF;
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

  static Uint8List _rewriteId3(Uint8List bytes, Uint8List apic) {
    final tagSize = syncsafeDecode(bytes, 6);
    final tagEnd = 10 + tagSize;
    final audioData = bytes.sublist(tagEnd);
    final frames = <Uint8List>[];
    int pos = 10;
    if (bytes[5] & 0x40 != 0) {
      final extSize = syncsafeDecode(bytes, 10);
      pos += 4 + extSize;
    }
    while (pos + 10 <= tagEnd) {
      final frameId = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      if (frameId == '\x00\x00\x00\x00') break;
      final frameSize = (bytes[pos + 4] << 24) |
          (bytes[pos + 5] << 16) |
          (bytes[pos + 6] << 8) |
          bytes[pos + 7];
      if (frameSize <= 0 || pos + 10 + frameSize > tagEnd) break;
      if (frameId != 'APIC') {
        frames.add(
            Uint8List.fromList(bytes.sublist(pos, pos + 10 + frameSize)));
      }
      pos += 10 + frameSize;
    }
    frames.add(apic);
    return _buildTag(frames, audioData);
  }

  static Uint8List _rewriteWithFrames(
      Uint8List bytes, List<Uint8List> newFrames,
      {required Set<String> stripIds}) {
    final tagSize = syncsafeDecode(bytes, 6);
    final tagEnd = 10 + tagSize;
    final audioData = bytes.sublist(tagEnd);
    final frames = <Uint8List>[];
    int pos = 10;
    if (bytes[5] & 0x40 != 0) {
      final extSize = syncsafeDecode(bytes, 10);
      pos += 4 + extSize;
    }
    while (pos + 10 <= tagEnd) {
      final frameId = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      if (frameId == '\x00\x00\x00\x00') break;
      final frameSize = (bytes[pos + 4] << 24) |
          (bytes[pos + 5] << 16) |
          (bytes[pos + 6] << 8) |
          bytes[pos + 7];
      if (frameSize <= 0 || pos + 10 + frameSize > tagEnd) break;
      if (!stripIds.contains(frameId)) {
        frames.add(
            Uint8List.fromList(bytes.sublist(pos, pos + 10 + frameSize)));
      }
      pos += 10 + frameSize;
    }
    frames.addAll(newFrames);
    return _buildTag(frames, audioData);
  }

  static Uint8List _prepend(Uint8List audioData, Uint8List frame) =>
      _buildTag([frame], audioData);

  static Uint8List _buildTag(List<Uint8List> frames, Uint8List audioData) {
    final framesSize = frames.fold(0, (s, f) => s + f.length);
    final tag = Uint8List(10 + framesSize);
    tag[0] = 0x49; tag[1] = 0x44; tag[2] = 0x33;
    tag[3] = 0x03; tag[4] = 0x00;
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

  static Uint8List _mergeFrames(List<Uint8List> frames) {
    final total = frames.fold(0, (s, f) => s + f.length);
    final out = Uint8List(total);
    int off = 0;
    for (final f in frames) {
      out.setRange(off, off + f.length, f);
      off += f.length;
    }
    return out;
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
