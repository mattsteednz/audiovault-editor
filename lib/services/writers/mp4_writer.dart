import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:audiovault_editor/models/audiobook.dart';
import 'package:audiovault_editor/services/writers/atomic_file_writer.dart';

class Mp4Writer {
  const Mp4Writer._();

  static Future<void> writeMetadata(String filePath, Audiobook book) async {
    final bytes = await File(filePath).readAsBytes();
    final plan = _metadataPlan(bytes, book);
    if (plan == null) return;
    await writeFileAtomicSplice(filePath, plan);
  }

  static SplicePlan? _metadataPlan(Uint8List bytes, Audiobook book) {
    final moovIdx = _findBox(bytes, 0, bytes.length, 'moov');
    if (moovIdx == null) return null;

    final moovData = _dataStartAt(bytes, moovIdx.$1, moovIdx.$2);
    final moovContent = bytes.sublist(moovData, moovIdx.$2);
    var newMoovContent = _injectTextAtomsInMoov(moovContent, book);
    newMoovContent = _shiftOffsetsIfMdatFollows(
        bytes, moovIdx.$1, moovIdx.$2, newMoovContent);
    final newMoov = _wrapBox('moov', newMoovContent);
    return SplicePlan(
        replaceStart: moovIdx.$1,
        replaceEnd: moovIdx.$2,
        replacement: newMoov);
  }

  /// If mdat follows moov in [bytes], growing/shrinking moov by
  /// `(8 + newMoovContent.length) - oldMoovSize` shifts every media chunk.
  /// stco/co64 tables live only under moov, so patching the rebuilt children
  /// is equivalent to patching the spliced file.
  static Uint8List _shiftOffsetsIfMdatFollows(Uint8List bytes, int moovStart,
      int moovEnd, Uint8List newMoovContent) {
    final mdatIdx = _findBox(bytes, 0, bytes.length, 'mdat');
    if (mdatIdx == null || moovStart >= mdatIdx.$1) return newMoovContent;
    final delta =
        8 + newMoovContent.length - (moovEnd - moovStart);
    if (delta == 0) return newMoovContent;
    final patched = Uint8List.fromList(newMoovContent);
    _adjustChunkOffsets(patched, delta);
    return patched;
  }

  /// Pure cores — build a plan and execute it against the original bytes.
  /// Existing tests assert on the executed output.
  @visibleForTesting
  static Uint8List rewriteMetadataForTest(Uint8List bytes, Audiobook book) {
    final plan = _metadataPlan(bytes, book);
    return plan == null ? bytes : plan.execute(bytes);
  }

  @visibleForTesting
  static Uint8List rewriteCoverForTest(Uint8List bytes, Uint8List jpeg) {
    final plan = _coverPlan(bytes, jpeg);
    return plan == null ? bytes : plan.execute(bytes);
  }

  @visibleForTesting
  static Uint8List writeChaptersForTest(Uint8List bytes,
      List<Chapter> chapters, Duration? bookDuration) {
    final plan = _chaptersPlan(bytes, chapters, bookDuration);
    return plan == null ? bytes : plan.execute(bytes);
  }

  static Future<void> embedCover(String filePath, Uint8List jpeg) async {
    final bytes = await File(filePath).readAsBytes();
    final plan = _coverPlan(bytes, jpeg);
    if (plan == null) return;
    await writeFileAtomicSplice(filePath, plan);
  }

  // ── Chapter track write ───────────────────────────────────────────────────

  /// Writes an iTunes/QuickTime chapter track to an M4B/M4A file.
  ///
  /// - Removes any existing chapter track (trak with mdia/hdlr type 'text' and gmhd)
  /// - Builds a new chapter text track with one sample per chapter
  /// - Adds a chap atom in the audio track's tref box referencing the chapter track
  /// - Adjusts chunk offsets if moov precedes mdat
  static Future<void> writeChapters(
    String filePath,
    List<Chapter> chapters,
    Duration? bookDuration,
  ) async {
    if (chapters.isEmpty) return;
    final bytes = await File(filePath).readAsBytes();
    final plan = _chaptersPlan(bytes, chapters, bookDuration);
    if (plan == null) return;
    await writeFileAtomicSplice(filePath, plan);
  }

  /// Reads a box header at [pos]. Returns `(size, headerSize)` where [size]
  /// is the full box size (handling the 64-bit extended-size form `size==1`
  /// and the "until end" form `size==0`) and [headerSize] is 8 or 16.
  /// Returns size 0 for malformed headers.
  static (int, int) _boxHeaderAt(Uint8List b, int pos, int end) {
    final sz32 = readUint32BE(b, pos);
    if (sz32 == 1) {
      if (pos + 16 > end) return (0, 8);
      final hi = readUint32BE(b, pos + 8);
      final lo = readUint32BE(b, pos + 12);
      final v = (hi << 32) | lo;
      return (v < 16 ? 0 : v, 16);
    }
    if (sz32 == 0) return (end - pos, 8);
    return (sz32, 8);
  }

