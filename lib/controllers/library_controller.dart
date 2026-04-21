import 'package:flutter/foundation.dart';
import 'package:audiovault_editor/models/audiobook.dart';
import 'package:audiovault_editor/services/metadata_writer.dart';
import 'package:audiovault_editor/services/scanner_service.dart';

enum SortOrder { titleAsc, titleDesc, authorAsc, authorDesc }

class LibraryController extends ChangeNotifier {
  final _scanner = ScannerService();

  List<Audiobook> _books = [];
  Audiobook? _selected;
  Audiobook? _undoSnapshot;
  final Set<String> _dirtyPaths = {};
  final Set<String> _batchPaths = {};
  bool _scanning = false;
  String? _folderPath;
  String _searchQuery = '';
  SortOrder _sortOrder = SortOrder.titleAsc;

  // ── Read-only accessors ───────────────────────────────────────────────────

  List<Audiobook> get books => _books;
  Audiobook? get selected => _selected;
  Audiobook? get undoSnapshot => _undoSnapshot;
  Set<String> get dirtyPaths => Set.unmodifiable(_dirtyPaths);
  Set<String> get batchPaths => Set.unmodifiable(_batchPaths);
  bool get scanning => _scanning;
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
    list = List.of(list);
    list.sort((a, b) {
      switch (_sortOrder) {
        case SortOrder.titleAsc:
          return (a.title ?? '')
              .toLowerCase()
              .compareTo((b.title ?? '').toLowerCase());
        case SortOrder.titleDesc:
          return (b.title ?? '')
              .toLowerCase()
              .compareTo((a.title ?? '').toLowerCase());
        case SortOrder.authorAsc:
          return (a.author ?? '')
              .toLowerCase()
              .compareTo((b.author ?? '').toLowerCase());
        case SortOrder.authorDesc:
          return (b.author ?? '')
              .toLowerCase()
              .compareTo((a.author ?? '').toLowerCase());
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
    notifyListeners();

    final books = await _scanner.scanFolder(folderPath, onBookFound: (book) {
      _books = [..._books, book];
      notifyListeners();
    });

    _books = books;
    _scanning = false;
    _dirtyPaths.clear();
    _batchPaths.clear();
    _searchQuery = '';
    notifyListeners();
  }

  void onBookApplied(Audiobook updated) {
    _undoSnapshot = _selected;
    _books = [for (final b in _books) b.path == updated.path ? updated : b];
    _selected = updated;
    _dirtyPaths.remove(updated.path);
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
