import 'dart:io';
import 'dart:typed_data';
import 'package:audiovault_editor/models/audiobook.dart';

class Mp4Writer {
  const Mp4Writer._();

  static Future<void> writeMetadata(String filePath, Audiobook book) async {
    final bytes = await File(filePath).readAsBytes();
    final result = _rewriteMetadata(bytes, book);
    await File(filePath).writeAsBytes(result);
  }

  static Future<void> embedCover(String filePath, Uint8List jpeg) async {
    final bytes = await File(filePath).readAsBytes();
    final result = _rewriteCover(bytes, jpeg);
    await File(filePath).writeAsBytes(result);
  }

  // ── Metadata rewrite ──────────────────────────────────────────────────────

  static Uint8List _rewriteMetadata(Uint8List bytes, Audiobook book) {
    final moovIdx = _findBox(bytes, 0, bytes.length, 'moov');
    if (moovIdx == null) return bytes;

    final moovStart = moovIdx.$1;
    final moovEnd = moovIdx.$2;
    final moovContent = bytes.sublist(moovStart + 8, moovEnd);
    final newMoovContent = _injectTextAtomsInMoov(moovContent, book);
    final newMoov = _wrapBox('moov', newMoovContent);

    final result = _spliceBytes(bytes, moovStart, moovEnd, newMoov);
    final mdatIdx = _findBox(result, 0, result.length, 'mdat');
    if (mdatIdx != null && moovStart < mdatIdx.$1) {
      final delta = newMoov.length - (moovEnd - moovStart);
      if (delta != 0) _adjustChunkOffsets(result, delta);
    }
    return result;
  }

  static Uint8List _injectTextAtomsInMoov(Uint8List moov, Audiobook book) {
    final atoms = <Uint8List>[
      if (book.title != null && book.title!.isNotEmpty)
        _buildTextAtom('\u00a9alb', book.title!),
      if (book.subtitle != null) _buildTextAtom('\u00a9nam', book.subtitle!),
      if (book.author != null) _buildTextAtom('\u00a9ART', book.author!),
      if (book.narrator != null) _buildTextAtom('\u00a9wrt', book.narrator!),
      if (book.releaseDate != null)
        _buildTextAtom('\u00a9day', book.releaseDate!),
      if (book.description != null)
        _buildTextAtom('\u00a9cmt', book.description!),
      if (book.publisher != null) _buildTextAtom('\u00a9pub', book.publisher!),
      if (book.language != null) _buildTextAtom('\u00a9lan', book.language!),
      if (book.genre != null) _buildTextAtom('\u00a9gen', book.genre!),
    ];
    if (atoms.isEmpty) return moov;
    return _injectIlstAtoms(moov, atoms);
  }

  // ── Cover rewrite ─────────────────────────────────────────────────────────

  static Uint8List _rewriteCover(Uint8List bytes, Uint8List jpeg) {
    final moovIdx = _findBox(bytes, 0, bytes.length, 'moov');
    if (moovIdx == null) return bytes;

    final moovStart = moovIdx.$1;
    final moovEnd = moovIdx.$2;
    final moovContent = bytes.sublist(moovStart + 8, moovEnd);
    final newMoovContent = _injectCovrInMoov(moovContent, _buildCovrAtom(jpeg));
    final newMoov = _wrapBox('moov', newMoovContent);

    final result = _spliceBytes(bytes, moovStart, moovEnd, newMoov);
    final mdatIdx = _findBox(result, 0, result.length, 'mdat');
    if (mdatIdx != null && moovStart < mdatIdx.$1) {
      final delta = newMoov.length - (moovEnd - moovStart);
      if (delta != 0) _adjustChunkOffsets(result, delta);
    }
    return result;
  }

  static Uint8List _injectCovrInMoov(Uint8List moov, Uint8List covrData) =>
      _injectIlstAtoms(moov, [covrData], replaceKey: 'covr');

  // ── Shared ilst injection ─────────────────────────────────────────────────