  /// Start offset of a box's payload (past its header), honouring extended
  /// 64-bit headers.
  static int _dataStartAt(Uint8List b, int boxStart, int boxEnd) =>
      boxStart + _boxHeaderAt(b, boxStart, boxEnd).$2;

  static SplicePlan? _chaptersPlan(
      Uint8List bytes, List<Chapter> chapters, Duration? bookDuration,
      {bool forceCo64 = false}) {
    // Step 1: Find moov
    final moovIdx = _findBox(bytes, 0, bytes.length, 'moov');
    if (moovIdx == null) return null;

    final moovStart = moovIdx.$1;
    final moovEnd = moovIdx.$2;

    // Step 1b: Rewrite chpl (Nero) atom if present, so the scanner's
    // chpl-first read path picks up the new chapter names. Because we
    // rebuild the whole moov below, ancestor size fixups are unnecessary.
    bytes = _rewriteChpl(bytes, moovStart, moovEnd, chapters);

    // Re-find moov after the potential chpl splice (size may have changed).
    final moovIdx2 = _findBox(bytes, 0, bytes.length, 'moov');
    if (moovIdx2 == null) return null;
    final moovStart2 = moovIdx2.$1;
    final moovEnd2 = moovIdx2.$2;

    // If the file had a chpl atom we've already updated it — no need to also
    // write a QT chapter track. Only write the QT track for files that had
    // neither format (chpl was absent).
    final hadChpl = _hasChpl(bytes, moovStart2, moovEnd2);
    if (hadChpl) {
      // chpl already updated above; no QT chapter track is added. The plan
      // replaces the (already-fixed) moov region.
      final updatedMoov = _findBox(bytes, 0, bytes.length, 'moov');
      if (updatedMoov == null) return null;
      return SplicePlan(
        replaceStart: moovStart2,
        replaceEnd: moovEnd2,
        replacement: bytes.sublist(updatedMoov.$1, updatedMoov.$2),
      );
    }

    // Step 2: Parse moov to find audio track ID and timescale
    int audioTrackId = 1;
    int audioTimescale = 44100;
    int movieTimescale = 1000;

    // Find mvhd for movie timescale
    final mvhdIdx = _findBox(bytes, moovStart2 + 8, moovEnd2, 'mvhd');
    if (mvhdIdx != null) {
      final mvhdData = _dataStartAt(bytes, mvhdIdx.$1, mvhdIdx.$2);
      final version = bytes[mvhdData];
      movieTimescale = readUint32BE(bytes, mvhdData + (version == 1 ? 20 : 12));
    }

    // Walk trak boxes to find audio track
    int pos = moovStart2 + 8;
    while (pos + 8 <= moovEnd2) {
      final (sz, hdrSize) = _boxHeaderAt(bytes, pos, moovEnd2);
      if (sz < 8 || pos + sz > moovEnd2) break;
      final type = String.fromCharCodes(bytes.sublist(pos + 4, pos + 8));
      if (type == 'trak') {
        final trakEnd = pos + sz;
        // Check mdia/hdlr for 'soun'
        final mdiaIdx = _findBox(bytes, pos + hdrSize, trakEnd, 'mdia');
        if (mdiaIdx != null) {
          final hdlrIdx = _findBox(bytes, mdiaIdx.$1 + 8, mdiaIdx.$2, 'hdlr');
          if (hdlrIdx != null) {
            // hdlr: version(1) + flags(3) + pre_defined(4) + handler_type(4)
            final handlerOffset =
                _dataStartAt(bytes, hdlrIdx.$1, hdlrIdx.$2) + 8;
            if (handlerOffset + 4 <= hdlrIdx.$2) {
              final handler = String.fromCharCodes(
                  bytes.sublist(handlerOffset, handlerOffset + 4));
              if (handler == 'soun') {
                // Read track ID from tkhd
                final tkhdIdx = _findBox(bytes, pos + 8, trakEnd, 'tkhd');
                if (tkhdIdx != null) {
                  final tkhdData = _dataStartAt(bytes, tkhdIdx.$1, tkhdIdx.$2);
                  final tkhdVersion = bytes[tkhdData];
                  audioTrackId =
                      readUint32BE(bytes, tkhdData + (tkhdVersion == 1 ? 20 : 12));
                }
                // Read timescale from mdhd
                final mdhdIdx =
                    _findBox(bytes, mdiaIdx.$1 + 8, mdiaIdx.$2, 'mdhd');
                if (mdhdIdx != null) {
                  final mdhdData = _dataStartAt(bytes, mdhdIdx.$1, mdhdIdx.$2);
                  final mdhdVersion = bytes[mdhdData];
                  audioTimescale =
                      readUint32BE(bytes, mdhdData + (mdhdVersion == 1 ? 20 : 12));
                  if (audioTimescale == 0) audioTimescale = 44100;
                }
              }
            }
          }
        }
      }
      pos += sz;
    }

    // Step 3: Remove existing chapter track and collect remaining trak boxes
    // Also find the audio trak bytes for step 5
    final List<Uint8List> otherBoxes = []; // non-trak moov children
    final List<Uint8List> nonChapterTraks = [];
    Uint8List? audioTrakBytes;

    pos = moovStart2 + 8;
    while (pos + 8 <= moovEnd2) {
      final (sz, hdrSize) = _boxHeaderAt(bytes, pos, moovEnd2);
      if (sz < 8 || pos + sz > moovEnd2) break;
      final type = String.fromCharCodes(bytes.sublist(pos + 4, pos + 8));
      if (type == 'trak') {
        final trakEnd = pos + sz;
        final trakBytes = bytes.sublist(pos, trakEnd);
        // Check if this is a chapter text track (has mdia/hdlr 'text' AND mdia/minf/gmhd)
        bool isChapterTrack = false;
        bool isAudioTrack = false;
        final mdiaIdx = _findBox(bytes, pos + hdrSize, trakEnd, 'mdia');
        if (mdiaIdx != null) {
          final hdlrIdx =
              _findBox(bytes, mdiaIdx.$1 + 8, mdiaIdx.$2, 'hdlr');
          if (hdlrIdx != null) {
            final handlerOffset =
                _dataStartAt(bytes, hdlrIdx.$1, hdlrIdx.$2) + 8;
            if (handlerOffset + 4 <= hdlrIdx.$2) {
              final handler = String.fromCharCodes(
                  bytes.sublist(handlerOffset, handlerOffset + 4));
              if (handler == 'text') {
                // Check for gmhd
                final minfIdx =
                    _findBox(bytes, mdiaIdx.$1 + 8, mdiaIdx.$2, 'minf');
                if (minfIdx != null) {
                  final gmhdIdx = _findBox(
                      bytes, minfIdx.$1 + 8, minfIdx.$2, 'gmhd');
                  if (gmhdIdx != null) {
                    isChapterTrack = true;
                  }
                }
              } else if (handler == 'soun') {
                isAudioTrack = true;
              }
            }
          }
        }
        if (!isChapterTrack) {
          if (isAudioTrack) {
            audioTrakBytes = trakBytes;
          }
          nonChapterTraks.add(trakBytes);
        }
      } else {
        otherBoxes.add(bytes.sublist(pos, pos + sz));
      }
      pos += sz;
    }

    final useCo64 = forceCo64;

    // Step 4: Build the new chapter text track
    final chapterTrackId = audioTrackId + 1;

    // Build samples: 2-byte big-endian length + UTF-8 bytes
    final List<Uint8List> samples = [];
    for (final ch in chapters) {
      final titleBytes = utf8.encode(ch.title);
      final sample = Uint8List(2 + titleBytes.length);
      sample[0] = (titleBytes.length >> 8) & 0xFF;
      sample[1] = titleBytes.length & 0xFF;
      sample.setRange(2, sample.length, titleBytes);
      samples.add(sample);
    }

    // Build stts entries: one per chapter
    final List<int> sttsDurations = [];
    for (int i = 0; i < chapters.length; i++) {
      int durationTicks;
      if (i < chapters.length - 1) {
        final diffUs =
            (chapters[i + 1].start - chapters[i].start).inMicroseconds;
        durationTicks = (diffUs * audioTimescale / 1000000).round();
      } else {
        if (bookDuration != null) {
          final diffUs =
              (bookDuration - chapters.last.start).inMicroseconds;
          durationTicks = (diffUs * audioTimescale / 1000000).round();
        } else {
          durationTicks = audioTimescale * 60; // 1 minute fallback
        }
      }
      if (durationTicks < 0) durationTicks = 0;
      sttsDurations.add(durationTicks);
    }

    final totalDurationTicks =
        sttsDurations.fold<int>(0, (a, b) => a + b);

    // stts box: version(4) + entry_count(4) + entries(n * 8)
    final sttsPayload = Uint8List(4 + 4 + chapters.length * 8);
    writeUint32BE(sttsPayload, 4, chapters.length);
    for (int i = 0; i < chapters.length; i++) {
      writeUint32BE(sttsPayload, 8 + i * 8, 1); // sample_count = 1
      writeUint32BE(sttsPayload, 8 + i * 8 + 4, sttsDurations[i]);
    }
    final sttsBox = _wrapBox('stts', sttsPayload);

    // stsz box: version(4) + sample_size(4) + sample_count(4) + entries(n * 4)
    final stszPayload = Uint8List(4 + 4 + 4 + samples.length * 4);
    writeUint32BE(stszPayload, 4, 0); // variable size
    writeUint32BE(stszPayload, 8, samples.length);
    for (int i = 0; i < samples.length; i++) {
      writeUint32BE(stszPayload, 12 + i * 4, samples[i].length);
    }
    final stszBox = _wrapBox('stsz', stszPayload);

    // Chunk offset table: 32-bit stco normally; 64-bit co64 when the appended
    // sample data would live beyond the 32-bit address space.
    final Uint8List chunkPayload;
    final String chunkType;
    if (useCo64) {
      chunkType = 'co64';
      chunkPayload = Uint8List(4 + 4 + samples.length * 8);
      writeUint32BE(chunkPayload, 4, samples.length);
    } else {
      chunkType = 'stco';
      chunkPayload = Uint8List(4 + 4 + samples.length * 4);
      writeUint32BE(chunkPayload, 4, samples.length);
    }
    // offsets will be fixed up after assembly
    final chunkBox = _wrapBox(chunkType, chunkPayload);

    // stsc box: version(4) + entry_count(4) + one entry(12)
    // first_chunk=1, samples_per_chunk=1, sample_description_index=1
    final stscPayload = Uint8List(4 + 4 + 12);
    writeUint32BE(stscPayload, 4, 1); // entry_count
    writeUint32BE(stscPayload, 8, 1); // first_chunk
    writeUint32BE(stscPayload, 12, 1); // samples_per_chunk
    writeUint32BE(stscPayload, 16, 1); // sample_description_index
    final stscBox = _wrapBox('stsc', stscPayload);

    // stsd box: version(4) + entry_count(4) + one text sample description (36 bytes)
    // Text sample description: size(4) + type(4) + reserved(6) + data_ref_index(2) + 20 bytes zeros
    final textSampleDesc = Uint8List(36);
    writeUint32BE(textSampleDesc, 0, 36); // size
    textSampleDesc[4] = 0x74; // 't'
    textSampleDesc[5] = 0x65; // 'e'
    textSampleDesc[6] = 0x78; // 'x'
    textSampleDesc[7] = 0x74; // 't'
    textSampleDesc[14] = 0x00; // data_ref_index high
    textSampleDesc[15] = 0x01; // data_ref_index = 1
    final stsdPayload = Uint8List(4 + 4 + textSampleDesc.length);
    writeUint32BE(stsdPayload, 4, 1); // entry_count
    stsdPayload.setRange(8, stsdPayload.length, textSampleDesc);
    final stsdBox = _wrapBox('stsd', stsdPayload);

    // stbl
    final stblContent = Uint8List.fromList([
      ...stsdBox,
      ...sttsBox,
      ...stszBox,
      ...chunkBox,
      ...stscBox,
    ]);
    final stblBox = _wrapBox('stbl', stblContent);

    // gmhd: 8-byte box header + 8 bytes zeros content
    final gmhdContent = Uint8List(8);
    final gmhdBox = _wrapBox('gmhd', gmhdContent);

    // dinf/dref: self-contained reference
    // dref entry: size(4) + 'url '(4) + version/flags(4) with flags=0x000001 (self-contained)
    final urlEntry = Uint8List(12);
    writeUint32BE(urlEntry, 0, 12);
    urlEntry[4] = 0x75; // 'u'
    urlEntry[5] = 0x72; // 'r'
    urlEntry[6] = 0x6C; // 'l'
    urlEntry[7] = 0x20; // ' '
    urlEntry[11] = 0x01; // flags = self-contained
    final drefPayload = Uint8List(4 + 4 + urlEntry.length);
    writeUint32BE(drefPayload, 4, 1); // entry_count
    drefPayload.setRange(8, drefPayload.length, urlEntry);
    final drefBox = _wrapBox('dref', drefPayload);
    final dinfBox = _wrapBox('dinf', drefBox);

    // minf
    final minfContent =
        Uint8List.fromList([...gmhdBox, ...dinfBox, ...stblBox]);
    final minfBox = _wrapBox('minf', minfContent);

    // mdhd: version 0
    // version(1) + flags(3) + creation_time(4) + modification_time(4) +
    // timescale(4) + duration(4) + language(2) + pre_defined(2)
    final mdhdPayload = Uint8List(4 + 4 + 4 + 4 + 4 + 2 + 2);
    writeUint32BE(mdhdPayload, 4, audioTimescale);
    writeUint32BE(mdhdPayload, 8, totalDurationTicks);
    // language: 'und' = 0x55C4 (ISO 639-2/T packed)
    mdhdPayload[12] = 0x55;
    mdhdPayload[13] = 0xC4;
    final mdhdBox = _wrapBox('mdhd', mdhdPayload);

    // hdlr: version(4) + pre_defined(4) + handler_type(4) + reserved(12) + name
    final handlerName = utf8.encode('Chapter Track\x00');
    final hdlrPayload = Uint8List(4 + 4 + 4 + 12 + handlerName.length);
    // handler_type = 'text' at offset 8
    hdlrPayload[8] = 0x74; // 't'
    hdlrPayload[9] = 0x65; // 'e'
    hdlrPayload[10] = 0x78; // 'x'
    hdlrPayload[11] = 0x74; // 't'
    // name starts at offset 24 (after version+flags(4) + pre_defined(4) + handler_type(4) + reserved(12))
    hdlrPayload.setRange(24, hdlrPayload.length, handlerName);
    final hdlrBox = _wrapBox('hdlr', hdlrPayload);

    // mdia
    final mdiaContent =
        Uint8List.fromList([...mdhdBox, ...hdlrBox, ...minfBox]);
    final mdiaBox = _wrapBox('mdia', mdiaContent);

    // tkhd: version 0, flags=0x0F (enabled+in-movie+in-preview+in-poster)
    // version(1) + flags(3) + creation_time(4) + modification_time(4) +
    // track_id(4) + reserved(4) + duration(4) + reserved(8) + layer(2) +
    // alternate_group(2) + volume(2) + reserved(2) + matrix(36) + width(4) + height(4)
    final durationInMovieTimescale = bookDuration != null
        ? (bookDuration.inMicroseconds * movieTimescale / 1000000).round()
        : totalDurationTicks;
    final tkhdPayload = Uint8List(4 + 4 + 4 + 4 + 4 + 8 + 2 + 2 + 2 + 2 + 36 + 4 + 4);
    tkhdPayload[3] = 0x0F; // flags = enabled+in-movie+in-preview+in-poster
    writeUint32BE(tkhdPayload, 8, chapterTrackId);
    writeUint32BE(tkhdPayload, 16, durationInMovieTimescale);
    // Identity matrix: [0x00010000, 0, 0, 0, 0x00010000, 0, 0, 0, 0x40000000]
    const matrixOffset = 4 + 4 + 4 + 4 + 4 + 8 + 2 + 2 + 2 + 2;
    writeUint32BE(tkhdPayload, matrixOffset, 0x00010000);
    writeUint32BE(tkhdPayload, matrixOffset + 16, 0x00010000);
    writeUint32BE(tkhdPayload, matrixOffset + 32, 0x40000000);
    final tkhdBox = _wrapBox('tkhd', tkhdPayload);

    // trak (chapter)
    final chapterTrakContent =
        Uint8List.fromList([...tkhdBox, ...mdiaBox]);
    final chapterTrakBox = _wrapBox('trak', chapterTrakContent);

    // Step 5: Add chap atom to audio track's tref
    Uint8List updatedAudioTrak;
    if (audioTrakBytes != null) {
      updatedAudioTrak =
          _addChapAtomToTrak(audioTrakBytes, chapterTrackId);
    } else {
      updatedAudioTrak = Uint8List(0);
    }

    // Step 6: Assemble new moov
    // Replace audio trak with updated version, append chapter trak
    final newMoovContent = BytesBuilder();
    for (final box in otherBoxes) {
      newMoovContent.add(box);
    }
    for (final trak in nonChapterTraks) {
      if (audioTrakBytes != null &&
          trak.length == audioTrakBytes.length &&
          _bytesEqual(trak, audioTrakBytes)) {
        newMoovContent.add(updatedAudioTrak);
      } else {
        newMoovContent.add(trak);
      }
    }
    newMoovContent.add(chapterTrakBox);

    // Adjust existing chunk offsets if moov precedes mdat — the stco/co64
    // boxes live exclusively under moov, so patching the rebuilt content
    // before wrapping is equivalent to patching the spliced file.
    var moovChildren = newMoovContent.toBytes();
    moovChildren = _shiftOffsetsIfMdatFollows(
        bytes, moovStart2, moovEnd2,
        Uint8List.fromList(moovChildren));

    // Chapter samples are appended after the original EOF; their absolute
    // offset is therefore fully determined before anything is written.
    final sampleDataOffset = bytes.length -
        (moovEnd2 - moovStart2) +
        (8 + moovChildren.length);
    // If the sample data would live beyond the 32-bit address space and we
    // built a 32-bit stco, redo the whole rewrite with co64 entries.
    if (!forceCo64 && sampleDataOffset + 16 > 0xFFFFFFFF) {
      return _chaptersPlan(bytes, chapters, bookDuration,
          forceCo64: true);
    }
    final List<int> sampleOffsets = [];
    int cumOffset = sampleDataOffset;
    for (final sample in samples) {
      sampleOffsets.add(cumOffset);
      cumOffset += sample.length;
    }

    // Fix the chapter track's offset table inside the rebuilt moov.
    final fixed = Uint8List.fromList(moovChildren);
    _fixChapterChunkOffsetsInContent(
        fixed, chapterTrackId, sampleOffsets, useCo64);

    final newMoov = _wrapBox('moov', fixed);
    return SplicePlan(
      replaceStart: moovStart2,
      replaceEnd: moovEnd2,
      replacement: newMoov,
      appendix: Uint8List.fromList(samples.expand((s) => s).toList()),
    );
  }

