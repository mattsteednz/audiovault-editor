import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:audiovault_editor/models/audiobook.dart';
import 'package:audiovault_editor/services/writers/atomic_file_writer.dart';
import 'package:audiovault_editor/services/writers/id3_writer.dart';
import 'package:audiovault_editor/services/writers/mp4_writer.dart';
import 'package:audiovault_editor/services/writers/flac_writer.dart';
import 'package:audiovault_editor/services/writers/ogg_writer.dart';

class MetadataWriter {
  const MetadataWriter._();

  /// JPEG re-encode worker — runs off the UI isolate because decoding and
  /// encoding large cover art is expensive.
  static Uint8List _toJpegJob(Uint8List imageBytes) {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) throw Exception('Could not decode image');
    return Uint8List.fromList(img.encodeJpg(decoded, quality: 92));
  }

  /// Converts [imageBytes] to JPEG, returning re-encoded bytes.
  static Future<Uint8List> toJpeg(Uint8List imageBytes) =>
      compute(_toJpegJob, imageBytes);

  /// Embeds title, author, narrator, and year into all audio files.
  /// Returns a list of per-file error strings; empty = full success.
  static Future<List<String>> applyMetadata(Audiobook book) async {
    final errors = <String>[];
    for (final filePath in book.audioFiles) {
      final ext = p.extension(filePath).toLowerCase();
      try {
        if (ext == '.mp3') {
          await Mp3Writer.writeMetadata(filePath, book);
        } else if (ext == '.m4b' || ext == '.m4a') {
          await Mp4Writer.writeMetadata(filePath, book);
        } else if (ext == '.flac') {
          await FlacWriter.writeMetadata(filePath, book);
        } else if (ext == '.ogg') {
          await OggWriter.writeMetadata(filePath, book);
        } else if (ext == '.aac') {
          // Raw .aac files are ADTS streams, not MP4 containers — there is no
          // tag surface to write to. Report it instead of silently no-op'ing.
          errors.add(
              '${p.basename(filePath)}: metadata writing is not supported for '
              '.aac files');
        }
      } catch (e) {
        errors.add('${p.basename(filePath)}: $e');
      }
    }
    return errors;
  }

  /// Writes cover.jpg to the book folder and embeds the cover into all audio files.
  /// Returns a list of per-file error strings; empty = full success.
  static Future<List<String>> applyCover(
      Audiobook book, String imagePath) async {
    final errors = <String>[];
    final imageBytes = await File(imagePath).readAsBytes();
    final jpegBytes = await toJpeg(imageBytes);
    await writeFileAtomic(p.join(book.path, 'cover.jpg'), jpegBytes);
    for (final filePath in book.audioFiles) {
      final ext = p.extension(filePath).toLowerCase();
      try {
        if (ext == '.mp3') {
          await Mp3Writer.embedCover(filePath, jpegBytes);
        } else if (ext == '.m4b' || ext == '.m4a') {
          await Mp4Writer.embedCover(filePath, jpegBytes);
        } else if (ext == '.flac') {
          await FlacWriter.embedCover(filePath, jpegBytes);
        } else if (ext == '.ogg') {
          await OggWriter.embedCover(filePath, jpegBytes);
        } else if (ext == '.aac') {
          errors.add(
              '${p.basename(filePath)}: cover embedding is not supported for '
              '.aac files');
        }
      } catch (e) {
        errors.add('${p.basename(filePath)}: $e');
      }
    }
    return errors;
  }

  /// Writes chapter data to the audio file for single-file M4B/M4A books.
  ///
  /// For MP3 books, chapters are stored in a CUE file (not embedded).
  /// Returns per-file error strings; empty = success.
  static Future<List<String>> applyChapters(
    Audiobook book,
    List<Chapter> chapters,
  ) async {
    if (chapters.isEmpty) return const [];
    if (book.audioFiles.length != 1) return const [];

    final filePath = book.audioFiles.first;
    final ext = p.extension(filePath).toLowerCase();

    if (ext == '.m4b' || ext == '.m4a') {
      try {
        await Mp4Writer.writeChapters(filePath, chapters, book.duration);
        return const [];
      } catch (e) {
        return ['${p.basename(filePath)}: $e'];
      }
    }
    // MP3: chapters stored in CUE file, not embedded
    return const [];
  }

  // ── OPF / cover export ────────────────────────────────────────────────────

  static Future<void> exportMetadata(Audiobook book) async {
    await exportOpf(book);
    await exportCover(book);
  }

  static Future<void> exportCover(Audiobook book) async {
    final coverOut = p.join(book.path, 'cover.jpg');
    if (book.coverImageBytes != null) {
      await writeFileAtomic(coverOut, await toJpeg(book.coverImageBytes!));
    } else if (book.coverImagePath != null) {
      final bytes = await File(book.coverImagePath!).readAsBytes();
      await writeFileAtomic(coverOut, await toJpeg(bytes));
    }
  }

  static Future<void> exportOpf(Audiobook book) async {
    await writeStringAtomic(
        p.join(book.path, 'metadata.opf'), buildOpfXml(book));
  }

  /// Serialises [book] into OPF 2.0 XML (pure function — no I/O).
  static String buildOpfXml(Audiobook book) {
    final buf = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="utf-8"?>')
      ..writeln('<package xmlns="http://www.idpf.org/2007/opf" version="2.0" '
          'unique-identifier="uid">')
      ..writeln('  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" '
          'xmlns:opf="http://www.idpf.org/2007/opf">')
      ..writeln('    <dc:title>${_xmlEscape(book.title ?? '')}</dc:title>');

    if (book.identifier != null) {
      buf.writeln(
          '    <dc:identifier>${_xmlEscape(book.identifier!)}</dc:identifier>');
    }
    if (book.subtitle != null) {
      buf.writeln('    <meta name="subtitle" content="${_xmlEscape(book.subtitle!)}"/>');
    }
    if (book.author != null) {
      buf.writeln('    <dc:creator opf:role="aut">'
          '${_xmlEscape(book.author!)}</dc:creator>');
    }
    for (final a in book.additionalAuthors) {
      buf.writeln(
          '    <dc:creator opf:role="aut">${_xmlEscape(a)}</dc:creator>');
    }
    if (book.narrator != null) {
      buf.writeln('    <dc:creator opf:role="nrt">'
          '${_xmlEscape(book.narrator!)}</dc:creator>');
    }
    for (final n in book.additionalNarrators) {
      buf.writeln(
          '    <dc:creator opf:role="nrt">${_xmlEscape(n)}</dc:creator>');
    }
    if (book.description != null) {
      buf.writeln('    <dc:description>'
          '${_xmlEscape(book.description!)}</dc:description>');
    }
    if (book.publisher != null) {
      buf.writeln(
          '    <dc:publisher>${_xmlEscape(book.publisher!)}</dc:publisher>');
    }
    if (book.language != null) {
      buf.writeln(
          '    <dc:language>${_xmlEscape(book.language!)}</dc:language>');
    }
    if (book.genre != null) {
      buf.writeln(
          '    <dc:subject>${_xmlEscape(book.genre!)}</dc:subject>');
    }
    if (book.releaseDate != null) {
      buf.writeln('    <dc:date>${_xmlEscape(book.releaseDate!)}</dc:date>');
    }
    if (book.series != null) {
      buf.writeln('    <meta name="calibre:series" '
          'content="${_xmlEscape(book.series!)}"/>');
    }
    if (book.seriesIndex != null) {
      buf.writeln(
          '    <meta name="calibre:series_index" content="${book.seriesIndex}"/>');
    }
    for (final entry in book.opfMeta.entries) {
      buf.writeln(
          '    <meta name="${_xmlEscape(entry.key)}" content="${_xmlEscape(entry.value)}"/>');
    }
    buf
      ..writeln('  </metadata>')
      ..writeln('</package>');
    return buf.toString();
  }

  static String _xmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
