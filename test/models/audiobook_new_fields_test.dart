import 'package:flutter_test/flutter_test.dart';
import 'package:audiovault_editor/models/audiobook.dart';

void main() {
  const base = Audiobook(
    path: '/books/test',
    audioFiles: ['/books/test/track.mp3'],
    title: 'Title',
    author: 'Author',
    genre: 'Fiction',
    identifier: 'isbn:123',
    additionalAuthors: ['Co-Author'],
    additionalNarrators: ['Second Narrator'],
    opfMeta: {'calibre:rating': '8'},
  );

  group('Audiobook.copyWith new fields', () {
    test('genre is preserved when not passed', () {
      expect(base.copyWith().genre, 'Fiction');
    });

    test('genre can be updated', () {
      expect(base.copyWith(genre: 'Non-Fiction').genre, 'Non-Fiction');
    });

    test('genre can be cleared to null', () {
      expect(base.copyWith(genre: null).genre, isNull);
    });

    test('identifier is preserved when not passed', () {
      expect(base.copyWith().identifier, 'isbn:123');
    });

    test('identifier can be cleared to null', () {
      expect(base.copyWith(identifier: null).identifier, isNull);
    });

    test('additionalAuthors preserved when not passed', () {
      expect(base.copyWith().additionalAuthors, ['Co-Author']);
    });

    test('additionalAuthors can be replaced', () {
      final copy = base.copyWith(additionalAuthors: ['New Co']);
      expect(copy.additionalAuthors, ['New Co']);
    });

    test('additionalNarrators preserved when not passed', () {
      expect(base.copyWith().additionalNarrators, ['Second Narrator']);
    });

    test('opfMeta preserved when not passed', () {
      expect(base.copyWith().opfMeta, {'calibre:rating': '8'});
    });

    test('opfMeta can be replaced', () {
      final copy = base.copyWith(opfMeta: {'calibre:timestamp': '2024'});
      expect(copy.opfMeta, {'calibre:timestamp': '2024'});
    });
  });
}