  /// Returns true if a `chpl` atom exists anywhere under [moovStart].
  static bool _hasChpl(Uint8List bytes, int moovStart, int moovEnd) {
    bool found = false;
    void search(int start, int end) {
      int pos = start;
      while (pos + 8 <= end) {
        final (sz, _) = _boxHeaderAt(bytes, pos, end);
        if (sz < 8 || pos + sz > end) break;
        final type = String.fromCharCodes(bytes.sublist(pos + 4, pos + 8));
        if (type == 'chpl') { found = true; return; }
        if (type == 'udta' || type == 'moov') {
          final (_, hdrSize) = _boxHeaderAt(bytes, pos, end);
          search(pos + hdrSize, pos + sz);
        }
        pos += sz;
      }
    }
    search(moovStart + 8, moovEnd);
    return found;
  }

  /// Rewrites the `chpl` (Nero chapter) atom inside `moov > udta` if one
  /// exists, replacing it with [chapters]. If no `chpl` is found the file is
  /// returned unchanged — we only update what's already there.
  ///
  /// Because the replacement may differ in size, every ancestor container
  /// between the top level and the chpl box (e.g. moov, udta) has its size
  /// field adjusted by the delta; otherwise the file would be left with
  /// structurally invalid container sizes.
  static Uint8List _rewriteChpl(
      Uint8List bytes, int moovStart, int moovEnd, List<Chapter> chapters) {
    // Walk moov children looking for udta, then walk udta for chpl.
    // chpl can also appear directly under moov in some encoders.
    int? chplStart;
    int? chplEnd;
    final chain = <(int, int)>[]; // ancestor boxes (start, end), outermost first

    void findChpl(int start, int end) {
      int pos = start;
      while (pos + 8 <= end) {
        final (sz, _) = _boxHeaderAt(bytes, pos, end);
        if (sz < 8 || pos + sz > end) break;
        final type = String.fromCharCodes(bytes.sublist(pos + 4, pos + 8));
        if (type == 'chpl') {
          chplStart = pos;
          chplEnd = pos + sz;
          return;
        }
        if (type == 'udta' || type == 'moov') {
          chain.add((pos, pos + sz));
          final (_, hdrSize) = _boxHeaderAt(bytes, pos, end);
          findChpl(pos + hdrSize, pos + sz);
          if (chplStart != null) return;
          chain.removeLast();
        }
        pos += sz;
      }
    }

    // The moov itself is always an ancestor of any chpl we find here.
    chain.add((moovStart, moovEnd));
    findChpl(moovStart + 8, moovEnd);
    if (chplStart == null) return bytes; // no chpl — nothing to update

    final newChplPayload = _buildChplPayload(chapters);
    final newChplBox = _wrapBox('chpl', newChplPayload);
    var out = _spliceBytes(bytes, chplStart!, chplEnd!, newChplBox);

    // Adjust ancestor container sizes by the splice delta.
    final delta = newChplBox.length - (chplEnd! - chplStart!);
    if (delta != 0) {
      for (final (start, end) in chain) {
        final (sz, hdrSize) = _boxHeaderAt(out, start, end);
        if (hdrSize == 16) {
          final hi = readUint32BE(out, start + 8);
          final lo = readUint32BE(out, start + 12);
          final newVal = ((hi << 32) | lo) + delta;
          writeUint32BE(out, start + 8, (newVal >> 32) & 0xFFFFFFFF);
          writeUint32BE(out, start + 12, newVal & 0xFFFFFFFF);
        } else if (sz >= 8) {
          writeUint32BE(out, start, readUint32BE(out, start) + delta);
        }
      }
    }
    return out;
  }

