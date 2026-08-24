/// Immutable value object representing one chapter row.
///
/// Lives in the model layer (not widgets) so services such as [CueWriter]
/// can depend on it without importing UI code.
class ChapterEntry {
  final String title;
  final Duration start;

  const ChapterEntry({required this.title, required this.start});

  ChapterEntry copyWith({String? title, Duration? start}) => ChapterEntry(
        title: title ?? this.title,
        start: start ?? this.start,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChapterEntry &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          start == other.start;

  @override
  int get hashCode => title.hashCode ^ start.hashCode;

  @override
  String toString() => 'ChapterEntry(title: $title, start: $start)';
}
