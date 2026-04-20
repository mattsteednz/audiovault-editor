import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'models/audiobook.dart';
import 'services/scanner_service.dart';
import 'screens/book_detail_screen.dart';

void main() {
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

class _HomeScreenState extends State<HomeScreen> {
  final _scanner = ScannerService();
  List<Audiobook> _books = [];
  Audiobook? _selected;
  // tracks which book paths have unapplied changes
  final Set<String> _dirtyPaths = {};
  bool _scanning = false;
  String? _folderPath;

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

    final books = await _scanner.scanFolder(result, onBookFound: (book) {
      setState(() {
        _books = [..._books, book];
      });
    });

    setState(() {
      _books = books;
      _scanning = false;
      _dirtyPaths.clear();
    });
  }

  void _onBookApplied(Audiobook updated) {
    setState(() {
      _books = [for (final b in _books) b.path == updated.path ? updated : b];
      _selected = updated;
      _dirtyPaths.remove(updated.path);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          SizedBox(
            width: 300,
            child: Column(
              children: [
                _buildToolbar(),
                Expanded(child: _buildBookList()),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          // Detail
          Expanded(
            child: _selected != null
                ? BookDetailScreen(
                    key: ValueKey(_selected!.path),
                    book: _selected!,
                    onApply: _onBookApplied,
                  )
                : const Center(
                    child: Text('Select a book to view metadata',
                        style: TextStyle(color: Colors.grey)),
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
          if (_folderPath != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _folderPath!,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (_scanning)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
          if (!_scanning && _books.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${_books.length} book(s)',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ),
        ],
      ),
    );
  }

  Widget _buildBookList() {
    if (_books.isEmpty && !_scanning) {
      return const Center(
        child: Text('No books loaded', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      itemCount: _books.length,
      itemBuilder: (context, index) {
        final book = _books[index];
        final isSelected = _selected?.path == book.path;
        return ListTile(
          selected: isSelected,
          selectedTileColor: Colors.white10,
          title: Row(
            children: [
              if (_dirtyPaths.contains(book.path))
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.circle, size: 8, color: Colors.orange),
                ),
              Expanded(
                child: Text(book.title,
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
          onTap: () => setState(() => _selected = book),
        );
      },
    );
  }
}
