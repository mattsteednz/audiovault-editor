import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';
import 'models/audiobook.dart';
import 'services/metadata_writer.dart';
import 'services/scanner_service.dart';
import 'screens/book_detail_screen.dart';
import 'screens/batch_edit_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  runApp(const AudioVaultEditorApp());
}

class AudioVaultEditorApp extends StatelessWidget {
  const AudioVaultEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AudioVault Editor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _SortOrder { titleAsc, titleDesc, authorAsc, authorDesc }

class _HomeScreenState extends State<HomeScreen> {
  final _scanner = ScannerService();
  List<Audiobook> _books = [];
  Audiobook? _selected;
  Audiobook? _undoSnapshot;
  final Set<String> _dirtyPaths = {};
  final Set<String> _batchPaths = {};
  bool _scanning = false;
  String? _folderPath;
  String _searchQuery = '';
  _SortOrder _sortOrder = _SortOrder.titleAsc;
  final _searchCtrl = TextEditingController();

  List<Audiobook> get _filteredBooks {
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
        case _SortOrder.titleAsc:
          return (a.title ?? '').toLowerCase().compareTo((b.title ?? '').toLowerCase());
        case _SortOrder.titleDesc:
          return (b.title ?? '').toLowerCase().compareTo((a.title ?? '').toLowerCase());
        case _SortOrder.authorAsc:
          return (a.author ?? '').toLowerCase().compareTo((b.author ?? '').toLowerCase());
        case _SortOrder.authorDesc:
          return (b.author ?? '').toLowerCase().compareTo((a.author ?? '').toLowerCase());
      }
    });
    return list;
  }

  Future<void> _pickFolder() async {
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select audiobook library folder',
    );
    if (result == null) return;

    setState(() {
      _scanning = true;
      _books = [];
      _selected = null;
      _folderPath = result;
    });
    windowManager.setTitle('AudioVault Editor — ${p.basename(result)}');

    final books = await _scanner.scanFolder(result, onBookFound: (book) {
      setState(() {
        _books = [..._books, book];
      });
    });

    setState(() {
      _books = books;
      _scanning = false;
      _dirtyPaths.clear();
      _batchPaths.clear();
      _searchQuery = '';
      _searchCtrl.clear();
    });
  }

  void _onBookApplied(Audiobook updated) {
    setState(() {
      _undoSnapshot = _selected; // save pre-apply state
      _books = [for (final b in _books) b.path == updated.path ? updated : b];
      _selected = updated;
      _dirtyPaths.remove(updated.path);
    });
  }

  Future<void> _onBookRescan() async {
    final book = _selected;
    if (book == null) return;
    final rescanned = await _scanner.scanBook(book.path);
    if (rescanned == null) return;
    setState(() {
      _books = [for (final b in _books) b.path == rescanned.path ? rescanned : b];
      _selected = rescanned;
      _undoSnapshot = null;
      _dirtyPaths.remove(rescanned.path);
    });
  }

  Future<void> _onUndo() async {
    final snapshot = _undoSnapshot;
    if (snapshot == null) return;
    await MetadataWriter.applyMetadata(snapshot);
    setState(() {
      _books = [for (final b in _books) b.path == snapshot.path ? snapshot : b];
      _selected = snapshot;
      _undoSnapshot = null;
      _dirtyPaths.remove(snapshot.path);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          ExcludeFocus(
            child: SizedBox(
              width: 300,
              child: Column(
                children: [
                  _buildToolbar(),
                  Expanded(child: _buildBookList()),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          // Detail
          Expanded(
            child: FocusScope(
              child: _batchPaths.length >= 2
                  ? BatchEditScreen(
                      key: ValueKey(_batchPaths.join()),
                      books: _books
                          .where((b) => _batchPaths.contains(b.path))
                          .toList(),
                      onApplied: (updated) {
                        setState(() {
                          for (final u in updated) {
                            _books = [for (final b in _books) b.path == u.path ? u : b];
                          }
                          _batchPaths.clear();
                        });
                      },
                    )
                  : _selected != null
                      ? BookDetailScreen(
                          key: ValueKey(_selected!.path),
                          book: _selected!,
                          onApply: _onBookApplied,
                          onRescan: _onBookRescan,
                          onUndo: _undoSnapshot?.path == _selected!.path
                              ? _onUndo
                              : null,
                          onDirtyChanged: (dirty) {
                            setState(() {
                              if (dirty) {
                                _dirtyPaths.add(_selected!.path);
                              } else {
                                _dirtyPaths.remove(_selected!.path);
                              }
                            });
                          },
                        )
                      : const Center(
                          child: Text('Select a book to view metadata',
                              style: TextStyle(color: Colors.grey)),
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: _scanning ? null : _pickFolder,
            icon: const Icon(Icons.folder_open),
            label: const Text('Open Folder'),
          ),
          if (_folderPath != null) ...
            [
              const SizedBox(height: 8),
              Text(
                _folderPath!,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _searchQuery = v),
                      decoration: const InputDecoration(
                        hintText: 'Search...',
                        isDense: true,
                        prefixIcon: Icon(Icons.search, size: 16),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  PopupMenuButton<_SortOrder>(
                    tooltip: 'Sort',
                    icon: const Icon(Icons.sort, size: 18),
                    onSelected: (v) => setState(() => _sortOrder = v),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: _SortOrder.titleAsc,
                          child: Text('Title A–Z')),
                      PopupMenuItem(
                          value: _SortOrder.titleDesc,
                          child: Text('Title Z–A')),
                      PopupMenuItem(
                          value: _SortOrder.authorAsc,
                          child: Text('Author A–Z')),
                      PopupMenuItem(
                          value: _SortOrder.authorDesc,
                          child: Text('Author Z–A')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${_filteredBooks.length} of ${_books.length} book(s)',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          if (_scanning)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _buildBookList() {
    final books = _filteredBooks;
    if (books.isEmpty && !_scanning) {
      return const Center(
        child: Text('No books loaded', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        final isSelected = _selected?.path == book.path;
        return CheckboxListTile(
          value: _batchPaths.contains(book.path),
          onChanged: (checked) => setState(() {
            if (checked == true) {
              _batchPaths.add(book.path);
              _selected = book;
            } else {
              _batchPaths.remove(book.path);
            }
          }),
          selected: isSelected,
          selectedTileColor: Colors.white10,
          controlAffinity: ListTileControlAffinity.leading,
          title: Row(
            children: [
              if (_dirtyPaths.contains(book.path))
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.circle, size: 8, color: Colors.orange),
                ),
              Expanded(
                child: Text(book.title ?? '',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          subtitle: Text(
            book.author ?? 'Unknown author',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          dense: true,
        );
      },
    );
  }
}
