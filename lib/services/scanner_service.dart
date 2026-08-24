import 'dart:io';
import 'dart:typed_data';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:audiovault_editor/models/audiobook.dart';
import 'package:audiovault_editor/services/app_logger.dart';
import 'package:audiovault_editor/services/cue_sheet_parser.dart';
import 'package:audiovault_editor/services/m4b_chapter_reader.dart';
import 'package:audiovault_editor/services/opf_parser.dart';

class ScannerService {
  static const _audioExtensions = {'.mp3', '.m4a', '.aac', '.m4b', '.flac', '.ogg'};
  static const _imageExtensions = {'.jpg', '.jpeg', '.png', '.webp'};
  static const int maxScanDepth = 3;

  /// How many book folders are scanned concurrently.
  static const int scanConcurrency = 4;

  /// Non-fatal problems collected during the most recent public scan call.
  final List<String> lastRunWarnings = [];

  void _warn(String message) {
    AppLog.w(message);
    lastRunWarnings.add(message);
  }

  /// Re-scans a single book folder and returns the updated [Audiobook], or
  /// null if no audio files were found.
  Future<Audiobook?> scanBook(String folderPath) {
    lastRunWarnings.clear();
    return _scanSubfolder(Directory(folderPath));
  }

  /// Recursively scans [folderPath] for books.
  ///
  /// [cancelled] is polled between folders; when it returns true the scan
  /// stops early and returns the books found so far. Up to
  /// [scanConcurrency] subfolders are processed concurrently.
  Future<List<Audiobook>> scanFolder(String folderPath,
      {void Function(Audiobook)? onBookFound,
      void Function(int found, int total)? onProgress,
      bool Function()? cancelled}) async {
    lastRunWarnings.clear();
    final dir = Directory(folderPath);
    if (!await dir.exists()) {
      _warn('Library folder does not exist: $folderPath');
      return [];
    }

    List<FileSystemEntity> entries;
    try {
      entries = await dir.list().toList();
    } catch (e) {
      _warn('Could not read library folder "$folderPath": $e');
      return [];
    }
    final subdirs = entries
        .whereType<Directory>()
        .where((d) => !p.basename(d.path).startsWith('.'))
        .toList();

    final total = subdirs.length;
    final books = <Audiobook>[];
    for (int i = 0; i < subdirs.length; i += scanConcurrency) {
      if (cancelled?.call() ?? false) break;
      final batchEnd = (i + scanConcurrency).clamp(0, subdirs.length);
      final results = await Future.wait(
        [for (int j = i; j < batchEnd; j++) _scanAsBookOrAuthorFolder(subdirs[j])],
      );
      for (final folderResults in results) {
        for (final book in folderResults) {
          onBookFound?.call(book);
        }
        books.addAll(folderResults);
      }
      onProgress?.call(books.length, total);
    }

    if (!(cancelled?.call() ?? false)) {
      final rootBook = await _scanSubfolder(dir);
      if (rootBook != null) {
        onBookFound?.call(rootBook);
        books.add(rootBook);
      }
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
    } catch (e) {
      _warn('Could not read folder "${dir.path}": $e');
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
    } catch (e) {
      _warn('Could not read folder "${dir.path}": $e');
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

    // CUE sheet â€” only used for file ordering and chapter timestamps
    CueSheet? cueSheet;
    final cueFiles = allFiles
        .where((f) => p.extension(f.path).toLowerCase() == '.cue')
        .toList();
    if (cueFiles.isNotEmpty) {
      try {
        cueSheet =
            parseCueSheet(await cueFiles.first.readAsString(), dir.path);
      } catch (e) {
        _warn('Unreadable CUE sheet in "${dir.path}": $e');
      }
    }
    if (cueSheet != null && cueSheet.audioFiles.isNotEmpty) {
      audioFiles..clear()..addAll(cueSheet.audioFiles);
    }

    if (audioFiles.isEmpty) return null;

    // â”€â”€ Read raw file tags off the UI thread â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
    final chapterDurations = <Duration>[];

    final coverPath = _pickBestCover(imageFiles);

    if (audioFiles.isNotEmpty) {
      final metaResult = await compute(_readAudioMetaJob,
          (files: audioFiles, wantArt: coverPath == null));
      chapterDurations.addAll(metaResult.durations);
      coverBytes = metaResult.coverBytes;

      final raw = await compute(_readExtendedTagsJob, audioFiles.first);
      fileTitle = raw.$1;
      fileAuthor = raw.$2;
      fileNarrator = raw.$3;
      fileSubtitle = raw.$4;
      fileReleaseDate = raw.$5;
      fileDescription = raw.$6;
      filePublisher = raw.$7;
      fileLanguage = raw.$8;
      fileGenre = raw.$9;
    }

    // â”€â”€ OPF â€” wins over file tags for all mapped fields â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    OpfMetadata opf = const OpfMetadata();
    bool hasOpf = false;
    final opfFile = allFiles
        .where((f) => p.basename(f.path).toLowerCase() == 'metadata.opf')
        .firstOrNull;
    if (opfFile != null) {
      try {
        opf = parseOpf(await opfFile.readAsString());
        hasOpf = true;
      } catch (e) {
        _warn('Could not parse metadata.opf in "${dir.path}": $e');
      }
    }

    final title = opf.title ?? fileTitle;
    final author = opf.author ?? fileAuthor;
    final narrator = opf.narrator ?? fileNarrator;
    final subtitle = opf.subtitle ?? fileSubtitle;
    final releaseDate = opf.releaseDate ?? fileReleaseDate;
    final description = opf.description ?? fileDescription;
    final publisher = opf.publisher ?? filePublisher;
    final language = opf.language ?? fileLanguage;
    final genre = opf.genre ?? fileGenre;
    final identifier = opf.identifier;

    // â”€â”€ Chapters â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    List<Chapter> chapters = const [];
    if (audioFiles.length == 1 &&
        p.extension(audioFiles.first).toLowerCase() == '.m4b') {
      chapters = await parseM4bChapters(audioFiles.first);
    } else if (cueSheet != null && cueSheet.chapters.isNotEmpty) {
      chapters = cueSheet.chapters;
    }

    // Multi-file chapter names: use filename without extension â€” no heuristics
    final chapterNames = audioFiles.length > 1
        ? audioFiles.map((f) => p.basenameWithoutExtension(f)).toList()
        : const <String>[];

    final hasEmbeddedTags = fileTitle != null || fileAuthor != null;
    final hasCue = cueSheet != null;

    final readOnlyStatus = await _checkReadOnlyStatus(dir, audioFiles);

    final totalDuration = chapterDurations.fold<Duration>(
        Duration.zero, (sum, d) => sum + d);

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
      readOnlyStatus: readOnlyStatus,
      fileTitleRaw: fileTitle,
      fileAuthorRaw: fileAuthor,
      fileNarratorRaw: fileNarrator,
      fileReleaseDateRaw: fileReleaseDate,
      fileSubtitleRaw: fileSubtitle,
    );
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

  /// Public wrapper for testing — delegates to [_checkReadOnlyStatus].
  // ignore: invalid_use_of_visible_for_testing_member
  @visibleForTesting
  Future<ReadOnlyStatus> checkReadOnlyStatusForTesting(
          Directory dir, List<String> audioFiles) =>
      _checkReadOnlyStatus(dir, audioFiles);

  /// Checks whether [dir] and each file in [audioFiles] are writable by the
  /// current OS user without modifying any data on disk.
  ///
  /// - Folder writability is probed by creating a temporary directory inside
  ///   [dir] and immediately deleting it.  If that throws, the folder is
  ///   considered read-only.
  /// - File writability is probed by opening each file in append mode and
  ///   immediately closing it without writing any bytes.  If that throws, the
  ///   file is considered read-only.
  ///
  /// Returns [ReadOnlyStatus.folderReadOnly] when the folder is not writable,
  /// [ReadOnlyStatus.filesReadOnly] when the folder is writable but at least
  /// one audio file is not, and [ReadOnlyStatus.writable] when everything is
  /// writable.
  Future<ReadOnlyStatus> _checkReadOnlyStatus(
      Directory dir, List<String> audioFiles) async {
    // â”€â”€ Probe folder writability â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    bool folderWritable = false;
    try {
      final tmp = await dir.createTemp('.kiro_probe_');
      await tmp.delete();
      folderWritable = true;
    } catch (e) {
      AppLog.d('Folder write probe failed for "${dir.path}": $e');
      folderWritable = false;
    }

    if (!folderWritable) return ReadOnlyStatus.folderReadOnly;

    // â”€â”€ Probe each audio file â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    for (final filePath in audioFiles) {
      bool fileWritable = false;
      try {
        final sink = File(filePath).openWrite(mode: FileMode.append);
        await sink.flush();
        await sink.close();
        fileWritable = true;
      } catch (e) {
        AppLog.d('File write probe failed for "$filePath": $e');
        fileWritable = false;
      }
      if (!fileWritable) return ReadOnlyStatus.filesReadOnly;
    }

    return ReadOnlyStatus.writable;
  }