  /// Injects [atoms] into moov > udta > meta > ilst.
  /// If [replaceKey] is set, existing atoms with that 4-char key are replaced.
  static Uint8List _injectIlstAtoms(Uint8List moov, List<Uint8List> atoms,
      {String? replaceKey}) {
    final udtaIdx = _findBox(moov, 0, moov.length, 'udta');
    if (udtaIdx == null) {
      final udta = _wrapBox('udta', _buildMetaWithIlst(atoms));
      return Uint8List.fromList([...moov, ...udta]);
    }

    final udtaContent = moov.sublist(udtaIdx.$1 + 8, udtaIdx.$2);
    final newUdta =
        _wrapBox('udta', _injectIlstInUdta(udtaContent, atoms, replaceKey));
    return _spliceBytes(moov, udtaIdx.$1, udtaIdx.$2, newUdta);
  }

  static Uint8List _injectIlstInUdta(
      Uint8List udta, List<Uint8List> atoms, String? replaceKey) {
    final metaIdx = _findBox(udta, 0, udta.length, 'meta');
    if (metaIdx == null) {
      final meta = _buildMetaWithIlst(atoms);
      return Uint8List.fromList([...udta, ...meta]);
    }

    final metaInner = udta.sublist(metaIdx.$1 + 8, metaIdx.$2);
    final metaFlags = metaInner.sublist(0, 4);
    final metaContent = metaInner.sublist(4);
    final newMetaContent =
        _injectIlstInMeta(metaContent, atoms, replaceKey);
    final newMetaPayload =
        Uint8List.fromList([...metaFlags, ...newMetaContent]);
    final newMeta = _wrapBox('meta', newMetaPayload);
    return _spliceBytes(udta, metaIdx.$1, metaIdx.$2, newMeta);
  }

  static Uint8List _injectIlstInMeta(
      Uint8List meta, List<Uint8List> atoms, String? replaceKey) {
    final ilstIdx = _findBox(meta, 0, meta.length, 'ilst');
    if (ilstIdx == null) {
      final ilst = _wrapBox(
          'ilst', Uint8List.fromList(atoms.expand((a) => a).toList()));
      return Uint8List.fromList([...meta, ...ilst]);
    }

    final ilstContent = meta.sublist(ilstIdx.$1 + 8, ilstIdx.$2);
    final newIlstContent = _mergeIlst(ilstContent, atoms, replaceKey);
    final newIlst = _wrapBox('ilst', newIlstContent);
    return _spliceBytes(meta, ilstIdx.$1, ilstIdx.$2, newIlst);
  }

