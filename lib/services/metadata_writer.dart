import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import '../models/audiobook.dart';

class MetadataWriter {
  /// Converts [imageBytes] to JPEG, returning the original bytes if already JPEG.
  static Future<Uint8List> toJpeg(Uint8List imageBytes) async {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) throw Exception('Could not decode image');
    return Uint8List.fromList(img.encodeJpg(decoded, quality: 92));
  }

  /// Embeds title, author, narrator, and year into all audio files.
  static Future<void> applyMetadata(Audiobook book) async {
    for (final filePath in book.audioFiles) {
      final ext = p.extension(filePath).toLowerCase();
      try {
        if (ext == '.mp3') {
          await _writeMetadataMp3(filePath, book);
        } else if (ext == '.m4b' || ext == '.m4a' || ext == '.aac') {
          await _writeMetadataMp4(filePath, book);
        }
        // FLAC/OGG text tag rewriting not yet implemented
      } catch (_) {}
    }
  }

  /// Writes cover.jpg to the book folder and embeds the cover into all audio files.
  static Future<void> applyCover(Audiobook book, String imagePath) async {    final imageBytes = await File(imagePath).readAsBytes();
    final jpegBytes = await toJpeg(imageBytes);

    // Write cover.jpg
    final coverOut = File(p.join(book.path, 'cover.jpg'));
    await coverOut.writeAsBytes(jpegBytes);

    // Embed into each audio file
    for (final filePath in book.audioFiles) {
      final ext = p.extension(filePath).toLowerCase();
      try {
        if (ext == '.mp3') {
          await _embedCoverMp3(filePath, jpegBytes);
        } else if (ext == '.m4b' || ext == '.m4a' || ext == '.aac') {
          await _embedCoverMp4(filePath, jpegBytes);
        } else if (ext == '.flac') {
          await _embedCoverFlac(filePath, jpegBytes);
        } else if (ext == '.ogg') {
          await _embedCoverOgg(filePath, jpegBytes);
        }
      } catch (e) {
        // Continue with remaining files if one fails
      }
    }
  }

  // ── MP3 ID3v2 cover embedding ─────────────────────────────────────────────
  //
  // Strategy: read the file, strip any existing APIC frames from the ID3v2
  // tag, append a new APIC frame, write back.
  // If no ID3v2 tag exists, prepend a minimal one.

  static Future<void> _embedCoverMp3(String filePath, Uint8List jpeg) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final apic = _buildApicFrame(jpeg);

    Uint8List result;
    if (bytes.length >= 3 &&
        bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) {
      // Has ID3v2 tag — parse size, strip existing APIC, inject new one
      result = _rewriteId3(bytes, apic);
    } else {
      // No ID3v2 — prepend a new minimal tag
      result = _prependId3(bytes, apic);
    }
    await file.writeAsBytes(result);
  }

  static Uint8List _buildApicFrame(Uint8List jpeg) {
    // APIC frame: encoding(1) + mime(n) + 0x00 + pic_type(1) + desc(0) + 0x00 + data
    const mime = 'image/jpeg';
    final mimeBytes = mime.codeUnits;
    final payload = Uint8List(1 + mimeBytes.length + 1 + 1 + 1 + jpeg.length);
    int off = 0;
    payload[off++] = 0x00; // UTF-8 encoding
    for (final b in mimeBytes) { payload[off++] = b; }
    payload[off++] = 0x00; // null terminator
    payload[off++] = 0x03; // picture type: cover (front)
    payload[off++] = 0x00; // empty description + null terminator

    payload.setRange(off, off + jpeg.length, jpeg);

    // Frame header: "APIC" + 4-byte size (big-endian) + 2-byte flags
    final frame = Uint8List(10 + payload.length);
    frame[0] = 0x41; frame[1] = 0x50; frame[2] = 0x49; frame[3] = 0x43; // APIC
    final sz = payload.length;
    frame[4] = (sz >> 24) & 0xFF;
    frame[5] = (sz >> 16) & 0xFF;
    frame[6] = (sz >> 8) & 0xFF;
    frame[7] = sz & 0xFF;
    frame[8] = 0x00; frame[9] = 0x00; // flags
    frame.setRange(10, 10 + payload.length, payload);
    return frame;
  }

  static Uint8List _rewriteId3(Uint8List bytes, Uint8List apic) {
    // Parse existing tag size (syncsafe integer at bytes 6-9)
    final tagSize = _syncsafeDecode(bytes, 6);
    final tagEnd = 10 + tagSize;
    final audioData = bytes.sublist(tagEnd);

    // Collect all frames except APIC
    final frames = <Uint8List>[];
    int pos = 10;
    // Skip extended header if present (flag bit 6 of byte 5)
    if (bytes[5] & 0x40 != 0) {
      final extSize = _syncsafeDecode(bytes, 10);
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
        frames.add(Uint8List.fromList(bytes.sublist(pos, pos + 10 + frameSize)));
      }
      pos += 10 + frameSize;
    }
    frames.add(apic);
    return _buildId3Tag(frames, audioData);
  }

  static Uint8List _prependId3(Uint8List audioData, Uint8List apic) {
    return _buildId3Tag([apic], audioData);
  }

  static Uint8List _buildId3Tag(List<Uint8List> frames, Uint8List audioData) {
    final framesSize = frames.fold(0, (s, f) => s + f.length);
    final tag = Uint8List(10 + framesSize);
    // ID3v2.3 header
    tag[0] = 0x49; tag[1] = 0x44; tag[2] = 0x33; // "ID3"
    tag[3] = 0x03; tag[4] = 0x00; // version 2.3.0
    tag[5] = 0x00; // flags
    _syncsafeEncode(framesSize, tag, 6);
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

  static int _syncsafeDecode(Uint8List b, int offset) =>
      (b[offset] << 21) | (b[offset + 1] << 14) |
      (b[offset + 2] << 7) | b[offset + 3];

  static void _syncsafeEncode(int value, Uint8List b, int offset) {
    b[offset + 3] = value & 0x7F; value >>= 7;
    b[offset + 2] = value & 0x7F; value >>= 7;
    b[offset + 1] = value & 0x7F; value >>= 7;
    b[offset]     = value & 0x7F;
  }

  // ── MP3 metadata writing ──────────────────────────────────────────────────

  static Future<void> _writeMetadataMp3(String filePath, Audiobook book) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();

    final newFrames = <Uint8List>[];
    if (book.title.isNotEmpty) newFrames.add(_buildId3TextField('TIT2', book.title));
    if (book.author != null) newFrames.add(_buildId3TextField('TPE1', book.author!));
    if (book.narrator != null) newFrames.add(_buildId3TextField('TPE2', book.narrator!));
    if (book.releaseDate != null) newFrames.add(_buildId3TextField('TYER', book.releaseDate!));

    Uint8List result;
    if (bytes.length >= 3 &&
        bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) {
      result = _rewriteId3WithFrames(bytes, newFrames,
          stripIds: {'TIT2', 'TPE1', 'TPE2', 'TYER'});
    } else {
      result = _prependId3(bytes, _mergeFrames(newFrames));
    }
    await file.writeAsBytes(result);
  }

  static Uint8List _buildId3TextField(String id, String value) {
    final encoded = Uint8List.fromList([0x00, ...value.codeUnits]); // UTF-8 flag + text
    final frame = Uint8List(10 + encoded.length);
    for (int i = 0; i < 4; i++) { frame[i] = id.codeUnitAt(i); }
    final sz = encoded.length;
    frame[4] = (sz >> 24) & 0xFF;
    frame[5] = (sz >> 16) & 0xFF;
    frame[6] = (sz >> 8) & 0xFF;
    frame[7] = sz & 0xFF;
    frame[8] = 0x00; frame[9] = 0x00;
    frame.setRange(10, frame.length, encoded);
    return frame;
  }

  static Uint8List _rewriteId3WithFrames(
      Uint8List bytes, List<Uint8List> newFrames, {required Set<String> stripIds}) {
    final tagSize = _syncsafeDecode(bytes, 6);
    final tagEnd = 10 + tagSize;
    final audioData = bytes.sublist(tagEnd);
    final frames = <Uint8List>[];
    int pos = 10;
    if (bytes[5] & 0x40 != 0) {
      final extSize = _syncsafeDecode(bytes, 10);
      pos += 4 + extSize;
    }
    while (pos + 10 <= tagEnd) {
      final frameId = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      if (frameId == '\x00\x00\x00\x00') break;
      final frameSize = (bytes[pos + 4] << 24) | (bytes[pos + 5] << 16) |
          (bytes[pos + 6] << 8) | bytes[pos + 7];
      if (frameSize <= 0 || pos + 10 + frameSize > tagEnd) break;
      if (!stripIds.contains(frameId) && frameId != 'APIC') {
        frames.add(Uint8List.fromList(bytes.sublist(pos, pos + 10 + frameSize)));
      } else if (frameId == 'APIC') {
        frames.add(Uint8List.fromList(bytes.sublist(pos, pos + 10 + frameSize)));
      }
      pos += 10 + frameSize;
    }
    frames.addAll(newFrames);
    return _buildId3Tag(frames, audioData);
  }

  static Uint8List _mergeFrames(List<Uint8List> frames) {
    final total = frames.fold(0, (s, f) => s + f.length);
    final out = Uint8List(total);
    int off = 0;
    for (final f in frames) { out.setRange(off, off + f.length, f); off += f.length; }
    return out;
  }

  // ── MP4 metadata writing ──────────────────────────────────────────────────

  static Future<void> _writeMetadataMp4(String filePath, Audiobook book) async {
    final bytes = await File(filePath).readAsBytes();
    final result = _rewriteMp4Metadata(bytes, book);
    await File(filePath).writeAsBytes(result);
  }

  static Uint8List _rewriteMp4Metadata(Uint8List bytes, Audiobook book) {
    final moovIdx = _findBox(bytes, 0, bytes.length, 'moov');
    if (moovIdx == null) return bytes;

    final moovStart = moovIdx.$1;
    final moovEnd = moovIdx.$2;
    final moovContent = bytes.sublist(moovStart + 8, moovEnd);
    final newMoovContent = _injectTextAtomsInMoov(moovContent, book);
    final newMoovSize = 8 + newMoovContent.length;
    final newMoov = Uint8List(newMoovSize);
    _writeUint32BE(newMoov, 0, newMoovSize);
    newMoov[4] = 0x6D; newMoov[5] = 0x6F; newMoov[6] = 0x6F; newMoov[7] = 0x76;
    newMoov.setRange(8, newMoovSize, newMoovContent);

    final result = Uint8List(bytes.length - (moovEnd - moovStart) + newMoovSize);
    result.setRange(0, moovStart, bytes.sublist(0, moovStart));
    result.setRange(moovStart, moovStart + newMoovSize, newMoov);
    result.setRange(moovStart + newMoovSize, result.length, bytes.sublist(moovEnd));

    final mdatIdx = _findBox(result, 0, result.length, 'mdat');
    if (mdatIdx != null && moovStart < mdatIdx.$1) {
      final delta = newMoovSize - (moovEnd - moovStart);
      if (delta != 0) _adjustChunkOffsets(result, delta);
    }
    return result;
  }

  static Uint8List _injectTextAtomsInMoov(Uint8List moov, Audiobook book) {
    // Build ilst atoms for each text field
    final atoms = <Uint8List>[];
    if (book.title.isNotEmpty) atoms.add(_buildMp4TextAtom('\u00a9nam', book.title));
    if (book.author != null) atoms.add(_buildMp4TextAtom('\u00a9ART', book.author!));
    if (book.narrator != null) atoms.add(_buildMp4TextAtom('\u00a9wrt', book.narrator!));
    if (book.releaseDate != null) atoms.add(_buildMp4TextAtom('\u00a9day', book.releaseDate!));
    if (atoms.isEmpty) return moov;

    final udtaIdx = _findBox(moov, 0, moov.length, 'udta');
    if (udtaIdx == null) {
      // Build udta > meta > ilst from scratch, preserving any existing covr
      final ilstContent = Uint8List.fromList(atoms.expand((a) => a).toList());
      final ilst = _wrapBox('ilst', ilstContent);
      final metaPayload = Uint8List(4 + ilst.length);
      metaPayload.setRange(4, metaPayload.length, ilst);
      final meta = _wrapBox('meta', metaPayload);
      final udta = _wrapBox('udta', meta);
      final result = Uint8List(moov.length + udta.length);
      result.setRange(0, moov.length, moov);
      result.setRange(moov.length, result.length, udta);
      return result;
    }

    final udtaStart = udtaIdx.$1;
    final udtaEnd = udtaIdx.$2;
    final udtaContent = moov.sublist(udtaStart + 8, udtaEnd);
    final newUdtaContent = _injectTextAtomsInUdta(udtaContent, atoms);
    final newUdta = _wrapBox('udta', newUdtaContent);

    final result = Uint8List(moov.length - (udtaEnd - udtaStart) + newUdta.length);
    result.setRange(0, udtaStart, moov.sublist(0, udtaStart));
    result.setRange(udtaStart, udtaStart + newUdta.length, newUdta);
    result.setRange(udtaStart + newUdta.length, result.length, moov.sublist(udtaEnd));
    return result;
  }

  static Uint8List _injectTextAtomsInUdta(
      Uint8List udta, List<Uint8List> atoms) {
    final metaIdx = _findBox(udta, 0, udta.length, 'meta');
    if (metaIdx == null) {
      final ilstContent = Uint8List.fromList(atoms.expand((a) => a).toList());
      final ilst = _wrapBox('ilst', ilstContent);
      final metaPayload = Uint8List(4 + ilst.length);
      metaPayload.setRange(4, metaPayload.length, ilst);
      final meta = _wrapBox('meta', metaPayload);
      final result = Uint8List(udta.length + meta.length);
      result.setRange(0, udta.length, udta);
      result.setRange(udta.length, result.length, meta);
      return result;
    }

    final metaStart = metaIdx.$1;
    final metaEnd = metaIdx.$2;
    final metaInner = udta.sublist(metaStart + 8, metaEnd);
    final metaFlags = metaInner.sublist(0, 4);
    final metaContent = metaInner.sublist(4);
    final newMetaContent = _injectTextAtomsInMeta(metaContent, atoms);
    final newMetaPayload = Uint8List(4 + newMetaContent.length);
    newMetaPayload.setRange(0, 4, metaFlags);
    newMetaPayload.setRange(4, newMetaPayload.length, newMetaContent);
    final newMeta = _wrapBox('meta', newMetaPayload);

    final result = Uint8List(udta.length - (metaEnd - metaStart) + newMeta.length);
    result.setRange(0, metaStart, udta.sublist(0, metaStart));
    result.setRange(metaStart, metaStart + newMeta.length, newMeta);
    result.setRange(metaStart + newMeta.length, result.length, udta.sublist(metaEnd));
    return result;
  }

  static Uint8List _injectTextAtomsInMeta(
      Uint8List meta, List<Uint8List> atoms) {
    final ilstIdx = _findBox(meta, 0, meta.length, 'ilst');
    if (ilstIdx == null) {
      final ilstContent = Uint8List.fromList(atoms.expand((a) => a).toList());
      final ilst = _wrapBox('ilst', ilstContent);
      final result = Uint8List(meta.length + ilst.length);
      result.setRange(0, meta.length, meta);
      result.setRange(meta.length, result.length, ilst);
      return result;
    }

    final ilstStart = ilstIdx.$1;
    final ilstEnd = ilstIdx.$2;
    final ilstContent = meta.sublist(ilstStart + 8, ilstEnd);
    final newIlstContent = _injectTextAtomsInIlst(ilstContent, atoms);
    final newIlst = _wrapBox('ilst', newIlstContent);

    final result = Uint8List(meta.length - (ilstEnd - ilstStart) + newIlst.length);
    result.setRange(0, ilstStart, meta.sublist(0, ilstStart));
    result.setRange(ilstStart, ilstStart + newIlst.length, newIlst);
    result.setRange(ilstStart + newIlst.length, result.length, meta.sublist(ilstEnd));
    return result;
  }

  static Uint8List _injectTextAtomsInIlst(
      Uint8List ilst, List<Uint8List> atoms) {
    // Collect the 4-char keys we're replacing
    final replaceKeys = atoms.map((a) => String.fromCharCodes(a.sublist(4, 8))).toSet();
    final kept = <int>[];
    int pos = 0;
    while (pos + 8 <= ilst.length) {
      final sz = _readUint32BE(ilst, pos);
      if (sz < 8 || pos + sz > ilst.length) break;
      final type = String.fromCharCodes(ilst.sublist(pos + 4, pos + 8));
      if (!replaceKeys.contains(type)) {
        kept.addAll(ilst.sublist(pos, pos + sz));
      }
      pos += sz;
    }
    kept.addAll(atoms.expand((a) => a));
    return Uint8List.fromList(kept);
  }

  static Uint8List _buildMp4TextAtom(String key, String value) {
    // atom: key > data(flags=1, locale=0, utf8 text)
    final textBytes = Uint8List.fromList(value.codeUnits);
    final dataPayload = Uint8List(8 + textBytes.length);
    dataPayload[0] = 0x00; dataPayload[1] = 0x00;
    dataPayload[2] = 0x00; dataPayload[3] = 0x01; // flags = UTF-8
    // locale bytes 4-7 = 0
    dataPayload.setRange(8, dataPayload.length, textBytes);
    final dataAtom = _wrapBox('data', dataPayload);
    return _wrapBox(key, dataAtom);
  }

  // ── FLAC cover embedding ──────────────────────────────────────────────────
  //
  // FLAC metadata lives in a sequence of METADATA_BLOCKs before the audio
  // frames. Each block: 1-byte header (last-flag + type) + 3-byte length +
  // data. We strip any existing PICTURE blocks (type 6) and inject a new one.

  static Future<void> _embedCoverFlac(String filePath, Uint8List jpeg) async {
    final bytes = await File(filePath).readAsBytes();
    if (bytes.length < 4 || bytes[0] != 0x66 || bytes[1] != 0x4C ||
        bytes[2] != 0x61 || bytes[3] != 0x43) {
      return; // not a valid FLAC file
    }

    final picture = _buildFlacPictureBlock(jpeg);
    final result = _rewriteFlacMetadata(bytes, picture);
    await File(filePath).writeAsBytes(result);
  }

  static Uint8List _buildFlacPictureBlock(Uint8List jpeg) {
    // PICTURE block data layout (all big-endian):
    // picture_type(4) + mime_len(4) + mime(n) + desc_len(4) + desc(0)
    // + width(4) + height(4) + color_depth(4) + color_count(4)
    // + data_len(4) + data(n)
    const mime = 'image/jpeg';
    final mimeBytes = Uint8List.fromList(mime.codeUnits);
    final data = Uint8List(4 + 4 + mimeBytes.length + 4 + 4 * 5 + jpeg.length);
    int off = 0;
    // picture type 3 = cover (front)
    _writeUint32BE(data, off, 3); off += 4;
    _writeUint32BE(data, off, mimeBytes.length); off += 4;
    data.setRange(off, off + mimeBytes.length, mimeBytes); off += mimeBytes.length;
    _writeUint32BE(data, off, 0); off += 4; // description length = 0
    _writeUint32BE(data, off, 0); off += 4; // width (0 = unknown)
    _writeUint32BE(data, off, 0); off += 4; // height
    _writeUint32BE(data, off, 0); off += 4; // color depth
    _writeUint32BE(data, off, 0); off += 4; // color count
    _writeUint32BE(data, off, jpeg.length); off += 4;
    data.setRange(off, off + jpeg.length, jpeg);
    return data;
  }

  static Uint8List _rewriteFlacMetadata(Uint8List bytes, Uint8List pictureData) {
    // Collect existing metadata blocks, skipping PICTURE (type 6)
    final blocks = <(int, Uint8List)>[]; // (type, data)
    int pos = 4; // skip 'fLaC' marker
    bool isLast = false;
    while (!isLast && pos + 4 <= bytes.length) {
      final header = bytes[pos];
      isLast = (header & 0x80) != 0;
      final type = header & 0x7F;
      final len = (bytes[pos + 1] << 16) | (bytes[pos + 2] << 8) | bytes[pos + 3];
      pos += 4;
      if (pos + len > bytes.length) break;
      if (type != 6) { // skip existing PICTURE blocks
        blocks.add((type, Uint8List.fromList(bytes.sublist(pos, pos + len))));
      }
      pos += len;
    }
    final audioData = bytes.sublist(pos);

    // Rebuild: fLaC marker + all kept blocks + new PICTURE block + audio
    final out = BytesBuilder();
    out.add([0x66, 0x4C, 0x61, 0x43]); // fLaC
    for (int i = 0; i < blocks.length; i++) {
      final (type, data) = blocks[i];
      final hdr = Uint8List(4);
      hdr[0] = type & 0x7F; // not last
      hdr[1] = (data.length >> 16) & 0xFF;
      hdr[2] = (data.length >> 8) & 0xFF;
      hdr[3] = data.length & 0xFF;
      out.add(hdr);
      out.add(data);
    }
    // PICTURE block — mark as last
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

  // ── OGG Vorbis cover embedding ────────────────────────────────────────────
  //
  // OGG files store metadata in the Vorbis comment header packet (packet 2
  // in the first logical bitstream). We locate it by walking Ogg pages,
  // strip any existing METADATA_BLOCK_PICTURE comment, inject a new one,
  // then repack the page with a corrected CRC.

  static Future<void> _embedCoverOgg(String filePath, Uint8List jpeg) async {
    final bytes = await File(filePath).readAsBytes();
    final result = _rewriteOggCover(bytes, jpeg);
    if (result != null) await File(filePath).writeAsBytes(result);
  }

  static Uint8List? _rewriteOggCover(Uint8List bytes, Uint8List jpeg) {
    // Build the base64-encoded METADATA_BLOCK_PICTURE for Vorbis
    final pictureData = _buildFlacPictureBlock(jpeg);
    final b64 = _base64Encode(pictureData);
    final newComment =
        'METADATA_BLOCK_PICTURE=${String.fromCharCodes(b64)}';

    // Walk Ogg pages to find the Vorbis comment header (packet type 0x03)
    int pos = 0;
    while (pos + 27 <= bytes.length) {
      // Ogg page header: capture_pattern(4) + version(1) + header_type(1)
      // + granule(8) + serial(4) + seq(4) + checksum(4) + segments(1)
      if (bytes[pos] != 0x4F || bytes[pos+1] != 0x67 ||
          bytes[pos+2] != 0x67 || bytes[pos+3] != 0x53) {
        return null; // not an Ogg page
      }
      final numSegs = bytes[pos + 26];
      if (pos + 27 + numSegs > bytes.length) return null;
      final segTable = bytes.sublist(pos + 27, pos + 27 + numSegs);
      final pageDataLen = segTable.fold(0, (s, v) => s + v);
      final pageStart = pos + 27 + numSegs;
      if (pageStart + pageDataLen > bytes.length) return null;
      final pageData = bytes.sublist(pageStart, pageStart + pageDataLen);
      final pageEnd = pageStart + pageDataLen;

      // Check if this page starts a Vorbis comment packet (0x03 + 'vorbis')
      if (pageData.length >= 7 &&
          pageData[0] == 0x03 &&
          pageData[1] == 0x76 && pageData[2] == 0x6F && pageData[3] == 0x72 &&
          pageData[4] == 0x62 && pageData[5] == 0x69 && pageData[6] == 0x73) {
        final newPageData =
            _rewriteVorbisCommentPacket(pageData, newComment);
        if (newPageData == null) return null;

        // Rebuild the page with the new data and corrected CRC
        final newPage =
            _rebuildOggPage(bytes, pos, segTable, newPageData);

        final result = Uint8List(
            bytes.length - (pageEnd - pos) + newPage.length);
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

  static Uint8List? _rewriteVorbisCommentPacket(
      Uint8List packet, String newComment) {
    // Vorbis comment packet layout:
    // type(1) + 'vorbis'(6) + vendor_len(4LE) + vendor(n)
    // + comment_count(4LE) + [comment_len(4LE) + comment(n)] * count
    // + framing_bit(1)
    if (packet.length < 11) return null;
    int off = 7; // skip type + 'vorbis'
    if (off + 4 > packet.length) return null;
    final vendorLen = _readUint32LE(packet, off); off += 4;
    if (off + vendorLen > packet.length) return null;
    final vendor = packet.sublist(off, off + vendorLen); off += vendorLen;
    if (off + 4 > packet.length) return null;
    final commentCount = _readUint32LE(packet, off); off += 4;

    // Collect existing comments, stripping METADATA_BLOCK_PICTURE
    final comments = <Uint8List>[];
    for (int i = 0; i < commentCount; i++) {
      if (off + 4 > packet.length) return null;
      final len = _readUint32LE(packet, off); off += 4;
      if (off + len > packet.length) return null;
      final comment = packet.sublist(off, off + len); off += len;
      final str = String.fromCharCodes(comment).toUpperCase();
      if (!str.startsWith('METADATA_BLOCK_PICTURE=')) {
        comments.add(comment);
      }
    }

    // Append new METADATA_BLOCK_PICTURE comment
    comments.add(Uint8List.fromList(newComment.codeUnits));

    // Rebuild packet
    final out = BytesBuilder();
    out.add(packet.sublist(0, 7)); // type + 'vorbis'
    final vl = Uint8List(4);
    _writeUint32LE(vl, 0, vendorLen);
    out.add(vl);
    out.add(vendor);
    final cl = Uint8List(4);
    _writeUint32LE(cl, 0, comments.length);
    out.add(cl);
    for (final c in comments) {
      final ll = Uint8List(4);
      _writeUint32LE(ll, 0, c.length);
      out.add(ll);
      out.add(c);
    }
    out.addByte(0x01); // framing bit
    return out.toBytes();
  }

  static Uint8List _rebuildOggPage(Uint8List original, int pagePos,
      Uint8List oldSegTable, Uint8List newPacket) {
    // Build new segment table for newPacket
    final newSegs = <int>[];
    int remaining = newPacket.length;
    while (remaining >= 255) {
      newSegs.add(255);
      remaining -= 255;
    }
    newSegs.add(remaining);

    final headerSize = 27 + newSegs.length;
    final page = Uint8List(headerSize + newPacket.length);
    // Copy fixed header fields from original (capture, version, header_type,
    // granule, serial, seq) — bytes 0..22
    page.setRange(0, 23, original.sublist(pagePos, pagePos + 23));
    // Zero checksum (bytes 22-25)
    page[22] = 0; page[23] = 0; page[24] = 0; page[25] = 0;
    page[26] = newSegs.length;
    page.setRange(27, 27 + newSegs.length, newSegs);
    page.setRange(headerSize, headerSize + newPacket.length, newPacket);

    // Compute and write CRC-32 (Ogg variant)
    final crc = _oggCrc32(page);
    page[22] = crc & 0xFF;
    page[23] = (crc >> 8) & 0xFF;
    page[24] = (crc >> 16) & 0xFF;
    page[25] = (crc >> 24) & 0xFF;
    return page;
  }

  // Ogg CRC-32 table (polynomial 0x04C11DB7, no reflection)
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
      crc = ((crc << 8) ^ _oggCrcTable[((crc >> 24) ^ b) & 0xFF]) & 0xFFFFFFFF;
    }
    return crc;
  }

  static int _readUint32LE(Uint8List b, int offset) =>
      b[offset] | (b[offset+1] << 8) | (b[offset+2] << 16) | (b[offset+3] << 24);

  static void _writeUint32LE(Uint8List b, int offset, int value) {
    b[offset]     = value & 0xFF;
    b[offset + 1] = (value >> 8) & 0xFF;
    b[offset + 2] = (value >> 16) & 0xFF;
    b[offset + 3] = (value >> 24) & 0xFF;
  }

  static Uint8List _base64Encode(Uint8List data) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    final out = <int>[];
    for (int i = 0; i < data.length; i += 3) {
      final b0 = data[i];
      final b1 = i + 1 < data.length ? data[i + 1] : 0;
      final b2 = i + 2 < data.length ? data[i + 2] : 0;
      out.add(chars.codeUnitAt((b0 >> 2) & 0x3F));
      out.add(chars.codeUnitAt(((b0 << 4) | (b1 >> 4)) & 0x3F));
      out.add(i + 1 < data.length
          ? chars.codeUnitAt(((b1 << 2) | (b2 >> 6)) & 0x3F)
          : 0x3D); // '='
      out.add(i + 2 < data.length
          ? chars.codeUnitAt(b2 & 0x3F)
          : 0x3D); // '='
    }
    return Uint8List.fromList(out);
  }

  // ── MP4 cover embedding ───────────────────────────────────────────────────
  //
  // Strategy: locate moov > udta > meta > ilst, replace or insert a `covr`
  // atom. Rebuild the affected boxes bottom-up and patch sizes.
  // Uses in-place rewrite via RandomAccessFile where possible; falls back to
  // full file rewrite.

  static Future<void> _embedCoverMp4(String filePath, Uint8List jpeg) async {
    final bytes = await File(filePath).readAsBytes();
    final result = _rewriteMp4Cover(bytes, jpeg);
    await File(filePath).writeAsBytes(result);
  }

  static Uint8List _rewriteMp4Cover(Uint8List bytes, Uint8List jpeg) {
    // Build the new covr atom
    final covrData = _buildCovrAtom(jpeg);

    // Find moov box
    final moovIdx = _findBox(bytes, 0, bytes.length, 'moov');
    if (moovIdx == null) return bytes; // can't find moov, leave unchanged

    final moovStart = moovIdx.$1;
    final moovEnd = moovIdx.$2;
    final moovContent = bytes.sublist(moovStart + 8, moovEnd);

    // Find or create udta > meta > ilst inside moov
    final newMoovContent = _injectCovrInMoov(moovContent, covrData);
    final newMoovSize = 8 + newMoovContent.length;
    final newMoov = Uint8List(newMoovSize);
    _writeUint32BE(newMoov, 0, newMoovSize);
    newMoov[4] = 0x6D; newMoov[5] = 0x6F; newMoov[6] = 0x6F; newMoov[7] = 0x76; // moov
    newMoov.setRange(8, newMoovSize, newMoovContent);

    // Reassemble: everything before moov + new moov + everything after moov
    final result = Uint8List(bytes.length - (moovEnd - moovStart) + newMoovSize);
    result.setRange(0, moovStart, bytes.sublist(0, moovStart));
    result.setRange(moovStart, moovStart + newMoovSize, newMoov);
    result.setRange(moovStart + newMoovSize, result.length, bytes.sublist(moovEnd));

    // Fix stco/co64 chunk offsets if moov was before mdat
    final mdatIdx = _findBox(result, 0, result.length, 'mdat');
    if (mdatIdx != null && moovStart < mdatIdx.$1) {
      final delta = newMoovSize - (moovEnd - moovStart);
      if (delta != 0) _adjustChunkOffsets(result, delta);
    }

    return result;
  }

  static Uint8List _injectCovrInMoov(Uint8List moov, Uint8List covrData) {
    // Try to find udta
    final udtaIdx = _findBox(moov, 0, moov.length, 'udta');
    if (udtaIdx == null) {
      // No udta — append one containing meta > ilst > covr
      final ilst = _wrapBox('ilst', covrData);
      // meta needs a 4-byte version/flags prefix before its children
      final metaPayload = Uint8List(4 + ilst.length);
      metaPayload.setRange(4, metaPayload.length, ilst);
      final meta = _wrapBox('meta', metaPayload);
      final udta = _wrapBox('udta', meta);
      final result = Uint8List(moov.length + udta.length);
      result.setRange(0, moov.length, moov);
      result.setRange(moov.length, result.length, udta);
      return result;
    }

    final udtaStart = udtaIdx.$1;
    final udtaEnd = udtaIdx.$2;
    final udtaContent = moov.sublist(udtaStart + 8, udtaEnd);
    final newUdtaContent = _injectCovrInUdta(udtaContent, covrData);
    final newUdta = _wrapBox('udta', newUdtaContent);

    final result = Uint8List(moov.length - (udtaEnd - udtaStart) + newUdta.length);
    result.setRange(0, udtaStart, moov.sublist(0, udtaStart));
    result.setRange(udtaStart, udtaStart + newUdta.length, newUdta);
    result.setRange(udtaStart + newUdta.length, result.length, moov.sublist(udtaEnd));
    return result;
  }

  static Uint8List _injectCovrInUdta(Uint8List udta, Uint8List covrData) {
    final metaIdx = _findBox(udta, 0, udta.length, 'meta');
    if (metaIdx == null) {
      final ilst = _wrapBox('ilst', covrData);
      final metaPayload = Uint8List(4 + ilst.length);
      metaPayload.setRange(4, metaPayload.length, ilst);
      final meta = _wrapBox('meta', metaPayload);
      final result = Uint8List(udta.length + meta.length);
      result.setRange(0, udta.length, udta);
      result.setRange(udta.length, result.length, meta);
      return result;
    }

    final metaStart = metaIdx.$1;
    final metaEnd = metaIdx.$2;
    // meta has a 4-byte version/flags prefix before its children
    final metaInner = udta.sublist(metaStart + 8, metaEnd);
    final metaFlags = metaInner.sublist(0, 4);
    final metaContent = metaInner.sublist(4);
    final newMetaContent = _injectCovrInMeta(metaContent, covrData);
    final newMetaPayload = Uint8List(4 + newMetaContent.length);
    newMetaPayload.setRange(0, 4, metaFlags);
    newMetaPayload.setRange(4, newMetaPayload.length, newMetaContent);
    final newMeta = _wrapBox('meta', newMetaPayload);

    final result = Uint8List(udta.length - (metaEnd - metaStart) + newMeta.length);
    result.setRange(0, metaStart, udta.sublist(0, metaStart));
    result.setRange(metaStart, metaStart + newMeta.length, newMeta);
    result.setRange(metaStart + newMeta.length, result.length, udta.sublist(metaEnd));
    return result;
  }

  static Uint8List _injectCovrInMeta(Uint8List meta, Uint8List covrData) {
    final ilstIdx = _findBox(meta, 0, meta.length, 'ilst');
    if (ilstIdx == null) {
      final ilst = _wrapBox('ilst', covrData);
      final result = Uint8List(meta.length + ilst.length);
      result.setRange(0, meta.length, meta);
      result.setRange(meta.length, result.length, ilst);
      return result;
    }

    final ilstStart = ilstIdx.$1;
    final ilstEnd = ilstIdx.$2;
    final ilstContent = meta.sublist(ilstStart + 8, ilstEnd);
    final newIlstContent = _injectCovrInIlst(ilstContent, covrData);
    final newIlst = _wrapBox('ilst', newIlstContent);

    final result = Uint8List(meta.length - (ilstEnd - ilstStart) + newIlst.length);
    result.setRange(0, ilstStart, meta.sublist(0, ilstStart));
    result.setRange(ilstStart, ilstStart + newIlst.length, newIlst);
    result.setRange(ilstStart + newIlst.length, result.length, meta.sublist(ilstEnd));
    return result;
  }

  static Uint8List _injectCovrInIlst(Uint8List ilst, Uint8List covrData) {
    // Remove existing covr atom if present, then append new one
    final result = <int>[];
    int pos = 0;
    while (pos + 8 <= ilst.length) {
      final sz = _readUint32BE(ilst, pos);
      if (sz < 8 || pos + sz > ilst.length) break;
      final type = String.fromCharCodes(ilst.sublist(pos + 4, pos + 8));
      if (type != 'covr') {
        result.addAll(ilst.sublist(pos, pos + sz));
      }
      pos += sz;
    }
    result.addAll(covrData);
    return Uint8List.fromList(result);
  }

  static Uint8List _buildCovrAtom(Uint8List jpeg) {
    // covr > data atom: version(1) + flags(3=JPEG) + locale(4) + jpeg
    const flags = 0x0D; // JPEG
    final dataPayload = Uint8List(8 + jpeg.length);
    dataPayload[0] = 0x00;
    dataPayload[1] = 0x00;
    dataPayload[2] = 0x00;
    dataPayload[3] = flags;
    // locale = 0x00000000
    dataPayload.setRange(8, dataPayload.length, jpeg);
    final dataAtom = _wrapBox('data', dataPayload);
    return _wrapBox('covr', dataAtom);
  }

  static void _adjustChunkOffsets(Uint8List bytes, int delta) {
    // Walk all trak > mdia > minf > stbl boxes and adjust stco/co64
    _walkBoxes(bytes, 0, bytes.length, (type, start, end) {
      if (type == 'stco') {
        final count = _readUint32BE(bytes, start + 8 + 4);
        for (int i = 0; i < count; i++) {
          final off = start + 8 + 8 + i * 4;
          final val = _readUint32BE(bytes, off);
          _writeUint32BE(bytes, off, val + delta);
        }
      } else if (type == 'co64') {
        final count = _readUint32BE(bytes, start + 8 + 4);
        for (int i = 0; i < count; i++) {
          final off = start + 8 + 8 + i * 8;
          final hi = _readUint32BE(bytes, off);
          final lo = _readUint32BE(bytes, off + 4);
          final val = (hi << 32) | lo;
          final newVal = val + delta;
          _writeUint32BE(bytes, off, (newVal >> 32) & 0xFFFFFFFF);
          _writeUint32BE(bytes, off + 4, newVal & 0xFFFFFFFF);
        }
      }
    });
  }

  static void _walkBoxes(Uint8List bytes, int start, int end,
      void Function(String type, int boxStart, int boxEnd) visitor) {
    int pos = start;
    while (pos + 8 <= end) {
      final sz = _readUint32BE(bytes, pos);
      if (sz < 8 || pos + sz > end) break;
      final type = String.fromCharCodes(bytes.sublist(pos + 4, pos + 8));
      visitor(type, pos, pos + sz);
      if ({'moov', 'trak', 'mdia', 'minf', 'stbl', 'udta'}.contains(type)) {
        _walkBoxes(bytes, pos + 8, pos + sz, visitor);
      }
      pos += sz;
    }
  }

  // ── Box utilities ─────────────────────────────────────────────────────────

  static (int, int)? _findBox(Uint8List bytes, int start, int end, String type) {
    int pos = start;
    while (pos + 8 <= end) {
      final sz = _readUint32BE(bytes, pos);
      if (sz < 8 || pos + sz > end) break;
      final t = String.fromCharCodes(bytes.sublist(pos + 4, pos + 8));
      if (t == type) return (pos, pos + sz);
      pos += sz;
    }
    return null;
  }

  static Uint8List _wrapBox(String type, Uint8List content) {
    final box = Uint8List(8 + content.length);
    _writeUint32BE(box, 0, box.length);
    for (int i = 0; i < 4; i++) { box[4 + i] = type.codeUnitAt(i); }
    box.setRange(8, box.length, content);
    return box;
  }

  static int _readUint32BE(Uint8List b, int offset) =>
      (b[offset] << 24) | (b[offset + 1] << 16) |
      (b[offset + 2] << 8) | b[offset + 3];

  static void _writeUint32BE(Uint8List b, int offset, int value) {
    b[offset]     = (value >> 24) & 0xFF;
    b[offset + 1] = (value >> 16) & 0xFF;
    b[offset + 2] = (value >> 8) & 0xFF;
    b[offset + 3] = value & 0xFF;
  }

  // ── OPF export ────────────────────────────────────────────────────────────

  static Future<void> exportMetadata(Audiobook book) async {
    await exportOpf(book);
    await exportCover(book);
  }

  static Future<void> exportCover(Audiobook book) async {
    final coverOut = File(p.join(book.path, 'cover.jpg'));
    if (book.coverImageBytes != null) {
      final jpeg = await toJpeg(book.coverImageBytes!);
      await coverOut.writeAsBytes(jpeg);
    } else if (book.coverImagePath != null) {
      final bytes = await File(book.coverImagePath!).readAsBytes();
      final jpeg = await toJpeg(bytes);
      await coverOut.writeAsBytes(jpeg);
    }
  }

  static Future<void> exportOpf(Audiobook book) async {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="utf-8"?>');
    buf.writeln('<package xmlns="http://www.idpf.org/2007/opf" version="2.0" '
        'unique-identifier="uid">');
    buf.writeln('  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:opf="http://www.idpf.org/2007/opf">');
    buf.writeln('    <dc:title>${_xmlEscape(book.title)}</dc:title>');
    if (book.author != null) {
      buf.writeln('    <dc:creator opf:role="aut">'
          '${_xmlEscape(book.author!)}</dc:creator>');
    }
    if (book.narrator != null) {
      buf.writeln('    <dc:creator opf:role="nrt">'
          '${_xmlEscape(book.narrator!)}</dc:creator>');
    }
    if (book.description != null) {
      buf.writeln('    <dc:description>'
          '${_xmlEscape(book.description!)}</dc:description>');
    }
    if (book.publisher != null) {
      buf.writeln('    <dc:publisher>'
          '${_xmlEscape(book.publisher!)}</dc:publisher>');
    }
    if (book.language != null) {
      buf.writeln('    <dc:language>${_xmlEscape(book.language!)}</dc:language>');
    }
    if (book.releaseDate != null) {
      buf.writeln('    <dc:date>${_xmlEscape(book.releaseDate!)}</dc:date>');
    }
    if (book.series != null) {
      buf.writeln('    <meta name="calibre:series" '
          'content="${_xmlEscape(book.series!)}"/>');
    }
    if (book.seriesIndex != null) {
      buf.writeln('    <meta name="calibre:series_index" '
          'content="${book.seriesIndex}"/>');
    }
    buf.writeln('  </metadata>');
    buf.writeln('</package>');

    final outFile = File(p.join(book.path, 'metadata.opf'));
    await outFile.writeAsString(buf.toString());
  }

  static String _xmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
