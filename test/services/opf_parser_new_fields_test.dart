import 'package:flutter_test/flutter_test.dart';
import 'package:audiovault_editor/services/opf_parser.dart';

void main() {
  group('parseOpf new fields', () {
    test('parses genre from dc:subject', () {
      const xml = '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Book</dc:title>
    <dc:subject>Science Fiction</dc:subject>
  </metadata>
</package>''';
      final result = parseOpf(xml);
      expect(result.genre, 'Science Fiction');
    });

    test('parses identifier from dc:identifier', () {
      const xml = '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Book</dc:title>
    <dc:identifier>isbn:9781234567890</dc:identifier>
  </metadata>
</package>''';
      final result = parseOpf(xml);
      expect(result.identifier, 'isbn:9781234567890');
    });

    test('parses multiple authors into author and additionalAuthors', () {
      const xml = '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"
            xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:title>Book</dc:title>
    <dc:creator opf:role="aut">Author One</dc:creator>
    <dc:creator opf:role="aut">Author Two</dc:creator>
    <dc:creator opf:role="aut">Author Three</dc:creator>
  </metadata>
</package>''';
      final result = parseOpf(xml);
      expect(result.author, 'Author One');
      expect(result.additionalAuthors, ['Author Two', 'Author Three']);
    });

    test('parses multiple narrators into narrator and additionalNarrators', () {
      const xml = '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"
            xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:title>Book</dc:title>
    <dc:creator opf:role="nrt">Narrator One</dc:creator>
    <dc:creator opf:role="nrt">Narrator Two</dc:creator>
  </metadata>
</package>''';
      final result = parseOpf(xml);
      expect(result.narrator, 'Narrator One');
      expect(result.additionalNarrators, ['Narrator Two']);
    });

    test('single author has empty additionalAuthors', () {
      const xml = '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"
            xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:title>Book</dc:title>
    <dc:creator opf:role="aut">Solo Author</dc:creator>
  </metadata>
</package>''';
      final result = parseOpf(xml);
      expect(result.author, 'Solo Author');
      expect(result.additionalAuthors, isEmpty);
    });

    test('preserves unknown meta entries in opfMeta', () {
      const xml = '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"
            xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:title>Book</dc:title>
    <meta name="calibre:series" content="My Series"/>
    <meta name="calibre:series_index" content="1.0"/>
    <meta name="calibre:rating" content="8"/>
    <meta name="calibre:timestamp" content="2024-01-01"/>
  </metadata>
</package>''';
      final result = parseOpf(xml);
      // Known fields extracted normally
      expect(result.series, 'My Series');
      expect(result.seriesIndex, 1);
      // Unknown fields passed through
      expect(result.opfMeta['calibre:rating'], '8');
      expect(result.opfMeta['calibre:timestamp'], '2024-01-01');
      // Known fields not duplicated in opfMeta
      expect(result.opfMeta.containsKey('calibre:series'), isFalse);
      expect(result.opfMeta.containsKey('calibre:series_index'), isFalse);
    });

    test('opfMeta is empty when no unknown meta elements', () {
      const xml = '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Book</dc:title>
  </metadata>
</package>''';
      final result = parseOpf(xml);
      expect(result.opfMeta, isEmpty);
    });
  });

  group('Audiobook copyWith new fields', () {
    // These are covered via the model test; just verify genre/identifier here
    // via the OPF round-trip path (parse → check fields present)
    test('genre and identifier are null when absent from OPF', () {
      const xml = '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Book</dc:title>
  </metadata>
</package>''';
      final result = parseOpf(xml);
      expect(result.genre, isNull);
      expect(result.identifier, isNull);
    });
  });
}