  /// Serialises [chapters] into the Nero `chpl` atom payload.
  ///
  /// Format (data section, i.e. after the 8-byte box header):
  ///   version(1) + reserved(4) + count(4) + per-chapter:
  ///     timestamp_100ns(8, big-endian uint64) + title_len(1) + title(N)
  static Uint8List _buildChplPayload(List<Chapter> chapters) {
    // Calculate total size first.
    int size = 1 + 4 + 4; // version + reserved + count
    for (final ch in chapters) {
      size += 8 + 1 + utf8.encode(ch.title).length;
    }
    final payload = Uint8List(size);
    int offset = 0;
    payload[offset++] = 0; // version
    offset += 4; // reserved (zeros)
    // count
    payload[offset++] = (chapters.length >> 24) & 0xFF;
    payload[offset++] = (chapters.length >> 16) & 0xFF;
    payload[offset++] = (chapters.length >> 8) & 0xFF;
    payload[offset++] = chapters.length & 0xFF;
    for (final ch in chapters) {
      // timestamp in 100ns units
      final units100ns = ch.start.inMicroseconds * 10;
      payload[offset++] = (units100ns >> 56) & 0xFF;
      payload[offset++] = (units100ns >> 48) & 0xFF;
      payload[offset++] = (units100ns >> 40) & 0xFF;
      payload[offset++] = (units100ns >> 32) & 0xFF;
      payload[offset++] = (units100ns >> 24) & 0xFF;
      payload[offset++] = (units100ns >> 16) & 0xFF;
      payload[offset++] = (units100ns >> 8) & 0xFF;
      payload[offset++] = units100ns & 0xFF;
      // title: 1-byte length + UTF-8 bytes (capped at 255)
      final titleBytes = utf8.encode(ch.title);
      final titleLen = titleBytes.length > 255 ? 255 : titleBytes.length;
      payload[offset++] = titleLen;
      payload.setRange(offset, offset + titleLen, titleBytes);
      offset += titleLen;
    }
    return payload;
  }

