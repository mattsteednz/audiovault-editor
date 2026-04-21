import 'package:xml/xml.dart';

class OpfMetadata {
  final String? title;
  final String? author;
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
  final List<String> additionalAuthors;
  final List<String> additionalNarrators;
  final Map<String, String> opfMeta;

  const OpfMetadata({
    this.title,
    this.author,
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
    this.additionalAuthors = const [],
    this.additionalNarrators = const [],
    this.opfMeta = const {},
  });
}

OpfMetadata parseOpf(String xmlContent) {
  try {
    final doc = XmlDocument.parse(xmlContent);
    final metadata = doc.findAllElements('metadata').firstOrNull ??
        doc.findAllElements('dc-metadata').firstOrNull;
    if (metadata == null) return const OpfMetadata();

    String? title;
    final authors = <String>[];
    final narrators = <String>[];
    String? subtitle;
    String? description;
    String? publisher;
    String? language;
    String? genre;
    String? identifier;
    String? releaseDate;
    String? series;
    int? seriesIndex;
    final opfMeta = <String, String>{};

    title = _dcText(metadata, 'title');

    for (final el in metadata.findElements('dc:creator')) {
      final role = el.getAttribute('opf:role') ??
          el.getAttribute('role') ??
          'aut';
      final text = el.innerText.trim();
      if (text.isEmpty) continue;
      if (role == 'aut') authors.add(text);
      if (role == 'nrt') narrators.add(text);
    }

    description = _dcText(metadata, 'description');
    publisher = _dcText(metadata, 'publisher');
    language = _dcText(metadata, 'language');
    genre = _dcText(metadata, 'subject');
    identifier = _dcText(metadata, 'identifier');

    final dateText = _dcText(metadata, 'date');
    if (dateText != null && dateText.length >= 4) {
      final year = dateText.substring(0, 4);
      if (int.tryParse(year) != null) releaseDate = year;
    }

    for (final el in metadata.findElements('meta')) {
      final name = el.getAttribute('name') ?? '';
      final content = el.getAttribute('content') ?? '';
      if (content.isEmpty) continue;
      if (name == 'calibre:series') {
        series = content;
      } else if (name == 'calibre:series_index') {
        final d = double.tryParse(content);
        if (d != null) seriesIndex = d.round();
      } else if (name == 'subtitle') {
        subtitle = content;
      } else if (name.isNotEmpty) {
        opfMeta[name] = content;
      }
    }

    return OpfMetadata(
      title: title,
      author: authors.firstOrNull,
      narrator: narrators.firstOrNull,
      subtitle: subtitle,
      description: description,
      publisher: publisher,
      language: language,
      genre: genre,
      identifier: identifier,
      releaseDate: releaseDate,
      series: series,
      seriesIndex: seriesIndex,
      additionalAuthors: authors.length > 1 ? authors.sublist(1) : const [],
      additionalNarrators: narrators.length > 1 ? narrators.sublist(1) : const [],
      opfMeta: opfMeta,
    );
  } catch (_) {
    return const OpfMetadata();
  }
}

String? _dcText(XmlElement metadata, String localName) {
  final el = metadata.findElements('dc:$localName').firstOrNull;
  if (el == null) return null;
  final text = el.innerText.trim();
  return text.isEmpty ? null : text;
}
