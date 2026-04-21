import 'package:flutter/foundation.dart';
import 'package:audiovault_editor/models/audiobook.dart';
import 'package:audiovault_editor/services/metadata_writer.dart';
import 'package:audiovault_editor/services/scanner_service.dart';

enum SortOrder { titleAsc, titleDesc, authorAsc, authorDesc, seriesAsc, narratorAsc, durationAsc, durationDesc }

class LibraryController extends ChangeNotifier {
  final _scanner = ScannerService();

  List<Audiobook> _books = [];
  Audiobook? _selected;
  Audiobook? _undoSnapshot;
  final Set<String> _dirtyPaths = {};
  final Set<String> _batchPaths = {};
  final Set<String> _duplicatePaths = {};
  final Set<String> _missingCoverPaths = {};
  bool _showDuplicatesOnly = false;
  bool _showMissingCoverOnly = false;
  bool _scanning = false;
  int _scanFound = 0;
  int _scanTotal = 0;
  String? _folderPath;
  String _searchQuery = '';
  SortOrder _sortOrder = SortOrder.titleAsc;

  // ── Read-only accessors ───────────────────────────────────────────────────

  List<Audiobook> get books => _books;
  Audiobook? get selected => _selected;
  Audiobook? get undoSnapshot => _undoSnapshot;
  Set<String> get dirtyPaths => Set.unmodifiable(_dirtyPaths);
  Set<String> get batchPaths => Set.unmodifiable(_batchPaths);
  Set<String> get duplicatePaths => Set.unmodifiable(_duplicatePaths);
  Set<String> get missingCoverPaths => Set.unmodifiable(_missingCoverPaths);
  bool get showDuplicatesOnly => _showDuplicatesOnly;
  bool get showMissingCoverOnly => _showMissingCoverOnly;
  int get missingCoverCount => _missingCoverPaths.length;
  int get duplicateCount => _duplicatePaths.length;
  bool get scanning => _scanning;
  int get scanFound => _scanFound;
  int get scanTotal => _scanTotal;
  String? get folderPath => _folderPath;
  String get searchQuery => _searchQuery;
  SortOrder get sortOrder => _sortOrder;

  List<Audiobook> get filteredBooks {
    final q = _searchQuery.toLowerCase();
    var list = q.isEmpty
        ? _books
        : _books.where((b) {
            return (b.title ?? '').toLowerCase().contains(q) ||
                (b.author ?? '').toLowerCase().contains(q);
          }).toList();
    if (_showDuplicatesOnly) {
      list = list.where((b) => _duplicatePaths.contains(b.path)).toList();
    }
    if (_showMissingCoverOnly) {
      list = list
          .where((b) => b.coverImagePath == null && b.coverImageBytes == null)
          .toList();
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
    return list;
  }

  // ── Mutations ─────────────────────────────────────────────────────────────

  void setSearchQuery(String q) {
    _searchQuery = q;
    notifyListeners();
  }

  void setSortOrder(SortOrder order) {
    _sortOrder = order;
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
  }

  void selectBook(Audiobook book) {
    _selected = book;
    notifyListeners();
  }

  void toggleBatch(Audiobook book, {required bool selected}) {
    if (selected) {
      _batchPaths.add(book.path);
      _selected = book;
    } else {
      _batchPaths.remove(book.path);
    }
    notifyListeners();
  }

  void markDirty(String path, {required bool dirty}) {
    if (dirty) {
      _dirtyPaths.add(path);
    } else {
      _dirtyPaths.remove(path);
    }
    notifyListeners();
  }

  // ── Async operations ──────────────────────────────────────────────────────

  Future<void> pickFolder(String folderPath) async {
    _scanning = true;
    _books = [];
    _selected = null;
    _folderPath = folderPath;
    _scanFound = 0;
    _scanTotal = 0;
    notifyListeners();

    final books = await _scanner.scanFolder(
      folderPath,
      onBookFound: (book) {
        _books = [..._books, book];
        notifyListeners();
      },
      onProgress: (found, total) {
        _scanFound = found;
        _scanTotal = total;
        notifyListeners();
      },
    );

    _books = books;
    _scanning = false;
    _scanFound = 0;
    _scanTotal = 0;
    _dirtyPaths.clear();
    _batchPaths.clear();
    _searchQuery = '';
    _recomputeFlags();
    notifyListeners();
  }

  void onBookApplied(Audiobook updated) {
    _undoSnapshot = _selected;
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
    _books = [
      for (final b in _books) b.path == rescanned.path ? rescanned : b
    ];
    _selected = rescanned;
    _undoSnapshot = null;
    _dirtyPaths.remove(rescanned.path);
    notifyListeners();
  }

  Future<void> undo() async {
    final snapshot = _undoSnapshot;
    if (snapshot == null) return;
    await MetadataWriter.applyMetadata(snapshot);
    _books = [
      for (final b in _books) b.path == snapshot.path ? snapshot : b
    ];
    _selected = snapshot;
    _undoSnapshot = null;
    _dirtyPaths.remove(snapshot.path);
    notifyListeners();
  }

  void onBatchApplied(List<Audiobook> updated) {
    for (final u in updated) {
      _books = [for (final b in _books) b.path == u.path ? u : b];
    }
    _batchPaths.clear();
    notifyListeners();
  }
}
