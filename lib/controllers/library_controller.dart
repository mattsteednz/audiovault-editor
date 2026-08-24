import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audiovault_editor/models/audiobook.dart';
import 'package:audiovault_editor/services/app_logger.dart';
import 'package:audiovault_editor/services/metadata_writer.dart';
import 'package:audiovault_editor/services/scanner_service.dart';
import 'package:audiovault_editor/services/preferences_service.dart';

enum SortOrder { titleAsc, titleDesc, authorAsc, authorDesc, seriesAsc, narratorAsc, durationAsc, durationDesc }

/// One reversible state transition.
class _UndoEntry {
  /// Model state BEFORE the change (paths match post-change paths except
  /// renames, which carry their own mapping).
  final List<Audiobook> before;

  /// Model state AFTER the change (used by redo).
  final List<Audiobook> after;

  final String label;

  /// Present only for folder renames; undone by renaming [to] back to
  /// [from] on disk.
  final ({String from, String to})? rename;

  _UndoEntry({
    required this.before,
    required this.after,
    required this.label,
    this.rename,
  });
}

class LibraryController extends ChangeNotifier {
  LibraryController({
    ScannerService? scanner,
    Future<void> Function(Audiobook book)? applySnapshot,
  })  : _scanner = scanner ?? ScannerService(),
        _applySnapshot = applySnapshot;

  final ScannerService _scanner;

  /// Write-back used by undo; injectable for tests.
  final Future<void> Function(Audiobook book)? _applySnapshot;

  static const int _maxUndoEntries = 25;
  final List<_UndoEntry> _undoStack = [];
  final List<_UndoEntry> _redoStack = [];

  List<Audiobook> _books = [];
  Audiobook? _selected;
  final Set<String> _dirtyPaths = {};
  final Set<String> _batchPaths = {};
  final Set<String> _duplicatePaths = {};
  final Set<String> _missingCoverPaths = {};
  final Set<String> _readOnlyPaths = {};
  final Set<String> _missingChaptersPaths = {};
  int _readOnlyCount = 0;
  bool _showDuplicatesOnly = false;
  bool _showMissingCoverOnly = false;
  bool _showReadOnlyOnly = false;
  bool _showMissingChaptersOnly = false;
  bool _scanning = false;
  int _scanFound = 0;
  int _scanTotal = 0;
  String? _folderPath;
  String _searchQuery = '';
  SortOrder _sortOrder = SortOrder.titleAsc;
  List<String> _scanWarnings = const [];

  /// Generation counter — bumped to invalidate an in-flight scan.
  int _scanGeneration = 0;

  // ── Read-only accessors ───────────────────────────────────────────────────

  List<Audiobook> get books => _books;
  Audiobook? get selected => _selected;
  Set<String> get dirtyPaths => Set.unmodifiable(_dirtyPaths);
  Set<String> get batchPaths => Set.unmodifiable(_batchPaths);
  Set<String> get duplicatePaths => Set.unmodifiable(_duplicatePaths);
  Set<String> get missingCoverPaths => Set.unmodifiable(_missingCoverPaths);
  Set<String> get readOnlyPaths => Set.unmodifiable(_readOnlyPaths);
  Set<String> get missingChaptersPaths => Set.unmodifiable(_missingChaptersPaths);
  bool get showDuplicatesOnly => _showDuplicatesOnly;
  bool get showMissingCoverOnly => _showMissingCoverOnly;
  bool get showReadOnlyOnly => _showReadOnlyOnly;
  bool get showMissingChaptersOnly => _showMissingChaptersOnly;
  int get missingCoverCount => _missingCoverPaths.length;
  int get duplicateCount => _duplicatePaths.length;
  int get readOnlyCount => _readOnlyCount;
  bool get scanning => _scanning;
  int get scanFound => _scanFound;
  int get scanTotal => _scanTotal;
  String? get folderPath => _folderPath;
  String get searchQuery => _searchQuery;
  SortOrder get sortOrder => _sortOrder;

  /// Non-fatal problems collected during the most recent scan (unreadable
  /// CUE sheets, OPF parse failures, inaccessible folders…).
  List<String> get scanWarnings => List.unmodifiable(_scanWarnings);

