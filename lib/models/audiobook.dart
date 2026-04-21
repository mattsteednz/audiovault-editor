import 'dart:typed_data';

class Chapter {
  final String title;
  final Duration start;

  const Chapter({required this.title, required this.start});

  Chapter copyWith({String? title, Duration? start}) =>
      Chapter(title: title ?? this.title, start: start ?? this.start);
}

class Audiobook {
  final String? title;
  final String? author;
  final Duration? duration;
  final String path;
  final String? coverImagePath;
  final Uint8List? coverImageBytes;
  final List<String> audioFiles;
  final List<Duration> chapterDurations;
  final List<Chapter> chapters;
  final List<String> chapterNames;
  final String? narrator;
  final String? subtitle;
  final String? description;
  final String? publisher;
  final String? language;
  final String? genre;
  final String? identifier;
  final String? releaseDate;
  final String? series;
  final int? seriesIndex;
  final String? pendingCoverPath;
  final List<String> additionalAuthors;
  final List<String> additionalNarrators;
  final Map<String, String> opfMeta;

  /// Raw values read directly from audio file tags, before OPF override.
  final String? fileTitleRaw;
  final String? fileAuthorRaw;
  final String? fileNarratorRaw;
  final String? fileReleaseDateRaw;
  final String? fileSubtitleRaw;

  const Audiobook({
    this.title,
    this.author,
    this.duration,
    required this.path,
    this.coverImagePath,
    this.coverImageBytes,
    required this.audioFiles,
    this.chapterDurations = const [],
    this.chapters = const [],
    this.chapterNames = const [],
    this.narrator,
    this.subtitle,
    this.description,
    this.publisher,
    this.language,
    this.genre,
    this.identifier,
    this.releaseDate,
    this.series,
    this.seriesIndex,
    this.pendingCoverPath,
    this.additionalAuthors = const [],
    this.additionalNarrators = const [],
    this.opfMeta = const {},
    this.fileTitleRaw,
    this.fileAuthorRaw,
    this.fileNarratorRaw,
    this.fileReleaseDateRaw,
    this.fileSubtitleRaw,
  });

  // Sentinel used to distinguish "not passed" from "explicitly null".
  static const Object _unset = Object();

  Audiobook copyWith({
    Object? title = _unset,
    Object? author = _unset,
    Object? narrator = _unset,
    Object? subtitle = _unset,
    Object? releaseDate = _unset,
    Object? coverImagePath = _unset,
    Object? coverImageBytes = _unset,
    Object? series = _unset,
    Object? seriesIndex = _unset,
    Object? description = _unset,
    Object? publisher = _unset,
    Object? language = _unset,
    Object? genre = _unset,
    Object? identifier = _unset,
    Object? duration = _unset,
    List<Chapter>? chapters,
    List<String>? chapterNames,
    List<String>? audioFiles,
    List<Duration>? chapterDurations,
    Object? pendingCoverPath = _unset,
    Object? fileTitleRaw = _unset,
    Object? fileAuthorRaw = _unset,
    Object? fileNarratorRaw = _unset,
    Object? fileReleaseDateRaw = _unset,
    Object? fileSubtitleRaw = _unset,
    List<String>? additionalAuthors,
    List<String>? additionalNarrators,
    Map<String, String>? opfMeta,
  }) =>
      Audiobook(
        title: title == _unset ? this.title : title as String?,
        author: author == _unset ? this.author : author as String?,
        duration: duration == _unset ? this.duration : duration as Duration?,
        path: path,
        coverImagePath: coverImagePath == _unset
            ? this.coverImagePath
            : coverImagePath as String?,
        coverImageBytes: coverImageBytes == _unset
            ? this.coverImageBytes
            : coverImageBytes as Uint8List?,
        audioFiles: audioFiles ?? this.audioFiles,
        chapterDurations: chapterDurations ?? this.chapterDurations,
        chapters: chapters ?? this.chapters,
        chapterNames: chapterNames ?? this.chapterNames,
        narrator: narrator == _unset ? this.narrator : narrator as String?,
        subtitle: subtitle == _unset ? this.subtitle : subtitle as String?,
        description:
            description == _unset ? this.description : description as String?,
        publisher: publisher == _unset ? this.publisher : publisher as String?,
        language: language == _unset ? this.language : language as String?,
        genre: genre == _unset ? this.genre : genre as String?,
        identifier: identifier == _unset ? this.identifier : identifier as String?,
        releaseDate:
            releaseDate == _unset ? this.releaseDate : releaseDate as String?,
        series: series == _unset ? this.series : series as String?,
        seriesIndex:
            seriesIndex == _unset ? this.seriesIndex : seriesIndex as int?,
        pendingCoverPath: pendingCoverPath == _unset
            ? this.pendingCoverPath
            : pendingCoverPath as String?,
        additionalAuthors: additionalAuthors ?? this.additionalAuthors,
        additionalNarrators: additionalNarrators ?? this.additionalNarrators,
        opfMeta: opfMeta ?? this.opfMeta,
        fileTitleRaw:
            fileTitleRaw == _unset ? this.fileTitleRaw : fileTitleRaw as String?,
        fileAuthorRaw: fileAuthorRaw == _unset
            ? this.fileAuthorRaw
            : fileAuthorRaw as String?,
        fileNarratorRaw: fileNarratorRaw == _unset
            ? this.fileNarratorRaw
            : fileNarratorRaw as String?,
        fileReleaseDateRaw: fileReleaseDateRaw == _unset
            ? this.fileReleaseDateRaw
            : fileReleaseDateRaw as String?,
        fileSubtitleRaw: fileSubtitleRaw == _unset
            ? this.fileSubtitleRaw
            : fileSubtitleRaw as String?,
      );
}