  /// Adds or replaces a chap atom in the audio trak's tref box.
  static Uint8List _addChapAtomToTrak(
      Uint8List trakBytes, int chapterTrackId) {
    // Build chap atom: 4 bytes = track ID as uint32
    final chapContent = Uint8List(4);
    writeUint32BE(chapContent, 0, chapterTrackId);
    final chapBox = _wrapBox('chap', chapContent);

    // Find or create tref inside trak
    final trefIdx = _findBox(trakBytes, 8, trakBytes.length, 'tref');
    final trakDataStart = _dataStartAt(trakBytes, 0, trakBytes.length);
    Uint8List newTrakContent;
    if (trefIdx == null) {
      // Create new tref with chap
      final trefBox = _wrapBox('tref', chapBox);
      newTrakContent = Uint8List.fromList([
        ...trakBytes.sublist(trakDataStart), // existing trak content
        ...trefBox,
      ]);
    } else {
      // Update existing tref: replace or add chap
      final trefData = _dataStartAt(trakBytes, trefIdx.$1, trefIdx.$2);
      final trefContent =
          trakBytes.sublist(trefData, trefIdx.$2);
      final chapIdx = _findBox(trefContent, 0, trefContent.length, 'chap');
      Uint8List newTrefContent;
      if (chapIdx == null) {
        newTrefContent =
            Uint8List.fromList([...trefContent, ...chapBox]);
      } else {
        newTrefContent = _spliceBytes(
            trefContent, chapIdx.$1, chapIdx.$2, chapBox);
      }
      final newTref = _wrapBox('tref', newTrefContent);
      final trakContent = trakBytes.sublist(trakDataStart);
      newTrakContent = Uint8List.fromList(
          _spliceBytes(trakContent, trefData - trakDataStart,
              trefIdx.$2 - trakDataStart, newTref));
    }
    return _wrapBox('trak', newTrakContent);
  }

