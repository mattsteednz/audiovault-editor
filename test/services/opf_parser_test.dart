import 'package:flutter_test/flutter_test.dart';
import 'package:audiovault_editor/services/opf_parser.dart';

void main() {
  group('parseOpf', () {
    test('parses title and author', () {
      const xml = '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"
            xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:title>My Book</dc:title>
    <dc:creator opf:role="aut">Jane Doe</dc:creator>
  </metadata>
</package>''';
      final result = parseOpf(xml);
      expect(result.title, 'My Book');
      expect(result.author, 'Jane Doe');
      expect(result.narrator, isNull);
    });

    test('parses narrator from nrt role', () {
      const xml = '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"
            xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:title>Book</dc:title>
    <dc:creator opf:role="aut">Author Name</dc:creator>
    <dc:creator opf:role="nrt">Narrator Name</dc:creator>
  </metadata>
</package>''';
      final result = parseOpf(xml);
      expect(result.author, 'Author Name');
      expect(result.narrator, 'Narrator Name');
    });

    test('parses series and series index from calibre meta', () {
      const xml = '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"
            xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:title>Book 3</dc:title>
    <meta name="calibre:series" content="The Series"/>
    <meta name="calibre:series_index" content="3.0"/>
  </metadata>
</package>''';
      final result = parseOpf(xml);
      expect(result.series, 'The Series');
      expect(result.seriesIndex, 3);
    });

    test('extracts year from full date string', () {
      const xml = '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Book</dc:title>
    <dc:date>2019-06-15</dc:date>
  </metadata>
</package>''';
      final result = parseOpf(xml);
      expect(result.releaseDate, '2019');
    });

    test('parses publisher and language', () {
      const xml = '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Book</dc:title>
    <dc:publisher>Acme Books</dc:publisher>
    <dc:language>en</dc:language>
  </metadata>
</package>''';
      final result = parseOpf(xml);
      expect(result.publisher, 'Acme Books');
      expect(result.language, 'en');
    });

    test('returns empty OpfMetadata for missing metadata element', () {
      const xml = '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
</package>''';
      final result = parseOpf(xml);
      expect(result.title, isNull);
      expect(result.author, isNull);
    });

    test('returns empty OpfMetadata for malformed XML', () {
      const xml = '<not valid xml <<< >';
      final result = parseOpf(xml);
      expect(result.title, isNull);
    });

    test('trims whitespace from fields', () {
      const xml = '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>  Spaced Title  </dc:title>
    <dc:creator>  Spaced Author  </dc:creator>
  </metadata>
</package>''';
      final result = parseOpf(xml);
      expect(result.title, 'Spaced Title');
      expect(result.author, 'Spaced Author');
    });

    test('returns null for empty string fields', () {
      const xml = '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title></dc:title>
  </metadata>
</package>''';
      final result = parseOpf(xml);
      expect(result.title, isNull);
    });

    test('parses subtitle from meta name="subtitle"', () {
      const xml = '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Main Title</dc:title>
    <meta name="subtitle" content="The Subtitle"/>
  </metadata>
</package>''';
      final result = parseOpf(xml);
      expect(result.subtitle, 'The Subtitle');
      // subtitle must not appear in opfMeta passthrough
      expect(result.opfMeta.containsKey('subtitle'), isFalse);
    });

    test('subtitle excluded from opfMeta passthrough', () {
      const xml = '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Book</dc:title>
    <meta name="subtitle" content="Sub"/>
    <meta name="custom:field" content="keep"/>
  </metadata>
</package>''';
      final result = parseOpf(xml);
      expect(result.subtitle, 'Sub');
      expect(result.opfMeta.containsKey('subtitle'), isFalse);
      expect(result.opfMeta['custom:field'], 'keep');
    });

    test('no duplicate dc:description when both subtitle and description set', () {
      // Verify the old dc:description opf:file-as="subtitle" format is NOT
      // produced by the parser (it reads description only from dc:description).
      const xml = '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Book</dc:title>
    <dc:description>Long description here</dc:description>
    <meta name="subtitle" content="Short subtitle"/>
  </metadata>
</package>''';
      final result = parseOpf(xml);
      expect(result.description, 'Long description here');
      expect(result.subtitle, 'Short subtitle');
    });
  });
}
