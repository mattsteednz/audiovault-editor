import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:audiovault_editor/models/audiobook.dart';
import 'package:audiovault_editor/services/app_logger.dart';

/// Reader for chapter information embedded in single-file M4B/M4A books.
///
/// Supports both the Nero `chpl` atom (preferred — what most taggers write)
/// and the iTunes/QuickTime chapter text track (a `tref`-referenced track
/// with 'text' handler whose samples are length-prefixed UTF-8 titles).
Future<List<Chapter>> parseM4bChapters(String filePath) async {
  try {
    return await _parseM4bChaptersInner(filePath)
        .timeout(const Duration(seconds: 10), onTimeout: () => const []);
  } catch (e) {
    AppLog.d('M4B chapter scan failed for "$filePath": $e');
    return const [];
  }
}

Future<List<Chapter>> _parseM4bChaptersInner(String filePath) async {
  RandomAccessFile? raf;
  try {
    raf = await File(filePath).open();
    final fileSize = await raf.length();
    final nero = await _scanForChpl(raf, 0, fileSize);
    if (nero.isNotEmpty) return nero;
    return _parseQTChapters(raf, fileSize);
  } catch (e) {
    AppLog.d('M4B chapter scan failed for "$filePath": $e');
    return const [];
  } finally {
    await raf?.close();
  }
}

Future<List<(String, int, int)>> _listBoxes(
    RandomAccessFile raf, int start, int end) async {
  final result = <(String, int, int)>[];
  var pos = start;
  while (pos + 8 <= end) {
    await raf.setPosition(pos);
    final hdr = await raf.read(8);
    if (hdr.length < 8) break;
    final bd = ByteData.sublistView(Uint8List.fromList(hdr));
    var sz = bd.getUint32(0); // big-endian is default
    final type = String.fromCharCodes(hdr.sublist(4, 8));
    int dataStart = pos + 8;
    if (sz == 1) {
      final ext = await raf.read(8);
      if (ext.length < 8) break;
      final ebd = ByteData.sublistView(Uint8List.fromList(ext));
      sz = (ebd.getUint32(0) << 32) | ebd.getUint32(4);
      dataStart = pos + 16;
    } else if (sz == 0) {
      sz = end - pos;
    }
    if (sz < 8) break;
    result.add((type, dataStart, pos + sz));
    pos += sz;
  }
  return result;
}

(String, int, int)? _firstBox(List<(String, int, int)> boxes, String type) {
  for (final b in boxes) {
    if (b.$1 == type) return b;
  }
  return null;
}

Future<Uint8List> _readBox(RandomAccessFile raf, (String, int, int) box) async {
  await raf.setPosition(box.$2);
  return Uint8List.fromList(await raf.read(box.$3 - box.$2));
}

Future<List<Chapter>> _scanForChpl(
    RandomAccessFile raf, int start, int end,
    {int depth = 0}) async {
  if (depth > 8) return const [];
  final boxes = await _listBoxes(raf, start, end);
  for (final box in boxes) {
    if (box.$1 == 'chpl') return _parseChpl(await _readBox(raf, box));
    if (box.$1 == 'moov' || box.$1 == 'udta') {
      final result = await _scanForChpl(raf, box.$2, box.$3, depth: depth + 1);
      if (result.isNotEmpty) return result;
    }
    if (box.$1 == 'meta') {
      // meta box has a 4-byte version/flags prefix before children
      final childStart = box.$2 + 4;
      if (childStart < box.$3) {
        final result = await _scanForChpl(raf, childStart, box.$3, depth: depth + 1);
        if (result.isNotEmpty) return result;
      }
    }
  }
  return const [];
}

List<Chapter> _parseChpl(Uint8List data) {
  if (data.length < 9) return const [];
  final bd = ByteData.sublistView(data);
  int offset = 5;
  if (offset + 4 > data.length) return const [];
  final count = bd.getUint32(offset);
  offset += 4;
  final chapters = <Chapter>[];
  for (int i = 0; i < count; i++) {
    if (offset + 9 > data.length) break;
    final hi = bd.getUint32(offset);
    final lo = bd.getUint32(offset + 4);
    final units100ns = (hi << 32) | lo;
    offset += 8;
    final titleLen = data[offset++];
    if (offset + titleLen > data.length) break;
    chapters.add(Chapter(
      title: utf8.decode(data.sublist(offset, offset + titleLen),
          allowMalformed: true),
      start: Duration(microseconds: units100ns ~/ 10),
    ));
    offset += titleLen;
  }
  return chapters;
}

Future<List<Chapter>> _parseQTChapters(
    RandomAccessFile raf, int fileSize) async {
  final top = await _listBoxes(raf, 0, fileSize);
  final moov = _firstBox(top, 'moov');
  if (moov == null) return const [];
  final moovBoxes = await _listBoxes(raf, moov.$2, moov.$3);
  for (final box in moovBoxes) {
    if (box.$1 != 'trak') continue;
    final chapters = await _tryQTChapterTrak(raf, box);
    if (chapters.isNotEmpty) return chapters;
  }
  return const [];
}