  /// Finds the chapter track's chunk-offset table (stco or co64) inside
  /// rebuilt moov *children* (no outer moov header) and updates its offsets.
  static void _fixChapterChunkOffsetsInContent(Uint8List children,
      int chapterTrackId, List<int> sampleOffsets, bool isCo64) {
    final bytes = children;
    int pos = 0;
    while (pos + 8 <= bytes.length) {
      final (sz, _) = _boxHeaderAt(bytes, pos, bytes.length);
      if (sz < 8 || pos + sz > bytes.length) break;
      final type = String.fromCharCodes(bytes.sublist(pos + 4, pos + 8));
      if (type == 'trak') {
        final trakEnd = pos + sz;
        // Check if this is the chapter track by track ID
        final tkhdIdx = _findBox(bytes, pos + 8, trakEnd, 'tkhd');
        if (tkhdIdx != null) {
          final tkhdData = _dataStartAt(bytes, tkhdIdx.$1, tkhdIdx.$2);
          final tkhdVersion = bytes[tkhdData];
          final trackId =
              readUint32BE(bytes, tkhdData + (tkhdVersion == 1 ? 20 : 12));
          if (trackId == chapterTrackId) {
            // Found chapter track — fix up its offset table inside stbl
            _walkBoxes(bytes, pos + 8, trakEnd, (btype, bstart, bend) {
              if (isCo64 ? btype == 'co64' : btype == 'stco') {
                final entrySize = isCo64 ? 8 : 4;
                final count = readUint32BE(bytes, bstart + 8 + 4);
                final n = count < sampleOffsets.length
                    ? count
                    : sampleOffsets.length;
                for (int i = 0; i < n; i++) {
                  if (isCo64) {
                    final v = sampleOffsets[i];
                    writeUint32BE(bytes, bstart + 8 + 8 + i * 8,
                        (v >> 32) & 0xFFFFFFFF);
                    writeUint32BE(
                        bytes, bstart + 8 + 12 + i * 8, v & 0xFFFFFFFF);
                  } else {
                    writeUint32BE(bytes, bstart + 8 + 8 + i * entrySize,
                        sampleOffsets[i]);
                  }
                }
              }
            });
            return;
          }
        }
      }
      pos += sz;
    }
  }

