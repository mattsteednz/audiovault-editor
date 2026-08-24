import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Leveled logger that mirrors to debugPrint AND an on-disk log file under
/// `<APPDATA>/AudioVaultEditor/logs` (falls back to the system temp dir).
///
/// Files rotate daily and entries older than [retentionDays] are removed.
/// All file I/O is best-effort and wrapped so logging can never take the
/// app down.
class AppLog {
  AppLog._();

  static const int retentionDays = 7;
  static File? _currentFile;
  static DateTime _currentDay = DateTime(0);

  static String d(String message) => _emit('DEBUG', message);
  static String w(String message) => _emit('WARN', message);
  static String e(String message) => _emit('ERROR', message);

  /// Directory containing the log files (created lazily).
  static Directory logsDirectory() {
    final base = Platform.environment['APPDATA'] ??
        Directory.systemTemp.path;
    return Directory(p.join(base, 'AudioVaultEditor', 'logs'));
  }

  static String _emit(String level, String message) {
    final line =
        '[${DateTime.now().toIso8601String()}][$level] $message';
    // Surface in consoles / flutter run logs.
    debugPrint(line);

    try {
      final now = DateTime.now();
      final sameDay = now.year == _currentDay.year &&
          now.month == _currentDay.month &&
          now.day == _currentDay.day;
      if (!sameDay) {
        final dir = logsDirectory();
        if (!dir.existsSync()) dir.createSync(recursive: true);
        _pruneOldLogs(dir, now);
        _currentFile = File(p.join(
            dir.path,
            'av-${now.year.toString().padLeft(4, '0')}-'
            '${now.month.toString().padLeft(2, '0')}-'
            '${now.day.toString().padLeft(2, '0')}.log'));
        _currentDay = now;
      }
      _currentFile?.writeAsStringSync('$line\n', mode: FileMode.append);
    } catch (_) {
      // Logging must never throw.
    }
    return line;
  }

  static void _pruneOldLogs(Directory dir, DateTime now) {
    try {
      final cutoff = now.subtract(const Duration(days: retentionDays));
      for (final f in dir.listSync()) {
        if (f is File && f.path.endsWith('.log')) {
          final modified = f.lastModifiedSync();
          if (modified.isBefore(cutoff)) {
            f.deleteSync();
          }
        }
      }
    } catch (_) {}
  }

  /// Opens the log folder in Windows Explorer (best-effort).
  static Future<void> revealLogsFolder() async {
    try {
      final dir = logsDirectory();
      if (!dir.existsSync()) dir.createSync(recursive: true);
      await Process.run('explorer.exe', [dir.path]);
    } catch (_) {}
  }
}
