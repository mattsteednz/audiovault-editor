import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;
import 'package:audiovault_editor/models/audiobook.dart';
import 'package:audiovault_editor/services/opf_parser.dart';

class _CueSheet {
  final String? title;
  final String? author;
  final List<String> audioFiles;
  final List<Chapter> chapters;

  const _CueSheet({
    this.title,
    this.author,
    required this.audioFiles,
    required this.chapters,
  });
}

class ScannerService {
  static const _audioExtensions = {'.mp3', '.m4a', '.aac', '.m4b', '.flac', '.ogg'};
  static const _imageExtensions = {'.jpg', '.jpeg', '.png', '.webp'};
  static const int maxScanDepth = 3;

  /// Re-scans a single book folder and returns the updated [Audiobook], or
  /// null if no audio files were found.
  Future<Audiobook?> scanBook(String folderPath) =>
      _scanSubfolder(Directory(folderPath));

  Future<List<Audiobook>> scanFolder(String folderPath,
      {void Function(Audiobook)? onBookFound}) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return [];

    final entries = await dir.list().toList();
    final subdirs = entries
        .whereType<Directory>()
        .where((d) => !p.basename(d.path).startsWith('.'))
        .toList();

    final books = <Audiobook>[];
    for (final subdir in subdirs) {
      final results = await _scanAsBookOrAuthorFolder(subdir);
      for (final book in results) {
        onBookFound?.call(book);
      }
      books.addAll(results);
    }

    final rootBook = await _scanSubfolder(dir);
    if (rootBook != null) {
      onBookFound?.call(rootBook);
      books.add(rootBook);
    }