  /// Compares two Uint8Lists for equality.
  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ── Metadata rewrite ──────────────────────────────────────────────────────

  static Uint8List _injectTextAtomsInMoov(Uint8List moov, Audiobook book) {
    final atoms = <Uint8List>[
      if (book.title != null && book.title!.isNotEmpty)
        _buildTextAtom('\u00a9alb', book.title!),
      if (book.subtitle != null) _buildTextAtom('\u00a9st3', book.subtitle!),
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

  static SplicePlan? _coverPlan(Uint8List bytes, Uint8List jpeg) {
    final moovIdx = _findBox(bytes, 0, bytes.length, 'moov');
    if (moovIdx == null) return null;

    final moovData = _dataStartAt(bytes, moovIdx.$1, moovIdx.$2);
    final moovContent = bytes.sublist(moovData, moovIdx.$2);
    var newMoovContent =
        _injectCovrInMoov(moovContent, _buildCovrAtom(jpeg));
    newMoovContent = _shiftOffsetsIfMdatFollows(
        bytes, moovIdx.$1, moovIdx.$2, newMoovContent);
    final newMoov = _wrapBox('moov', newMoovContent);
    return SplicePlan(
        replaceStart: moovIdx.$1,
        replaceEnd: moovIdx.$2,
        replacement: newMoov);
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

    final udtaData = _dataStartAt(moov, udtaIdx.$1, udtaIdx.$2);
    final udtaContent = moov.sublist(udtaData, udtaIdx.$2);
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

    final metaDataStart = _dataStartAt(udta, metaIdx.$1, metaIdx.$2);
    final metaInner = udta.sublist(metaDataStart, metaIdx.$2);
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

    final ilstData = _dataStartAt(meta, ilstIdx.$1, ilstIdx.$2);
    final ilstContent = meta.sublist(ilstData, ilstIdx.$2);
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
      final (sz, _) = _boxHeaderAt(ilst, pos, ilst.length);
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
    // UTF-8 encode — the data atom's type flags (below) declare UTF-8, and
    // using .codeUnits here would write raw UTF-16 code units as bytes.
    final textBytes = Uint8List.fromList(utf8.encode(value));
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
      final (sz, hdrSize) = _boxHeaderAt(bytes, pos, end);
      if (sz < 8 || pos + sz > end) break;
      final type = String.fromCharCodes(bytes.sublist(pos + 4, pos + 8));
      visitor(type, pos, pos + sz);
      if (const {'moov', 'trak', 'mdia', 'minf', 'stbl', 'udta'}
          .contains(type)) {
        _walkBoxes(bytes, pos + hdrSize, pos + sz, visitor);
      }
      pos += sz;
    }
  }

  // ── Box utilities (also used by tests) ───────────────────────────────────

  static (int, int)? _findBox(
      Uint8List bytes, int start, int end, String type) {
    int pos = start;
    while (pos + 8 <= end) {
      final (sz, _) = _boxHeaderAt(bytes, pos, end);
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