  List<Audiobook> get filteredBooks {
    final cached = _filteredCache;
    if (cached != null) return cached;
    final q = _searchQuery.toLowerCase();
    var list = q.isEmpty
        ? _books
        : _books.where((b) {
            return (b.title ?? '').toLowerCase().contains(q) ||
                (b.author ?? '').toLowerCase().contains(q) ||
                (b.narrator ?? '').toLowerCase().contains(q) ||
                (b.series ?? '').toLowerCase().contains(q);
          }).toList();
    if (_showDuplicatesOnly) {
      list = list.where((b) => _duplicatePaths.contains(b.path)).toList();
    }
    if (_showMissingCoverOnly) {
      list = list
          .where((b) => b.coverImagePath == null && b.coverImageBytes == null)
          .toList();
    }
    if (_showReadOnlyOnly) {
      list = list.where((b) => _readOnlyPaths.contains(b.path)).toList();
    }
    if (_showMissingChaptersOnly) {
      list = list.where((b) => _missingChaptersPaths.contains(b.path)).toList();
    }
    list = List.of(list);
    list.sort((a, b) {
      switch (_sortOrder) {
        case SortOrder.titleAsc:
          return (a.title ?? '').toLowerCase().compareTo((b.title ?? '').toLowerCase());
        case SortOrder.titleDesc:
          return (b.title ?? '').toLowerCase().compareTo((a.title ?? '').toLowerCase());
        case SortOrder.authorAsc:
          return (a.author ?? '').toLowerCase().compareTo((b.author ?? '').toLowerCase());
        case SortOrder.authorDesc:
          return (b.author ?? '').toLowerCase().compareTo((a.author ?? '').toLowerCase());
        case SortOrder.seriesAsc:
          final as_ = a.series?.toLowerCase() ?? '';
          final bs_ = b.series?.toLowerCase() ?? '';
          if (as_.isEmpty && bs_.isEmpty) return 0;
          if (as_.isEmpty) return 1;
          if (bs_.isEmpty) return -1;
          return as_.compareTo(bs_);
        case SortOrder.narratorAsc:
          return (a.narrator ?? '').toLowerCase().compareTo((b.narrator ?? '').toLowerCase());
        case SortOrder.durationAsc:
          return (a.duration ?? Duration.zero).compareTo(b.duration ?? Duration.zero);
        case SortOrder.durationDesc:
          return (b.duration ?? Duration.zero).compareTo(a.duration ?? Duration.zero);
      }
    });
    _filteredCache = list;
    return list;
  }

  List<Audiobook>? _filteredCache;

  /// Any state change invalidates the derived filtered/sorted list cache.
  @override
  void notifyListeners() {
    _filteredCache = null;
    super.notifyListeners();
  }

  // ── Mutations ─────────────────────────────────────────────────────────────

  void setSearchQuery(String q) {
    _searchQuery = q;
    notifyListeners();
  }

  void setSortOrder(SortOrder order) {
    _sortOrder = order;
    PreferencesService.saveSortOrder(order);
    notifyListeners();
  }

  void toggleShowDuplicates() {
    _showDuplicatesOnly = !_showDuplicatesOnly;
    notifyListeners();
  }

  void toggleShowMissingCover() {
    _showMissingCoverOnly = !_showMissingCoverOnly;
    notifyListeners();
  }

  void toggleShowReadOnly() {
    _showReadOnlyOnly = !_showReadOnlyOnly;
    notifyListeners();
  }

  void toggleShowMissingChapters() {
    _showMissingChaptersOnly = !_showMissingChaptersOnly;
    notifyListeners();
  }

  void _recomputeFlags() {
    _missingCoverPaths.clear();
    for (final b in _books) {
      if (b.coverImagePath == null && b.coverImageBytes == null) {
        _missingCoverPaths.add(b.path);
      }
    }
    _duplicatePaths.clear();
    final keyToBooks = <String, List<String>>{};
    for (final b in _books) {
      if ((b.title ?? '').isEmpty && (b.author ?? '').isEmpty) continue;
      final key = '${b.title ?? ''}${b.author ?? ''}'
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
      (keyToBooks[key] ??= []).add(b.path);
    }
    for (final paths in keyToBooks.values) {
      if (paths.length > 1) _duplicatePaths.addAll(paths);
    }
    _readOnlyPaths.clear();
    for (final b in _books) {
      if (b.readOnlyStatus != ReadOnlyStatus.writable) {
        _readOnlyPaths.add(b.path);
      }
    }
    _readOnlyCount = _readOnlyPaths.length;
    _missingChaptersPaths.clear();
    for (final b in _books) {
      // Single-file books with no embedded/CUE chapters have no chapter
      // navigation at all; multi-file books implicitly have one per file.
      if (b.audioFiles.length == 1 && b.chapters.isEmpty) {
        _missingChaptersPaths.add(b.path);
      }
    }
  }