    books.sort((a, b) {
      final at = a.title ?? '';
      final bt = b.title ?? '';
      return at.toLowerCase().compareTo(bt.toLowerCase());
    });
    return books;
  }

  Future<List<Audiobook>> _scanAsBookOrAuthorFolder(Directory dir,
      {int remainingDepth = maxScanDepth - 1}) async {
    final book = await _scanSubfolder(dir);
    if (book != null) return [book];
    if (remainingDepth <= 0) return const [];

    List<FileSystemEntity> entries;
    try {
      entries = await dir.list().toList();
    } catch (_) {
      return const [];
    }
    final subdirs = entries
        .whereType<Directory>()
        .where((d) => !p.basename(d.path).startsWith('.'))
        .toList();
    if (subdirs.isEmpty) return const [];

    final books = <Audiobook>[];
    for (final sub in subdirs) {
      books.addAll(await _scanAsBookOrAuthorFolder(sub,
          remainingDepth: remainingDepth - 1));
    }
    return books;
  }

  Future<Audiobook?> _scanSubfolder(Directory dir) async {
    List<FileSystemEntity> entries;
    try {
      entries = await dir.list().toList();
    } catch (_) {
      return null;
    }

    final allFiles = entries
        .whereType<File>()
        .where((f) => !p.basename(f.path).startsWith('.'))
        .toList();
    final audioFiles = allFiles
        .where((f) => _isAudio(f.path))
        .map((f) => f.path)
        .toList()
      ..sort(naturalSortCompare);
    final imageFiles = allFiles.where((f) => _isImage(f.path)).toList();

    // CUE sheet — only used for file ordering and chapter timestamps
    _CueSheet? cueSheet;
    final cueFiles = allFiles
        .where((f) => p.extension(f.path).toLowerCase() == '.cue')
        .toList();
    if (cueFiles.isNotEmpty) {
      try {
        cueSheet = _parseCueSheet(await cueFiles.first.readAsString(), dir.path);
      } catch (_) {}
    }
    if (cueSheet != null && cueSheet.audioFiles.isNotEmpty) {
      audioFiles..clear()..addAll(cueSheet.audioFiles);
    }

    if (audioFiles.isEmpty) return null;

    // ── Read raw file tags from the first audio file ──────────────────────
    String? fileTitle;
    String? fileAuthor;
    String? fileNarrator;
    String? fileSubtitle;
    String? fileReleaseDate;
    String? fileDescription;
    String? filePublisher;
    String? fileLanguage;
    String? fileGenre;
    Uint8List? coverBytes;
    Duration totalDuration = Duration.zero;
    final chapterDurations = <Duration>[];

    final coverPath = _pickBestCover(imageFiles);

    for (final filePath in audioFiles) {
      try {
        final needArt = coverPath == null && coverBytes == null;
        final meta = readMetadata(File(filePath), getImage: needArt); // ignore: avoid_redundant_argument_values - value is dynamic
        chapterDurations.add(meta.duration ?? Duration.zero);
        totalDuration += meta.duration ?? Duration.zero;
        if (needArt && meta.pictures.isNotEmpty) {
          coverBytes = meta.pictures.first.bytes;
        }
      } catch (_) {
        chapterDurations.add(Duration.zero);
      }
    }

    // Read extended tags from first file only
    if (audioFiles.isNotEmpty) {
      try {
        final raw = readAllMetadata(File(audioFiles.first), getImage: false); // ignore: avoid_redundant_argument_values - explicit false is clearer
        if (raw is Mp3Metadata) {
          fileTitle = raw.album?.trim().nullIfEmpty;
          fileAuthor = raw.leadPerformer?.trim().nullIfEmpty;
          fileNarrator = raw.bandOrOrchestra?.trim().nullIfEmpty;
          fileSubtitle = raw.subtitle?.trim().nullIfEmpty;
          fileReleaseDate = raw.year != null && raw.year! > 0
              ? raw.year.toString()
              : null;
          fileDescription = raw.comments.firstOrNull?.text.trim().nullIfEmpty;
          filePublisher = raw.publisher?.trim().nullIfEmpty;
          fileLanguage = raw.languages?.trim().nullIfEmpty;
          fileGenre = raw.contentType?.trim().nullIfEmpty;
        } else if (raw is Mp4Metadata) {
          fileTitle = raw.album?.trim().nullIfEmpty;
          fileAuthor = raw.artist?.trim().nullIfEmpty;
          fileReleaseDate = raw.year?.year != null ? raw.year!.year.toString() : null;
          fileGenre = raw.genre?.trim().nullIfEmpty;
        } else if (raw is VorbisMetadata) {
          fileTitle = raw.album.firstOrNull?.trim().nullIfEmpty;
          fileAuthor = raw.artist.firstOrNull?.trim().nullIfEmpty;
          fileNarrator = raw.performer.firstOrNull?.trim().nullIfEmpty;
          fileDescription = raw.description.firstOrNull?.trim().nullIfEmpty
              ?? raw.comment.firstOrNull?.trim().nullIfEmpty;
          filePublisher = raw.organization.firstOrNull?.trim().nullIfEmpty;
          final yr = raw.date.firstOrNull?.year;
          if (yr != null && yr > 0) fileReleaseDate = yr.toString();
          fileGenre = raw.genres.firstOrNull?.trim().nullIfEmpty;
        }
      } catch (_) {}
    }

    // ── OPF — wins over file tags for all mapped fields ───────────────────
    OpfMetadata opf = const OpfMetadata();
    bool hasOpf = false;
    final opfFile = allFiles
        .where((f) => p.basename(f.path).toLowerCase() == 'metadata.opf')
        .firstOrNull;
    if (opfFile != null) {
      try {
        opf = parseOpf(await opfFile.readAsString());
        hasOpf = true;
      } catch (_) {}
    }

    final title = opf.title ?? fileTitle;
    final author = opf.author ?? fileAuthor;
    final narrator = opf.narrator ?? fileNarrator;
    final subtitle = fileSubtitle;
    final releaseDate = opf.releaseDate ?? fileReleaseDate;
    final description = opf.description ?? fileDescription;
    final publisher = opf.publisher ?? filePublisher;
    final language = opf.language ?? fileLanguage;
    final genre = opf.genre ?? fileGenre;
    final identifier = opf.identifier;

    // ── Chapters ──────────────────────────────────────────────────────────
    List<Chapter> chapters = const [];
    if (audioFiles.length == 1 &&
        p.extension(audioFiles.first).toLowerCase() == '.m4b') {
      chapters = await _parseM4bChapters(audioFiles.first);
    } else if (cueSheet != null && cueSheet.chapters.isNotEmpty) {
      chapters = cueSheet.chapters;
    }

    // Multi-file chapter names: use filename without extension — no heuristics
    final chapterNames = audioFiles.length > 1
        ? audioFiles.map((f) => p.basenameWithoutExtension(f)).toList()
        : const <String>[];

    final hasEmbeddedTags = fileTitle != null || fileAuthor != null;
    final hasCue = cueSheet != null;

    return Audiobook(
      title: title,
      author: author,
      duration: totalDuration == Duration.zero ? null : totalDuration,
      path: dir.path,
      coverImagePath: coverPath,
      coverImageBytes: coverBytes,
      audioFiles: audioFiles,
      chapterDurations: chapterDurations,
      chapters: chapters,
      chapterNames: chapterNames,
      narrator: narrator,
      subtitle: subtitle,
      description: description,
      publisher: publisher,
      language: language,
      genre: genre,
      identifier: identifier,
      releaseDate: releaseDate,
      series: opf.series,
      seriesIndex: opf.seriesIndex,
      additionalAuthors: opf.additionalAuthors,
      additionalNarrators: opf.additionalNarrators,
      opfMeta: opf.opfMeta,
      hasOpf: hasOpf,
      hasCue: hasCue,
      hasEmbeddedTags: hasEmbeddedTags,
      fileTitleRaw: fileTitle,
      fileAuthorRaw: fileAuthor,
      fileNarratorRaw: fileNarrator,
      fileReleaseDateRaw: fileReleaseDate,
      fileSubtitleRaw: fileSubtitle,
    );
  }

  // ── M4B chapter parsing ───────────────────────────────────────────────────

  Future<List<Chapter>> _parseM4bChapters(String filePath) async {
    try {
      return await _parseM4bChaptersInner(filePath)
          .timeout(const Duration(seconds: 10), onTimeout: () => const []);
    } catch (_) {
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
    } catch (_) {
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

  String? _pickBestCover(List<File> images) {
    if (images.isEmpty) return null;
    for (final file in images) {
      final name = p.basename(file.path);
      if (name == 'cover.jpg' || name == 'Cover.jpg') return file.path;
    }
    for (final file in images) {
      if (p.basenameWithoutExtension(file.path).toLowerCase().contains('cover')) {
        return file.path;
      }
    }
    return images.first.path;
  }

  /// Public static comparator for testing.
  static int naturalSortCompare(String a, String b) {
    final nameA = p.basename(a).toLowerCase();
    final nameB = p.basename(b).toLowerCase();
    final re = RegExp(r'(\d+)|(\D+)');
    final segA = re.allMatches(nameA).toList();
    final segB = re.allMatches(nameB).toList();
    final len = segA.length < segB.length ? segA.length : segB.length;
    for (var i = 0; i < len; i++) {
      final sa = segA[i].group(0)!;
      final sb = segB[i].group(0)!;
      final na = int.tryParse(sa);
      final nb = int.tryParse(sb);
      final cmp = (na != null && nb != null) ? na.compareTo(nb) : sa.compareTo(sb);
      if (cmp != 0) return cmp;
    }
    return segA.length.compareTo(segB.length);
  }

  _CueSheet? _parseCueSheet(String content, String folderPath) {
    String? globalTitle;
    String? globalPerformer;
    final fileSections = <({String path, List<Chapter> chapters})>[];
    String? currentFilePath;
    final pendingChapters = <Chapter>[];
    String? pendingTrackTitle;

    void commitFile() {
      if (currentFilePath != null) {
        fileSections.add((path: currentFilePath!, chapters: List.of(pendingChapters)));
      }
      pendingChapters.clear();
      currentFilePath = null;
      pendingTrackTitle = null;
    }

    for (var line in content.split('\n')) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('REM')) continue;
      if (line.startsWith('FILE ')) {
        commitFile();
        final match = RegExp(r'^FILE\s+"(.+?)"\s+\S+').firstMatch(line) ??
            RegExp(r'^FILE\s+(\S+)\s+\S+').firstMatch(line);
        if (match == null) continue;
        final filename = match.group(1)!.replaceAll('\\', p.separator);
        final resolved = p.join(folderPath, filename);
        currentFilePath = File(resolved).existsSync() ? resolved : null;
      } else if (line.startsWith('TITLE ')) {
        final title = _cueUnquote(line.substring(6));
        if (currentFilePath == null && fileSections.isEmpty) {
          globalTitle = title;
        } else {
          pendingTrackTitle = title;
        }
      } else if (line.startsWith('PERFORMER ')) {
        final performer = _cueUnquote(line.substring(10));
        if (currentFilePath == null && fileSections.isEmpty) globalPerformer = performer;
      } else if (line.startsWith('INDEX 01 ') && pendingTrackTitle != null) {
        final dur = _parseCueTime(line.substring(9).trim());
        if (dur != null && currentFilePath != null) {
          pendingChapters.add(Chapter(title: pendingTrackTitle!, start: dur));
        }
        pendingTrackTitle = null;
      }
    }
    commitFile();
    if (fileSections.isEmpty) return null;
    return _CueSheet(
      title: globalTitle,
      author: globalPerformer,
      audioFiles: fileSections.map((s) => s.path).toList(),
      chapters: fileSections.length == 1 ? fileSections.first.chapters : const [],
    );
  }

  String _cueUnquote(String s) {
    s = s.trim();
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }

  Duration? _parseCueTime(String s) {
    final parts = s.split(':');
    if (parts.length != 3) return null;
    final mm = int.tryParse(parts[0]);
    final ss = int.tryParse(parts[1]);
    final ff = int.tryParse(parts[2]);
    if (mm == null || ss == null || ff == null) return null;
    return Duration(milliseconds: mm * 60000 + ss * 1000 + ff * 1000 ~/ 75);
  }

  bool _isAudio(String path) => _audioExtensions.contains(p.extension(path).toLowerCase());
  bool _isImage(String path) => _imageExtensions.contains(p.extension(path).toLowerCase());
}

extension _StringExt on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