Future<List<Chapter>> _tryQTChapterTrak(
    RandomAccessFile raf, (String, int, int) trak) async {
  final trakBoxes = await _listBoxes(raf, trak.$2, trak.$3);
  final mdia = _firstBox(trakBoxes, 'mdia');
  if (mdia == null) return const [];
  final mdiaBoxes = await _listBoxes(raf, mdia.$2, mdia.$3);
  final mdhd = _firstBox(mdiaBoxes, 'mdhd');
  final minf = _firstBox(mdiaBoxes, 'minf');
  if (mdhd == null || minf == null) return const [];
  final minfBoxes = await _listBoxes(raf, minf.$2, minf.$3);
  if (_firstBox(minfBoxes, 'gmhd') == null) return const [];
  final stbl = _firstBox(minfBoxes, 'stbl');
  if (stbl == null) return const [];
  final stblBoxes = await _listBoxes(raf, stbl.$2, stbl.$3);
  final stts = _firstBox(stblBoxes, 'stts');
  final stsz = _firstBox(stblBoxes, 'stsz');
  final stco = _firstBox(stblBoxes, 'stco');
  final co64 = _firstBox(stblBoxes, 'co64');
  final stsc = _firstBox(stblBoxes, 'stsc');
  if (stts == null || stsz == null || (stco == null && co64 == null)) {
    return const [];
  }
  return _extractQTChapters(raf, mdhd, stts, stsz, stco ?? co64!, stsc,
      isco64: stco == null);
}

Future<List<Chapter>> _extractQTChapters(
  RandomAccessFile raf,
  (String, int, int) mdhd,
  (String, int, int) stts,
  (String, int, int) stsz,
  (String, int, int) stco,
  (String, int, int)? stsc, {
  bool isco64 = false,
}) async {
  final mdhdData = await _readBox(raf, mdhd);
  final sttsData = await _readBox(raf, stts);
  final stszData = await _readBox(raf, stsz);
  final stcoData = await _readBox(raf, stco);
  final stscData = stsc != null ? await _readBox(raf, stsc) : null;

  final mdhdBD = ByteData.sublistView(mdhdData);
  final timeScale = mdhdBD.getUint32(mdhdData[0] == 1 ? 20 : 12);
  if (timeScale == 0) return const [];

  final sttsBD = ByteData.sublistView(sttsData);
  final sttsCount = sttsBD.getUint32(4);
  final sampleStarts = <int>[];
  int ticks = 0, off = 8;
  for (int i = 0; i < sttsCount && off + 8 <= sttsData.length; i++) {
    final n = sttsBD.getUint32(off);
    final d = sttsBD.getUint32(off + 4);
    for (int j = 0; j < n && sampleStarts.length < 10000; j++) {
      sampleStarts.add(ticks);
      ticks += d;
    }
    off += 8;
    if (sampleStarts.length >= 10000) break;
  }

  final stszBD = ByteData.sublistView(stszData);
  final defSz = stszBD.getUint32(4);
  final sampleCount = stszBD.getUint32(8);
  final sizes = <int>[];
  if (defSz == 0) {
    off = 12;
    for (int i = 0; i < sampleCount && off + 4 <= stszData.length; i++, off += 4) {
      sizes.add(stszBD.getUint32(off));
    }
  } else {
    sizes.addAll(List.filled(sampleCount, defSz));
  }

  final stcoBD = ByteData.sublistView(stcoData);
  final chunkCount = stcoBD.getUint32(4);
  final chunkOffsets = <int>[];
  off = 8;
  if (isco64) {
    for (int i = 0; i < chunkCount && off + 8 <= stcoData.length; i++, off += 8) {
      final hi = stcoBD.getUint32(off);
      final lo = stcoBD.getUint32(off + 4);
      chunkOffsets.add((hi << 32) | lo);
    }
  } else {
    for (int i = 0; i < chunkCount && off + 4 <= stcoData.length; i++, off += 4) {
      chunkOffsets.add(stcoBD.getUint32(off));
    }
  }

  final sampleOffsets = <int>[];
  if (stscData != null && stscData.length >= 8) {
    final stscBD = ByteData.sublistView(stscData);
    final stscCount = stscBD.getUint32(4);
    final runs = <(int, int)>[];
    off = 8;
    for (int i = 0; i < stscCount && off + 12 <= stscData.length; i++, off += 12) {
      runs.add((stscBD.getUint32(off) - 1,
                stscBD.getUint32(off + 4)));
    }
    int sIdx = 0;
    for (int c = 0; c < chunkOffsets.length; c++) {
      int spc = 1;
      for (int e = runs.length - 1; e >= 0; e--) {
        if (c >= runs[e].$1) { spc = runs[e].$2; break; }
      }
      int chunkOff = chunkOffsets[c];
      for (int j = 0; j < spc && sIdx < sizes.length; j++, sIdx++) {
        sampleOffsets.add(chunkOff);
        chunkOff += sizes[sIdx];
      }
    }
  } else {
    sampleOffsets.addAll(chunkOffsets.take(sizes.length));
  }

  final chapters = <Chapter>[];
  for (int i = 0;
      i < sizes.length && i < sampleOffsets.length && i < sampleStarts.length;
      i++) {
    await raf.setPosition(sampleOffsets[i]);
    final data = await raf.read(sizes[i]);
    if (data.length < 3) continue;
    final len = (data[0] << 8) | data[1];
    if (len == 0 || 2 + len > data.length) continue;
    final titleBytes = data.sublist(2, 2 + len);
    String title;
    try {
      title = utf8.decode(titleBytes);
    } catch (_) {
      // Fallback: interpret as UTF-16BE when UTF-8 decoding fails.
      final chars = <int>[];
      for (int j = 0; j + 1 < titleBytes.length; j += 2) {
        chars.add((titleBytes[j] << 8) | titleBytes[j + 1]);
      }
      title = String.fromCharCodes(chars);
    }
    chapters.add(Chapter(
      title: title,
      start: Duration(microseconds: sampleStarts[i] * 1000000 ~/ timeScale),
    ));
  }
  return chapters;
}
