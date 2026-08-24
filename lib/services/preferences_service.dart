import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audiovault_editor/controllers/library_controller.dart';

/// Persists user preferences across app sessions.
class PreferencesService {
  static const _keyFolderPath = 'folder_path';
  static const _keySortOrder = 'sort_order';
  static const _keyWindowX = 'window_x';
  static const _keyWindowY = 'window_y';
  static const _keyWindowWidth = 'window_width';
  static const _keyWindowHeight = 'window_height';
  static const _keySidebarWidth = 'sidebar_width';
  static const _keyLastBookPath = 'last_book_path';
  static const _keyFfmpegPathOverride = 'ffmpeg_path_override';
  static const _keyAdvanceAfterApply = 'advance_after_apply';
  static const _keyKeepBackups = 'keep_backups';

  /// Save the path of the currently selected book (session continuity).
  static Future<void> saveLastBook(String path) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLastBookPath, path);
    } catch (e) {
      debugPrint('Failed to save last book: $e');
    }
  }

  static Future<String?> loadLastBook() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyLastBookPath);
    } catch (e) {
      debugPrint('Failed to load last book: $e');
      return null;
    }
  }

  static Future<void> clearLastBook() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLastBookPath);
  }

  /// Custom ffmpeg executable location (settings override).
  static Future<void> saveFfmpegOverride(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.isEmpty) {
      await prefs.remove(_keyFfmpegPathOverride);
    } else {
      await prefs.setString(_keyFfmpegPathOverride, path);
    }
  }

  static Future<String?> loadFfmpegOverride() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyFfmpegPathOverride);
  }

  /// Whether Apply should auto-advance selection to the next book.
  static Future<void> saveAdvanceAfterApply(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAdvanceAfterApply, value);
  }

  /// Defaults to true (apply-and-next is the primary workflow).
  static Future<bool> loadAdvanceAfterApply() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAdvanceAfterApply) ?? true;
  }

  /// Whether audio writes preserve the original as `<name>.bak`.
  static Future<void> saveKeepBackups(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyKeepBackups, value);
  }

  static Future<bool> loadKeepBackups() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyKeepBackups) ?? false;
  }

  /// Save the last-opened folder path.
  static Future<void> saveFolder(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFolderPath, path);
  }

  /// Load the last-opened folder path, or null if none saved.
  static Future<String?> loadFolder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyFolderPath);
  }

  /// Clear the saved folder path (e.g., if the folder no longer exists).
  static Future<void> clearFolder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyFolderPath);
  }

  /// Save the current sort order.
  static Future<void> saveSortOrder(SortOrder order) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySortOrder, order.name);
  }

  /// Load the saved sort order, or null if none saved.
  static Future<SortOrder?> loadSortOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_keySortOrder);
    if (name == null) return null;
    return SortOrder.values.firstWhere(
      (e) => e.name == name,
      orElse: () => SortOrder.titleAsc,
    );
  }

  /// Save the current window bounds.
  static Future<void> saveWindowBounds(Rect bounds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyWindowX, bounds.left);
    await prefs.setDouble(_keyWindowY, bounds.top);
    await prefs.setDouble(_keyWindowWidth, bounds.width);
    await prefs.setDouble(_keyWindowHeight, bounds.height);
  }

  /// Load the saved window bounds, or null if none saved.
  static Future<Rect?> loadWindowBounds() async {
    final prefs = await SharedPreferences.getInstance();
    final x = prefs.getDouble(_keyWindowX);
    final y = prefs.getDouble(_keyWindowY);
    final w = prefs.getDouble(_keyWindowWidth);
    final h = prefs.getDouble(_keyWindowHeight);
    if (x == null || y == null || w == null || h == null) return null;
    return Rect.fromLTWH(x, y, w, h);
  }

  /// Save the sidebar width preference.
  static Future<void> saveSidebarWidth(double width) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keySidebarWidth, width);
    } catch (e) {
      // Graceful degradation - log but don't throw
      debugPrint('Failed to save sidebar width: $e');
    }
  }

  /// Load the saved sidebar width, or null if none saved.
  static Future<double?> loadSidebarWidth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getDouble(_keySidebarWidth);
    } catch (e) {
      // Graceful degradation - return null to use default
      debugPrint('Failed to load sidebar width: $e');
      return null;
    }
  }
}
