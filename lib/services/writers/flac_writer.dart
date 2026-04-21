import 'dart:io';
import 'dart:typed_data';

class FlacWriter {
  const FlacWriter._();

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
}