  /// Selects the book that follows [path] in the current filtered view —
  /// used by the apply-and-next workflow.
  void selectNextAfter(String path) {
    final list = filteredBooks;
    final idx = list.indexWhere((b) => b.path == path);
    if (idx == -1 || idx + 1 >= list.length) return;
    selectBook(list[idx + 1]);
  }

  void selectBook(Audiobook book) {
    _selected = book;
    PreferencesService.saveLastBook(book.path);
    notifyListeners();
  }

  /// Toggles a book's batch-selection checkbox. Per PRD-28 this must not
  /// change which book is shown in the detail panel.
  void toggleBatch(Audiobook book, {required bool selected}) {
    if (selected) {
      _batchPaths.add(book.path);
    } else {
      _batchPaths.remove(book.path);
    }
    notifyListeners();
  }

  /// Clear all batch selections.
  void clearBatchSelection() {
    _batchPaths.clear();
    notifyListeners();
  }

  /// Number of books currently selected for batch editing.
  int get batchSelectionCount => _batchPaths.length;

  void markDirty(String path, {required bool dirty}) {
    if (dirty) {
      _dirtyPaths.add(path);
    } else {
      _dirtyPaths.remove(path);
    }
    notifyListeners();
  }

  // ── Async operations ──────────────────────────────────────────────────────

  /// Starts scanning [folderPath]. Any previously running scan is cancelled.
  Future<void> pickFolder(String folderPath) async {
    final generation = ++_scanGeneration;
    _scanning = true;
    _books = [];
    _selected = null;
    _folderPath = folderPath;
    _scanFound = 0;
    _scanTotal = 0;
    _scanWarnings = const [];
    notifyListeners();

    final books = await _scanner.scanFolder(
      folderPath,
      cancelled: () => generation != _scanGeneration,
      onBookFound: (book) {
        if (generation != _scanGeneration) return;
        _books = [..._books, book];
        notifyListeners();
      },
      onProgress: (found, total) {
        if (generation != _scanGeneration) return;
        _scanFound = found;
        _scanTotal = total;
        notifyListeners();
      },
    );

    if (generation != _scanGeneration) return; // superseded or cancelled

    _books = books;
    _scanning = false;
    _scanFound = 0;
    _scanTotal = 0;
    _dirtyPaths.clear();
    _batchPaths.clear();
    _searchQuery = '';
    _recomputeFlags();
    _captureScanWarnings();
    await PreferencesService.saveFolder(folderPath);

    // Restore the previously selected book when it still exists.
    final lastBook = await PreferencesService.loadLastBook();
    if (lastBook != null) {
      final match = _books.where((b) => b.path == lastBook).firstOrNull;
      if (match != null) {
        _selected = match;
      } else {
        await PreferencesService.clearLastBook();
      }
    }
    notifyListeners();
  }

  /// Cancels an in-progress scan. Books found so far are kept and the UI
  /// leaves the scanning state.
  void cancelScan() {
    if (!_scanning) return;
    _scanGeneration++;
    _scanning = false;
    _scanFound = 0;
    _scanTotal = 0;
    _recomputeFlags();
    _captureScanWarnings();
    notifyListeners();
  }

  void _captureScanWarnings() {
    final warnings = List<String>.of(_scanner.lastRunWarnings);
    _scanWarnings = warnings;
  }

  // ── Undo / redo ───────────────────────────────────────────────────────────

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  String? get topUndoLabel =>
      _undoStack.isEmpty ? null : _undoStack.last.label;
  String? get topRedoLabel =>
      _redoStack.isEmpty ? null : _redoStack.last.label;

