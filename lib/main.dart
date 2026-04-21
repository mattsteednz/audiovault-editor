import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';
import 'package:audiovault_editor/controllers/library_controller.dart';
import 'package:audiovault_editor/screens/book_detail_screen.dart';
import 'package:audiovault_editor/screens/batch_edit_screen.dart';

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

class _HomeScreenState extends State<HomeScreen> {
  final _ctrl = LibraryController();
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onControllerChanged);
    _ctrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onControllerChanged() => setState(() {});

  Future<void> _pickFolder() async {
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select audiobook library folder',
    );
    if (result == null) return;
    windowManager.setTitle('AudioVault Editor — ${p.basename(result)}');
    _searchCtrl.clear();
    await _ctrl.pickFolder(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
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
          Expanded(
            child: FocusScope(
              child: _ctrl.batchPaths.length >= 2
                  ? BatchEditScreen(
                      key: ValueKey(_ctrl.batchPaths.join()),
                      books: _ctrl.books
                          .where((b) => _ctrl.batchPaths.contains(b.path))
                          .toList(),
                      onApplied: _ctrl.onBatchApplied,
                    )
                  : _ctrl.selected != null
                      ? BookDetailScreen(
                          key: ValueKey(_ctrl.selected!.path),
                          book: _ctrl.selected!,
                          onApply: _ctrl.onBookApplied,
                          onRescan: _ctrl.rescanSelected,
                          onUndo: _ctrl.undoSnapshot?.path ==
                                  _ctrl.selected!.path
                              ? _ctrl.undo
                              : null,
                          onDirtyChanged: (dirty) =>
                              _ctrl.markDirty(_ctrl.selected!.path, dirty: dirty),
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
            onPressed: _ctrl.scanning ? null : _pickFolder,
            icon: const Icon(Icons.folder_open),
            label: const Text('Open Folder'),
          ),
          if (_ctrl.folderPath != null) ...[
            const SizedBox(height: 8),
            Text(
              _ctrl.folderPath!,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _ctrl.setSearchQuery,
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
                PopupMenuButton<SortOrder>(
                  tooltip: 'Sort',
                  icon: const Icon(Icons.sort, size: 18),
                  onSelected: _ctrl.setSortOrder,
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: SortOrder.titleAsc, child: Text('Title A–Z')),
                    PopupMenuItem(
                        value: SortOrder.titleDesc, child: Text('Title Z–A')),
                    PopupMenuItem(
                        value: SortOrder.authorAsc, child: Text('Author A–Z')),
                    PopupMenuItem(
                        value: SortOrder.authorDesc,
                        child: Text('Author Z–A')),
                    PopupMenuItem(
                        value: SortOrder.seriesAsc, child: Text('Series A–Z')),
                    PopupMenuItem(
                        value: SortOrder.narratorAsc,
                        child: Text('Narrator A–Z')),
                    PopupMenuItem(
                        value: SortOrder.durationAsc,
                        child: Text('Duration ↑')),
                    PopupMenuItem(
                        value: SortOrder.durationDesc,
                        child: Text('Duration ↓')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${_ctrl.filteredBooks.length} of ${_ctrl.books.length} book(s)',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            if (_ctrl.duplicateCount > 0 || _ctrl.missingCoverCount > 0) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                children: [
                  if (_ctrl.duplicateCount > 0)
                    FilterChip(
                      label: Text('Dupes (${_ctrl.duplicateCount})'),
                      selected: _ctrl.showDuplicatesOnly,
                      onSelected: (_) => _ctrl.toggleShowDuplicates(),
                      labelStyle: const TextStyle(fontSize: 11),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  if (_ctrl.missingCoverCount > 0)
                    FilterChip(
                      label: Text('No cover (${_ctrl.missingCoverCount})'),
                      selected: _ctrl.showMissingCoverOnly,
                      onSelected: (_) => _ctrl.toggleShowMissingCover(),
                      labelStyle: const TextStyle(fontSize: 11),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ],
          if (_ctrl.scanning)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _buildBookList() {
    final books = _ctrl.filteredBooks;
    if (books.isEmpty && !_ctrl.scanning) {
      return const Center(
        child: Text('No books loaded', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        final isSelected = _ctrl.selected?.path == book.path;
        return CheckboxListTile(
          value: _ctrl.batchPaths.contains(book.path),
          onChanged: (checked) {
            _ctrl.toggleBatch(book, selected: checked == true);
            if (checked != true) _ctrl.selectBook(book);
          },
          selected: isSelected,
          selectedTileColor: Colors.white10,
          controlAffinity: ListTileControlAffinity.leading,
          title: Row(
            children: [
              if (_ctrl.dirtyPaths.contains(book.path))
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
          subtitle: Row(
            children: [
              if (_ctrl.duplicatePaths.contains(book.path))
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.warning_amber, size: 12, color: Colors.amber),
                ),
              if (_ctrl.missingCoverPaths.contains(book.path))
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.image_not_supported, size: 12, color: Colors.grey),
                ),
              Expanded(
                child: Text(
                  book.author ?? 'Unknown author',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          dense: true,
        );
      },
    );
  }
}
