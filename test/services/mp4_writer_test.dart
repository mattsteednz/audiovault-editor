import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiovault_editor/models/audiobook.dart';
import 'package:audiovault_editor/services/writers/mp4_writer.dart';

// ---------------------------------------------------------------------------
// Synthetic MP4 fixture builder + independent box parser (test-only)
// ---------------------------------------------------------------------------

void writeU32(Uint8List b, int off, int v) =>
    Mp4Writer.writeUint32BE(b, off, v);

/// Wraps [content] in a box of [type] (32-bit size only; see
/// [buildBox64] for extended sizes).
Uint8List buildBox(String type, List<int> content) {
  final box = Uint8List(8 + content.length);
  writeU32(box, 0, box.length);
  for (int i = 0; i < 4; i++) {
    box[4 + i] = type.codeUnitAt(i);
  }
  box.setRange(8, box.length, content);
  return box;
}

/// Builds a box using a 64-bit extended size header (size==1).
Uint8List buildBox64(String type, List<int> content) {
  final payloadLen = 8 + content.length;
  final box = Uint8List(16 + content.length);
  writeU32(box, 0, 1); // extended size indicator
  for (int i = 0; i < 4; i++) {
    box[4 + i] = type.codeUnitAt(i);
  }
  // 64-bit total size (big-endian)
  final hi = (payloadLen >> 32) & 0xFFFFFFFF;
  final lo = payloadLen & 0xFFFFFFFF;
  writeU32(box, 8, hi);
  writeU32(box, 12, lo);
  box.setRange(16, box.length, content);
  return box;
}

class ParsedBox {
  final String type;
  final int start;
  final int end;
  final Uint8List bytes;
  ParsedBox(this.type, this.start, this.end, this.bytes);

  Uint8List get content => Uint8List.sublistView(bytes, start + 8, end);

  /// Finds a child box by type within this box's *content*.
  ParsedBox? child(String type) => walk(bytes, start + 8, end, type);
}

ParsedBox? walk(Uint8List bytes, int from, int to, String type,
    {bool recurseInto = false}) {
  int pos = from;
  while (pos + 8 <= to) {
    var sz = readU32(bytes, pos);
    var dataStart = pos + 8;
    if (sz == 1) {
      final hi = readU32(bytes, pos + 8);
      final lo = readU32(bytes, pos + 12);
      sz = (hi << 32) | lo;
      dataStart = pos + 16;
    } else if (sz == 0) {
      sz = to - pos;
    }
    if (sz < 8 || pos + sz > to) break;
    final t = String.fromCharCodes(bytes.sublist(pos + 4, pos + 8));
    if (t == type) {
      return ParsedBox(t, pos, pos + sz, bytes);
    }
    if (recurseInto &&
        const {'moov', 'trak', 'mdia', 'minf', 'stbl', 'udta', 'meta', 'ilst'}
            .contains(t)) {
      // meta carries a 4-byte version/flags prefix before its children.
      var childFrom = dataStart;
      if (t == 'meta') childFrom += 4;
      final hit = walk(bytes, childFrom, pos + sz, type, recurseInto: true);
      if (hit != null) return hit;
    }
    pos += sz;
  }
  return null;
}

int readU32(Uint8List b, int off) =>
    Mp4Writer.readUint32BE(b, off);

/// Builds a minimal but structurally valid M4B:
/// ftyp + moov{mvhd, trak{tkhd(trackId), mdia{mdhd(timescale),
/// hdlr('soun'), minf{stbl{stts, stsz, stco}}}}} + mdat.
Uint8List buildM4bFixture({
  int audioTrackId = 1,
  int timescale = 44100,
  bool moovFirst = true,
  List<int> chunkOffsets = const [100],
}) {
  final mvhdPayload = Uint8List(100);
  writeU32(mvhdPayload, 12, 1000); // movie timescale
  final mvhd = buildBox('mvhd', mvhdPayload);

  final tkhdPayload = Uint8List(84);
  writeU32(tkhdPayload, 12, audioTrackId); // track id (version 0 layout)
  final tkhd = buildBox('tkhd', tkhdPayload);

  final mdhdPayload = Uint8List(24);
  writeU32(mdhdPayload, 12, timescale);
  final mdhd = buildBox('mdhd', mdhdPayload);

  final hdlrPayload = Uint8List(28);
  // handler_type at offset 8
  for (int i = 0; i < 4; i++) {
    hdlrPayload[8 + i] = 'soun'.codeUnitAt(i);
  }
  final hdlr = buildBox('hdlr', hdlrPayload);

  final stts = buildBox(
      'stts', [0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1]); // 1 entry
  final stszPayload = Uint8List(12);
  writeU32(stszPayload, 4, 0); // variable
  writeU32(stszPayload, 8, 1); // sample count
  final stsz = buildBox('stsz', stszPayload);
  final stcoPayload =
      Uint8List(8 + chunkOffsets.length * 4);
  writeU32(stcoPayload, 4, chunkOffsets.length);
  for (int i = 0; i < chunkOffsets.length; i++) {
    writeU32(stcoPayload, 8 + i * 4, chunkOffsets[i]);
  }
  final stco = buildBox('stco', stcoPayload);
  final stbl = buildBox(
      'stbl', [...stts, ...stsz, ...stco]);
  final minf = buildBox('minf', [...stbl]);
  final mdia = buildBox('mdia', [...mdhd, ...hdlr, ...minf]);
  final trak =
      buildBox('trak', [...tkhd, ...mdia]);
  final moov = buildBox('moov', [...mvhd, ...trak]);

  final ftyp = buildBox('ftyp', [
    ...'M4A '.codeUnits, 0, 0, 0, 0, ...'M4A '.codeUnits, ...'mp42'.codeUnits,
  ]);
  final mdat = buildBox('mdat', List<int>.filled(64, 0xAB));

  return Uint8List.fromList(moovFirst
      ? [...ftyp, ...moov, ...mdat]
      : [...ftyp, ...mdat, ...moov]);
}