  void _pushUndo(_UndoEntry entry) {
    _undoStack.add(entry);
    if (_undoStack.length > _maxUndoEntries) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  /// Restores [books] into state (matching by path).
  void _restoreBooks(List<Audiobook> books) {
    for (final b in books) {
      final path = b.path;
      _books = [for (final cur in _books) cur.path == path ? b : cur];
    }
    _recomputeFlags();
  }

  Future<void> undo() async {
    if (_undoStack.isEmpty) return;
    final entry = _undoStack.removeLast();

    if (entry.rename != null) {
      try {
        await Directory(entry.rename!.to).rename(entry.rename!.from);
      } catch (e) {
        AppLog.e('Undo rename failed (${entry.rename!.to} → '
            '${entry.rename!.from}): $e');
        _undoStack.add(entry);
        notifyListeners();
        return;
      }
    }

    // The entry already encodes both directions: `before` is restored by
    // undo (renaming to→from), `after` by redo (renaming from→to).
    _redoStack.add(entry);

    _restoreBooks(entry.before);
    // Point the selection at the restored state.
    if (entry.before.isNotEmpty) {
      final path = entry.before.first.path;
      if (_books.any((b) => b.path == path)) {
        _selected = _books.firstWhere((b) => b.path == path);
      }
    }
    // Best-effort tag write-back for plain applies so disk matches memory.
    if (entry.rename == null && entry.before.isNotEmpty) {
      try {
        await (_applySnapshot ?? MetadataWriter.applyMetadata)(
            entry.before.first);
      } catch (e) {
        AppLog.e('Undo write-back failed: $e');
      }
    }
    notifyListeners();
  }

  Future<void> redo() async {
    if (_redoStack.isEmpty) return;
    final entry = _redoStack.removeLast();

    if (entry.rename != null) {
      try {
        await Directory(entry.rename!.from).rename(entry.rename!.to);
      } catch (e) {
        AppLog.e('Redo rename failed: $e');
        _redoStack.add(entry);
        notifyListeners();
        return;
      }
    }

    _undoStack.add(entry);

    _restoreBooks(entry.after);
    if (entry.after.isNotEmpty) {
      final path = entry.after.first.path;
      if (_books.any((b) => b.path == path)) {
        _selected = _books.firstWhere((b) => b.path == path);
      }
    }
    notifyListeners();
  }

  void clearHistory() {
    _undoStack.clear();
    _redoStack.clear();
    notifyListeners();
  }

  void onBookApplied(Audiobook updated) {
    final before = _selected;
    if (before != null) {
      _pushUndo(_UndoEntry(
        before: [before],
        after: [updated],
        label: 'Apply tags',
      ));
    }
    _books = [for (final b in _books) b.path == updated.path ? updated : b];
    _selected = updated;
    _dirtyPaths.remove(updated.path);
    _recomputeFlags();
    notifyListeners();
  }

  Future<void> rescanSelected() async {
    final book = _selected;
    if (book == null) return;
    final rescanned = await _scanner.scanBook(book.path);
    if (rescanned == null) return;
    _pushUndo(_UndoEntry(
      before: [book],
      after: [rescanned],
      label: 'Rescan from disk',
    ));
    _books = [
      for (final b in _books) b.path == rescanned.path ? rescanned : b
    ];
    _selected = rescanned;
    _dirtyPaths.remove(rescanned.path);
    _recomputeFlags();
    _captureScanWarnings();
    notifyListeners();
  }

  void onBatchApplied(List<Audiobook> updated) {
    final before = [
      for (final u in updated)
        _books.firstWhere((b) => b.path == u.path, orElse: () => u),
    ];
    _pushUndo(_UndoEntry(
      before: before,
      after: List.of(updated),
      label: 'Batch edit (${updated.length})',
    ));
    for (final u in updated) {
      _books = [for (final b in _books) b.path == u.path ? u : b];
    }
    _batchPaths.clear();
    // Batch applies can change covers/tags — refresh derived flag sets.
    _recomputeFlags();
    notifyListeners();
  }

  void onBookRenamed(String oldPath, String newPath) {
    final book = _books.firstWhere((b) => b.path == oldPath);
    final beforeBook = book;
    final updatedBook = book.copyWith(
      path: newPath,
      coverImagePath:
          book.coverImagePath?.replaceFirst(oldPath, newPath),
      audioFiles:
          book.audioFiles.map((f) => f.replaceFirst(oldPath, newPath)).toList(),
    );
    _pushUndo(_UndoEntry(
      before: [beforeBook],
      after: [updatedBook],
      label: 'Rename folder',
      rename: (from: oldPath, to: newPath),
    ));
    _books = [
      for (final b in _books) b.path == oldPath ? updatedBook : b
    ];
    if (_selected?.path == oldPath) {
      _selected = updatedBook;
    }
    _dirtyPaths.remove(oldPath);
    notifyListeners();
  }
}
