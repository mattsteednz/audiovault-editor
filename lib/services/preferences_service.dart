import 'dart:ui';
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
}
