import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:audiovault_editor/models/audiobook.dart';

/// A parsed CUE sheet: optional global title/performer, the resolved audio
/// file list, and chapter marks (only populated for single-file sheets).
class CueSheet {
  final String? title;
  final String? author;
  final List<String> audioFiles;
  final List<Chapter> chapters;

  const CueSheet({
    this.title,
    this.author,
    required this.audioFiles,
    required this.chapters,
  });
}

/// Parses a CUE sheet's text content, resolving FILE paths against
/// [folderPath]. Files that do not exist on disk are skipped. Returns null
/// when no playable FILE section could be parsed.
CueSheet? parseCueSheet(String content, String folderPath) {
  String? globalTitle;
  String? globalPerformer;
  final fileSections = <({String path, List<Chapter> chapters})>[];
  String? currentFilePath;
  final pendingChapters = <Chapter>[];
  String? pendingTrackTitle;

  void commitFile() {
    if (currentFilePath != null) {
      fileSections.add((path: currentFilePath!, chapters: List.of(pendingChapters)));
    }
    pendingChapters.clear();
    currentFilePath = null;
    pendingTrackTitle = null;
  }

  for (var line in content.split('\n')) {
    line = line.trim();
    if (line.isEmpty || line.startsWith('REM')) continue;
    if (line.startsWith('FILE ')) {
      commitFile();
      final match = RegExp(r'^FILE\s+"(.+?)"\s+\S+').firstMatch(line) ??
          RegExp(r'^FILE\s+(\S+)\s+\S+').firstMatch(line);
      if (match == null) continue;
      final filename = match.group(1)!.replaceAll('\\', p.separator);
      final resolved = p.join(folderPath, filename);
      currentFilePath = File(resolved).existsSync() ? resolved : null;
    } else if (line.startsWith('TITLE ')) {
      final title = _cueUnquote(line.substring(6));
      if (currentFilePath == null && fileSections.isEmpty) {
        globalTitle = title;
      } else {
        pendingTrackTitle = title;
      }
    } else if (line.startsWith('PERFORMER ')) {
      final performer = _cueUnquote(line.substring(10));
      if (currentFilePath == null && fileSections.isEmpty) {
        globalPerformer = performer;
      }
    } else if (line.startsWith('INDEX 01 ') && pendingTrackTitle != null) {
      final dur = _parseCueTime(line.substring(9).trim());
      if (dur != null && currentFilePath != null) {
        pendingChapters.add(Chapter(title: pendingTrackTitle!, start: dur));
      }
      pendingTrackTitle = null;
    }
  }
  commitFile();
  if (fileSections.isEmpty) return null;
  return CueSheet(
    title: globalTitle,
    author: globalPerformer,
    audioFiles: fileSections.map((s) => s.path).toList(),
    chapters: fileSections.length == 1 ? fileSections.first.chapters : const [],
  );
}

String _cueUnquote(String s) {
  s = s.trim();
  if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
    return s.substring(1, s.length - 1);
  }
  return s;
}

Duration? _parseCueTime(String s) {
  final parts = s.split(':');
  if (parts.length != 3) return null;
  final mm = int.tryParse(parts[0]);
  final ss = int.tryParse(parts[1]);
  final ff = int.tryParse(parts[2]);
  if (mm == null || ss == null || ff == null) return null;
  return Duration(milliseconds: mm * 60000 + ss * 1000 + ff * 1000 ~/ 75);
}