  static Uint8List _mergeIlst(
      Uint8List ilst, List<Uint8List> atoms, String? replaceKey) {
    final replaceKeys = replaceKey != null
        ? {replaceKey}
        : atoms.map((a) => String.fromCharCodes(a.sublist(4, 8))).toSet();
    final kept = <int>[];
    int pos = 0;
    while (pos + 8 <= ilst.length) {
      final sz = readUint32BE(ilst, pos);
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

  static Uint8List _buildMetaWithIlst(List<Uint8List> atoms) {
    final ilstContent =
        Uint8List.fromList(atoms.expand((a) => a).toList());
    final ilst = _wrapBox('ilst', ilstContent);
    final metaPayload = Uint8List(4 + ilst.length);
    metaPayload.setRange(4, metaPayload.length, ilst);
    return _wrapBox('meta', metaPayload);
  }

  // ── Atom builders ─────────────────────────────────────────────────────────

  static Uint8List _buildTextAtom(String key, String value) {
    final textBytes = Uint8List.fromList(value.codeUnits);
    final dataPayload = Uint8List(8 + textBytes.length);
    dataPayload[2] = 0x00;
    dataPayload[3] = 0x01; // UTF-8
    dataPayload.setRange(8, dataPayload.length, textBytes);
    return _wrapBox(key, _wrapBox('data', dataPayload));
  }

  static Uint8List _buildCovrAtom(Uint8List jpeg) {
    const flags = 0x0D; // JPEG
    final dataPayload = Uint8List(8 + jpeg.length);
    dataPayload[3] = flags;
    dataPayload.setRange(8, dataPayload.length, jpeg);
    return _wrapBox('covr', _wrapBox('data', dataPayload));
  }

  // ── Chunk offset patching ─────────────────────────────────────────────────

  static void _adjustChunkOffsets(Uint8List bytes, int delta) {
    _walkBoxes(bytes, 0, bytes.length, (type, start, end) {
      if (type == 'stco') {
        final count = readUint32BE(bytes, start + 8 + 4);
        for (int i = 0; i < count; i++) {
          final off = start + 8 + 8 + i * 4;
          writeUint32BE(bytes, off, readUint32BE(bytes, off) + delta);
        }
      } else if (type == 'co64') {
        final count = readUint32BE(bytes, start + 8 + 4);
        for (int i = 0; i < count; i++) {
          final off = start + 8 + 8 + i * 8;
          final hi = readUint32BE(bytes, off);
          final lo = readUint32BE(bytes, off + 4);
          final newVal = ((hi << 32) | lo) + delta;
          writeUint32BE(bytes, off, (newVal >> 32) & 0xFFFFFFFF);
          writeUint32BE(bytes, off + 4, newVal & 0xFFFFFFFF);
        }
      }
    });
  }

  static void _walkBoxes(Uint8List bytes, int start, int end,
      void Function(String type, int boxStart, int boxEnd) visitor) {
    int pos = start;
    while (pos + 8 <= end) {
      final sz = readUint32BE(bytes, pos);
      if (sz < 8 || pos + sz > end) break;
      final type = String.fromCharCodes(bytes.sublist(pos + 4, pos + 8));
      visitor(type, pos, pos + sz);
      if (const {'moov', 'trak', 'mdia', 'minf', 'stbl', 'udta'}
          .contains(type)) {
        _walkBoxes(bytes, pos + 8, pos + sz, visitor);
      }
      pos += sz;
    }
  }

  // ── Box utilities (also used by tests) ───────────────────────────────────

  static (int, int)? _findBox(
      Uint8List bytes, int start, int end, String type) {
    int pos = start;
    while (pos + 8 <= end) {
      final sz = readUint32BE(bytes, pos);
      if (sz < 8 || pos + sz > end) break;
      final t = String.fromCharCodes(bytes.sublist(pos + 4, pos + 8));
      if (t == type) return (pos, pos + sz);
      pos += sz;
    }
    return null;
  }

  static Uint8List _wrapBox(String type, Uint8List content) {
    final box = Uint8List(8 + content.length);
    writeUint32BE(box, 0, box.length);
    for (int i = 0; i < 4; i++) {
      box[4 + i] = type.codeUnitAt(i);
    }
    box.setRange(8, box.length, content);
    return box;
  }

  static Uint8List _spliceBytes(
      Uint8List src, int start, int end, Uint8List replacement) {
    final result =
        Uint8List(src.length - (end - start) + replacement.length);
    result.setRange(0, start, src.sublist(0, start));
    result.setRange(start, start + replacement.length, replacement);
    result.setRange(
        start + replacement.length, result.length, src.sublist(end));
    return result;
  }

  /// Reads a big-endian uint32 from [b] at [offset]. Exposed for tests.
  static int readUint32BE(Uint8List b, int offset) =>
      (b[offset] << 24) |
      (b[offset + 1] << 16) |
      (b[offset + 2] << 8) |
      b[offset + 3];

  /// Writes a big-endian uint32 [value] into [b] at [offset]. Exposed for tests.
  static void writeUint32BE(Uint8List b, int offset, int value) {
    b[offset] = (value >> 24) & 0xFF;
    b[offset + 1] = (value >> 16) & 0xFF;
    b[offset + 2] = (value >> 8) & 0xFF;
    b[offset + 3] = value & 0xFF;
  }
}
