import 'package:flutter_test/flutter_test.dart';
import 'package:audiovault_editor/models/audiobook.dart';
import 'package:audiovault_editor/services/metadata_writer.dart';
import 'package:audiovault_editor/services/opf_parser.dart';

void main() {
  group('OPF round-trip (buildOpfXml -> parseOpf)', () {
    const book = Audiobook(
      path: '/books/x',
      audioFiles: [],
      title: 'Round Trip & Co.',
      subtitle: 'A Subtitle',
      author: 'Author One',
      narrator: 'Narrator <One>',
      additionalAuthors: ['Co-Author A', 'Co-Author B'],
      additionalNarrators: ['Co-Narrator N'],
      description: 'Description with "quotes" and <tags> & ampersands',
      publisher: 'Publisher',
      language: 'en',
      genre: 'Fantasy',
      identifier: 'isbn:1234567890',
      releaseDate: '2021-05-01',
      series: 'The Saga',
      seriesIndex: 7,
      opfMeta: {'calibre:title_sort': 'Round Trip & Co.', 'custom:key': 'v'},
    );

    test('preserves all mapped fields', () {
      final parsed = parseOpf(MetadataWriter.buildOpfXml(book));

      expect(parsed.title, 'Round Trip & Co.');
      expect(parsed.subtitle, 'A Subtitle');
      expect(parsed.author, 'Author One');
      expect(parsed.narrator, 'Narrator <One>');
      expect(parsed.additionalAuthors, ['Co-Author A', 'Co-Author B']);
      expect(parsed.additionalNarrators, ['Co-Narrator N']);
      expect(parsed.description,
          'Description with "quotes" and <tags> & ampersands');
      expect(parsed.publisher, 'Publisher');
      expect(parsed.language, 'en');
      expect(parsed.genre, 'Fantasy');
      expect(parsed.identifier, 'isbn:1234567890');
      // Full date precision survives the round trip.
      expect(parsed.releaseDate, '2021-05-01');
      expect(parsed.series, 'The Saga');
      expect(parsed.seriesIndex, 7);
    });

    test('preserves custom meta passthrough', () {
      final parsed = parseOpf(MetadataWriter.buildOpfXml(book));
      expect(parsed.opfMeta['calibre:title_sort'], 'Round Trip & Co.');
      expect(parsed.opfMeta['custom:key'], 'v');
      // Managed meta keys must not leak into passthrough.
      expect(parsed.opfMeta.containsKey('subtitle'), isFalse);
    });

    test('XML special characters survive escaping both ways', () {
      final tricky = book.copyWith(
        title: 'A & B <C> "D" \'E\'',
        author: 'Zzz',
      );
      final parsed = parseOpf(MetadataWriter.buildOpfXml(tricky));
      expect(parsed.title, 'A & B <C> "D" \'E\'');
    });
  });
}
