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
  final String? releaseDate;
  final String? series;
  final int? seriesIndex;
  final String? pendingCoverPath;

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
    this.releaseDate,
    this.series,
    this.seriesIndex,
    this.pendingCoverPath,
    this.fileTitleRaw,
    this.fileAuthorRaw,
    this.fileNarratorRaw,
    this.fileReleaseDateRaw,
    this.fileSubtitleRaw,
  });

  Audiobook copyWith({
    String? title,
    String? author,
    String? narrator,
    String? subtitle,
    String? releaseDate,
    String? coverImagePath,
    String? series,
    int? seriesIndex,
    String? description,
    List<Chapter>? chapters,
    List<String>? chapterNames,
    String? pendingCoverPath,
    String? fileTitleRaw,
    String? fileAuthorRaw,
    String? fileNarratorRaw,
    String? fileReleaseDateRaw,
    String? fileSubtitleRaw,
  }) =>
      Audiobook(
        title: title ?? this.title,
        author: author ?? this.author,
        duration: duration,
        path: path,
        coverImagePath: coverImagePath ?? this.coverImagePath,
        coverImageBytes: coverImageBytes,
        audioFiles: audioFiles,
        chapterDurations: chapterDurations,
        chapters: chapters ?? this.chapters,
        chapterNames: chapterNames ?? this.chapterNames,
        narrator: narrator ?? this.narrator,
        subtitle: subtitle ?? this.subtitle,
        description: description ?? this.description,
        publisher: publisher,
        language: language,
        releaseDate: releaseDate ?? this.releaseDate,
        series: series ?? this.series,
        seriesIndex: seriesIndex ?? this.seriesIndex,
        pendingCoverPath: pendingCoverPath ?? this.pendingCoverPath,
        fileTitleRaw: fileTitleRaw ?? this.fileTitleRaw,
        fileAuthorRaw: fileAuthorRaw ?? this.fileAuthorRaw,
        fileNarratorRaw: fileNarratorRaw ?? this.fileNarratorRaw,
        fileReleaseDateRaw: fileReleaseDateRaw ?? this.fileReleaseDateRaw,
        fileSubtitleRaw: fileSubtitleRaw ?? this.fileSubtitleRaw,
      );
}