  bool _isAudio(String path) => _audioExtensions.contains(p.extension(path).toLowerCase());
  bool _isImage(String path) => _imageExtensions.contains(p.extension(path).toLowerCase());

  // â”€â”€ Isolate jobs (tag parsing is CPU-heavy and must not jank the UI) â”€â”€â”€â”€â”€

  /// Reads duration + embedded art for every audio file. Runs inside an
  /// isolate via [compute].
  static ({List<Duration> durations, Uint8List? coverBytes}) _readAudioMetaJob(
      ({List<String> files, bool wantArt}) msg) {
    final durations = <Duration>[];
    Uint8List? coverBytes;
    var needArt = msg.wantArt;
    for (final filePath in msg.files) {
      try {
        final meta = readMetadata(File(filePath), getImage: needArt); // ignore: avoid_redundant_argument_values - value is dynamic
        durations.add(meta.duration ?? Duration.zero);
        if (needArt && meta.pictures.isNotEmpty) {
          coverBytes = meta.pictures.first.bytes;
          needArt = false;
        }
      } catch (e) {
        AppLog.d('Could not read metadata from "$filePath": $e');
        durations.add(Duration.zero);
      }
    }
    return (durations: durations, coverBytes: coverBytes);
  }

  /// Reads extended tags from the first audio file. Runs inside an isolate.
  static (
    String? title,
    String? author,
    String? narrator,
    String? subtitle,
    String? releaseDate,
    String? description,
    String? publisher,
    String? language,
    String? genre,
  ) _readExtendedTagsJob(String filePath) {
    try {
      final raw =
          readAllMetadata(File(filePath), getImage: false); // ignore: avoid_redundant_argument_values - explicit false is clearer
      if (raw is Mp3Metadata) {
        return (
          raw.album?.trim().nullIfEmpty,
          raw.leadPerformer?.trim().nullIfEmpty,
          raw.bandOrOrchestra?.trim().nullIfEmpty,
          raw.subtitle?.trim().nullIfEmpty,
          raw.year != null && raw.year! > 0 ? raw.year.toString() : null,
          raw.comments.firstOrNull?.text.trim().nullIfEmpty,
          raw.publisher?.trim().nullIfEmpty,
          raw.languages?.trim().nullIfEmpty,
          raw.contentType?.trim().nullIfEmpty,
        );
      } else if (raw is Mp4Metadata) {
        // Note: Mp4Metadata does not expose composer (Â©wrt) atom.
        // Narrator for M4B files is read from OPF when present.
        return (
          raw.album?.trim().nullIfEmpty,
          raw.artist?.trim().nullIfEmpty,
          null,
          null,
          raw.year?.year != null ? raw.year!.year.toString() : null,
          null,
          null,
          null,
          raw.genre?.trim().nullIfEmpty,
        );
      } else if (raw is VorbisMetadata) {
        final yr = raw.date.firstOrNull?.year;
        return (
          raw.album.firstOrNull?.trim().nullIfEmpty,
          raw.artist.firstOrNull?.trim().nullIfEmpty,
          raw.performer.firstOrNull?.trim().nullIfEmpty,
          null,
          yr != null && yr > 0 ? yr.toString() : null,
          raw.description.firstOrNull?.trim().nullIfEmpty ??
              raw.comment.firstOrNull?.trim().nullIfEmpty,
          raw.organization.firstOrNull?.trim().nullIfEmpty,
          null,
          raw.genres.firstOrNull?.trim().nullIfEmpty,
        );
      }
    } catch (e) {
      AppLog.d('Could not read extended tags from "$filePath": $e');
    }
    return (null, null, null, null, null, null, null, null, null);
  }
}

extension _StringExt on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