/// Extracts all (key, utf8Value) pairs from moov/udta/meta/ilst.
Map<String, String> extractIlstTextValues(Uint8List fileBytes) {
  final result = <String, String>{};
  final ilst = walk(fileBytes, 0, fileBytes.length, 'ilst', recurseInto: true);
  if (ilst == null) return result;
  final content = ilst.content;
  int pos = 0;
  while (pos + 8 <= content.length) {
    final sz = readU32(content, pos);
    if (sz < 8 || pos + sz > content.length) break;
    final key =
        String.fromCharCodes(content.sublist(pos + 4, pos + 8));
    final dataBox = walk(content, pos + 8, pos + sz, 'data');
    if (dataBox != null) {
      final dataContent = dataBox.content;
      result[key] = utf8.decode(dataContent.sublist(8), allowMalformed: true);
    }
    pos += sz;
  }
  return result;
}

Audiobook bookWith({
  String? title,
  String? author,
  String? narrator,
  String? date,
  String? subtitle,
}) =>
    Audiobook(
      path: '/books/test',
      audioFiles: const [],
      title: title,
      author: author,
      narrator: narrator,
      releaseDate: date,
      subtitle: subtitle,
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Mp4Writer metadata injection', () {
    test('creates udta/meta/ilst when absent and writes UTF-8 text atoms',
        () {
      final m4b = buildM4bFixture();
      expect(walk(m4b, 0, m4b.length, 'udta'), isNull,
          reason: 'fixture must not contain udta initially');

      final result = Mp4Writer.rewriteMetadataForTest(
          m4b, bookWith(title: 'Café ☕ 日本語'));

      final values = extractIlstTextValues(result);
      expect(values['\u00a9alb'], 'Café ☕ 日本語');
    });

    test('replaces existing managed keys, preserves unmanaged ones', () {
      Uint8List dataAtom(String s) => buildBox(
          'data',
          // version/flags (4) + locale (4) + UTF-8 text
          [0, 0, 0, 1, 0, 0, 0, 0, ...utf8.encode(s)]);

      // Build moov > udta > meta > ilst {©alb:'Old', xxxx:'keepme'} directly.
      final ilst = buildBox('ilst', [
        ...buildBox('\u00a9alb', dataAtom('Old')),
        ...buildBox('xxxx', dataAtom('keepme')),
      ]);
      final metaPayload = [0, 0, 0, 0, ...ilst]; // version/flags prefix
      final udta = buildBox('udta', [...buildBox('meta', metaPayload)]);

      final base = buildM4bFixture();
      final moovBox = walk(base, 0, base.length, 'moov')!;
      final withIlst = Uint8List.fromList([
        ...base.sublist(0, moovBox.start),
        ...buildBox('moov', [...moovBox.content, ...udta]),
        ...base.sublist(moovBox.end),
      ]);

      final result = Mp4Writer.rewriteMetadataForTest(
          withIlst, bookWith(title: 'New Title'));

      final values = extractIlstTextValues(result);
      expect(values['\u00a9alb'], 'New Title');
      expect(values['xxxx'], 'keepme',
          reason: 'unmanaged ilst atoms must survive');
    });

    test('audio (mdat) is untouched by metadata rewrite', () {
      final m4b = buildM4bFixture();
      final mdatBefore = walk(m4b, 0, m4b.length, 'mdat')!.content;
      final result = Mp4Writer.rewriteMetadataForTest(
          m4b, bookWith(title: 'T'));
      final mdatAfter = walk(result, 0, result.length, 'mdat')!.content;
      expect(mdatAfter, mdatBefore);
    });

    test('adjusts stco chunk offsets when moov precedes mdat and grows', () {
      final m4b = buildM4bFixture(chunkOffsets: [100]);
      final before = readStcoOffset(m4b);
      final result = Mp4Writer.rewriteMetadataForTest(
          m4b, bookWith(title: 'A much longer title value than before'));
      final after = readStcoOffset(result);
      final delta = result.length - m4b.length;
      expect(delta, greaterThan(0));
      expect(after, before + delta);
    });

    test('does not adjust offsets when mdat precedes moov', () {
      final m4b = buildM4bFixture(moovFirst: false, chunkOffsets: [100]);
      final before = readStcoOffset(m4b);
      final result = Mp4Writer.rewriteMetadataForTest(
          m4b, bookWith(title: 'Some title'));
      final after = readStcoOffset(result);
      expect(after, before);
    });

    test('returns input unchanged when no moov exists', () {
      final junk = Uint8List.fromList([1, 2, 3, 4]);
      expect(Mp4Writer.rewriteMetadataForTest(junk, bookWith(title: 'X')),
          same(junk));
    });
  });

  group('Mp4Writer cover injection', () {
    test('writes covr atom with JPEG flag', () {
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
      final result = Mp4Writer.rewriteCoverForTest(buildM4bFixture(), jpeg);
      final covr =
          walk(result, 0, result.length, 'covr', recurseInto: true);
      expect(covr, isNotNull);
      final dataContent = covr!
          .child('data')
          !
          .content;
      expect(dataContent[3], 0x0D, reason: 'JPEG type flag');
      expect(dataContent.sublist(8), jpeg);
    });
  });

  group('Mp4Writer 64-bit extended boxes', () {
    test('finds and rewrites moov declared with extended size', () {
      final base = buildM4bFixture();
      // Replace the 32-bit moov with a 64-bit-sized one.
      final moov = walk(base, 0, base.length, 'moov')!;
      final moov64 = buildBox64('moov', moov.content);
      final with64 = Uint8List.fromList([
        ...base.sublist(0, moov.start),
        ...moov64,
        ...base.sublist(moov.end),
      ]);

      final result = Mp4Writer.rewriteMetadataForTest(
          with64, bookWith(title: 'Ext64'));
      final values = extractIlstTextValues(result);
      expect(values['\u00a9alb'], 'Ext64');
    });
  });

  group('Mp4Writer chapter writing', () {
    test('adds a QT chapter track + chap tref and appends samples', () {
      final m4b = buildM4bFixture();
      final chapters = [
        const Chapter(title: 'Intro', start: Duration.zero),
        const Chapter(title: 'Kapitel zwei', start: Duration(minutes: 5)),
        const Chapter(title: 'Ende', start: Duration(minutes: 10)),
      ];

      final result = Mp4Writer.writeChaptersForTest(
          m4b, chapters, const Duration(minutes: 15));

      // A chapter text track now exists.
      final chapterHdlr = _findHdlrWithType(result, 'text');
      expect(chapterHdlr, isNotNull, reason: 'chapter text track must exist');

      // Audio track references it via chap/tref.
      final tref =
          walk(result, 0, result.length, 'tref', recurseInto: true);
      expect(tref, isNotNull, reason: 'audio trak must gain a tref');
      final chap = tref!.child('chap');
      expect(chap, isNotNull, reason: 'tref must contain chap');

      // Sample data appended at EOF contains length-prefixed UTF-8 titles.
      for (final ch in chapters) {
        final titleBytes = utf8.encode(ch.title);
        final needle = [
          (titleBytes.length >> 8) & 0xFF,
          titleBytes.length & 0xFF,
          ...titleBytes,
        ];
        expect(_containsSublist(result, needle), isTrue,
            reason: 'sample for "${ch.title}" must be appended');
      }

      // The original audio stco entries are unchanged relative to their own
      // values (mdat precedes moov splice target here since fixture has
      // moov first... actually moov-first means offsets shift; assert they
      // were adjusted by the moov delta).
      final origMoovSize = _boxSize(m4b, 'moov');
      final newMoovSize = _boxSize(result, 'moov');
      final delta = newMoovSize - origMoovSize;
      if (delta > 0) {
        expect(readStcoOffsetOfTrack(result, audioTrackId: 1),
            100 + delta);
      }
    });

    test('rewrites an existing chpl atom instead of adding a second format',
        () {
      // Build a fixture whose moov/udta contains a chpl atom.
      final chplPayload = BytesBuilder();
      chplPayload.add([0x00]); // version
      chplPayload.add(Uint8List(4)); // reserved
      chplPayload.add([0, 0, 0, 1]); // count=1
      // timestamp 100ns units = 60s -> 600,000,000
      const ts = 600000000;
      chplPayload.add([
        (ts >> 56) & 0xFF, (ts >> 48) & 0xFF, (ts >> 40) & 0xFF,
        (ts >> 32) & 0xFF, (ts >> 24) & 0xFF, (ts >> 16) & 0xFF,
        (ts >> 8) & 0xFF, ts & 0xFF,
      ]);
      chplPayload.add([5, ...utf8.encode('Altch')]);
      final chplBox = buildBox('chpl', chplPayload.toBytes());
      final udta = buildBox('udta', [...chplBox]);

      final base = buildM4bFixture();
      final moov = walk(base, 0, base.length, 'moov')!;
      final newMoov =
          buildBox('moov', [...moov.content, ...udta]);
      final withChpl = Uint8List.fromList([
        ...base.sublist(0, moov.start),
        ...newMoov,
        ...base.sublist(moov.end),
      ]);

      final result = Mp4Writer.writeChaptersForTest(withChpl, [
        const Chapter(title: 'Neu Eins', start: Duration.zero),
        const Chapter(title: 'Neu Zwei', start: Duration(minutes: 3)),
      ], null);

      // chpl updated with new titles...
      expect(_containsSublist(result, utf8.encode('Neu Eins')), isTrue);
      expect(_containsSublist(result, utf8.encode('Neu Zwei')), isTrue);
      // ...old content gone...
      expect(_containsSublist(result, utf8.encode('Altch')), isFalse);
      // ...and no QT text-track was added (chpl path short-circuits).
      final textHdlr = _findHdlrWithType(result, 'text');
      final hadTextTrackBefore =
          _findHdlrWithType(withChpl, 'text') != null;
      if (!hadTextTrackBefore) {
        expect(textHdlr, isNull,
            reason: 'no extra QT chapter track when chpl existed');
      }
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

int readStcoOffset(Uint8List bytes) {
  final stco = walk(bytes, 0, bytes.length, 'stco', recurseInto: true)!;
  return readU32(stco.bytes, stco.start + 8 + 8);
}

int readStcoOffsetOfTrack(Uint8List bytes, {required int audioTrackId}) {
  // Walk top-level moov > trak boxes; pick the one whose tkhd track id
  // matches, then read its stco's first offset.
  final moov = walk(bytes, 0, bytes.length, 'moov')!;
  final content = moov.content;
  int pos = 0;
  while (pos + 8 <= content.length) {
    final sz = readU32(content, pos);
    if (sz < 8 || pos + sz > content.length) break;
    final type =
        String.fromCharCodes(content.sublist(pos + 4, pos + 8));
    if (type == 'trak') {
      final tkhd = walk(content, pos + 8, pos + sz, 'tkhd');
      if (tkhd != null) {
        final id = readU32(content, tkhd.start + 8 + 12);
        if (id == audioTrackId) {
          final stco =
              walk(content, pos + 8, pos + sz, 'stco', recurseInto: true)!;
          return readU32(content, stco.start + 8 + 8);
        }
      }
    }
    pos += sz;
  }
  fail('audio trak $audioTrackId not found');
}

ParsedBox? _findHdlrWithType(Uint8List bytes, String handlerType) {
  final moov = walk(bytes, 0, bytes.length, 'moov');
  if (moov == null) return null;
  final content = moov.content;
  int pos = 0;
  while (pos + 8 <= content.length) {
    final sz = readU32(content, pos);
    if (sz < 8 || pos + sz > content.length) break;
    final type = String.fromCharCodes(content.sublist(pos + 4, pos + 8));
    if (type == 'trak') {
      // hdlr sits at trak > mdia > hdlr — find each level directly.
      final mdia = walk(content, pos + 8, pos + sz, 'mdia');
      if (mdia != null) {
        final hdlr = walk(content, mdia.start + 8, mdia.end, 'hdlr');
        if (hdlr != null) {
          final handler = String.fromCharCodes(
              content.sublist(hdlr.start + 8 + 8, hdlr.start + 8 + 12));
          if (handler == handlerType) return hdlr;
        }
      }
    }
    pos += sz;
  }
  return null;
}

int _boxSize(Uint8List bytes, String type) {
  int pos = 0;
  while (pos + 8 <= bytes.length) {
    final sz = readU32(bytes, pos);
    if (sz < 8 || pos + sz > bytes.length) break;
    final t = String.fromCharCodes(bytes.sublist(pos + 4, pos + 8));
    if (t == type) return sz;
    pos += sz;
  }
  fail('$type not found');
}

bool _containsSublist(List<int> haystack, List<int> needle) {
  if (needle.isEmpty) return true;
  for (int i = 0; i <= haystack.length - needle.length; i++) {
    var match = true;
    for (int j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}
