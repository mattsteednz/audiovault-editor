import 'package:flutter_test/flutter_test.dart';
import 'package:audiovault_editor/models/audiobook.dart';

void main() {
  const base = Audiobook(
    path: '/books/test',
    audioFiles: ['/books/test/track.mp3'],
    title: 'Original Title',
    author: 'Original Author',
    narrator: 'Original Narrator',
    publisher: 'Original Publisher',
    language: 'en',
    series: 'My Series',
    seriesIndex: 1,
    releaseDate: '2020',
    description: 'A description',
    subtitle: 'A subtitle',
  );

  group('Audiobook.copyWith', () {
    test('returns identical values when nothing is passed', () {
      final copy = base.copyWith();
      expect(copy.title, base.title);
      expect(copy.author, base.author);
      expect(copy.narrator, base.narrator);
      expect(copy.publisher, base.publisher);
      expect(copy.language, base.language);
      expect(copy.series, base.series);
      expect(copy.seriesIndex, base.seriesIndex);
      expect(copy.releaseDate, base.releaseDate);
      expect(copy.description, base.description);
      expect(copy.subtitle, base.subtitle);
      expect(copy.path, base.path);
      expect(copy.audioFiles, base.audioFiles);
    });

    test('updates a field when a new value is passed', () {
      final copy = base.copyWith(title: 'New Title');
      expect(copy.title, 'New Title');
      expect(copy.author, base.author);
    });

    test('can explicitly clear a nullable String field to null', () {
      final copy = base.copyWith(publisher: null);
      expect(copy.publisher, isNull);
      expect(copy.title, base.title); // other fields unchanged
    });

    test('can explicitly clear series to null', () {
      final copy = base.copyWith(series: null);
      expect(copy.series, isNull);
      expect(copy.seriesIndex, base.seriesIndex);
    });

    test('can explicitly clear seriesIndex to null', () {
      final copy = base.copyWith(seriesIndex: null);
      expect(copy.seriesIndex, isNull);
    });

    test('can explicitly clear narrator to null', () {
      final copy = base.copyWith(narrator: null);
      expect(copy.narrator, isNull);
    });

    test('can explicitly clear language to null', () {
      final copy = base.copyWith(language: null);
      expect(copy.language, isNull);
    });

    test('path is always preserved', () {
      final copy = base.copyWith(title: 'X');
      expect(copy.path, base.path);
    });

    test('list fields use provided value when given', () {
      final newFiles = ['/books/test/a.mp3', '/books/test/b.mp3'];
      final copy = base.copyWith(audioFiles: newFiles);
      expect(copy.audioFiles, newFiles);
    });

    test('list fields are preserved when not passed', () {
      final copy = base.copyWith(title: 'X');
      expect(copy.audioFiles, base.audioFiles);
    });
  });
}
