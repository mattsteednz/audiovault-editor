import 'package:xml/xml.dart';

class OpfMetadata {
  final String? title;
  final String? author;
  final String? narrator;
  final String? description;
  final String? publisher;
  final String? language;
  final String? releaseDate;
  final String? series;
  final int? seriesIndex;

  const OpfMetadata({
    this.title,
    this.author,
    this.narrator,
    this.description,
    this.publisher,
    this.language,
    this.releaseDate,
    this.series,
    this.seriesIndex,
  });
}

OpfMetadata parseOpf(String xmlContent) {
  try {
    final doc = XmlDocument.parse(xmlContent);
    final metadata = doc.findAllElements('metadata').firstOrNull ??
        doc.findAllElements('dc-metadata').firstOrNull;
    if (metadata == null) return const OpfMetadata();

    String? title;
    String? author;
    String? narrator;
    String? description;
    String? publisher;
    String? language;
    String? releaseDate;
    String? series;
    int? seriesIndex;

    title = _dcText(metadata, 'title');

    for (final el in metadata.findElements('dc:creator')) {
      final role = el.getAttribute('opf:role') ??
          el.getAttribute('role') ??
          'aut';
      final text = el.innerText.trim();
      if (text.isEmpty) continue;
      if (role == 'aut' && author == null) author = text;
      if (role == 'nrt' && narrator == null) narrator = text;
    }

    description = _dcText(metadata, 'description');
    publisher = _dcText(metadata, 'publisher');
    language = _dcText(metadata, 'language');

    final dateText = _dcText(metadata, 'date');
    if (dateText != null && dateText.length >= 4) {
      final year = dateText.substring(0, 4);
      if (int.tryParse(year) != null) releaseDate = year;
    }

    for (final el in metadata.findElements('meta')) {
      final name = el.getAttribute('name') ?? '';
      final content = el.getAttribute('content') ?? '';
      if (content.isEmpty) continue;
      if (name == 'calibre:series') series = content;
      if (name == 'calibre:series_index') {
        final d = double.tryParse(content);
        if (d != null) seriesIndex = d.round();
      }
    }

    return OpfMetadata(
      title: title,
      author: author,
      narrator: narrator,
      description: description,
      publisher: publisher,
      language: language,
      releaseDate: releaseDate,
      series: series,
      seriesIndex: seriesIndex,
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
