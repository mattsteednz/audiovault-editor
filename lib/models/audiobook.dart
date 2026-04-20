import 'dart:typed_data';

class Chapter {
  final String title;
  final Duration start;

  const Chapter({required this.title, required this.start});

  Chapter copyWith({String? title, Duration? start}) =>
      Chapter(title: title ?? this.title, start: start ?? this.start);
}

class Audiobook {
  final String title;
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
  final String? description;
  final String? publisher;
  final String? language;
  final String? releaseDate;
  final String? series;
  final int? seriesIndex;
  /// Path to a newly dropped cover image, not yet written to disk.
  final String? pendingCoverPath;

  const Audiobook({
    required this.title,
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
    this.description,
    this.publisher,
    this.language,
    this.releaseDate,
    this.series,
    this.seriesIndex,
    this.pendingCoverPath,
  });

  Audiobook copyWith({
    String? title,
    String? author,
    String? narrator,
    String? releaseDate,
    String? coverImagePath,
    List<Chapter>? chapters,
    List<String>? chapterNames,
    String? pendingCoverPath,
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
        description: description,
        publisher: publisher,
        language: language,
        releaseDate: releaseDate ?? this.releaseDate,
        series: series,
        seriesIndex: seriesIndex,
        pendingCoverPath: pendingCoverPath ?? this.pendingCoverPath,
      );
}
