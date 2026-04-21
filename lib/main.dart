import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';
import 'package:audiovault_editor/controllers/library_controller.dart';
import 'package:audiovault_editor/screens/book_detail_screen.dart';
import 'package:audiovault_editor/screens/batch_edit_screen.dart';
import 'package:audiovault_editor/services/preferences_service.dart';
import 'package:audiovault_editor/widgets/sort_button.dart';
import 'package:audiovault_editor/widgets/cover_thumbnail.dart';
import 'package:audiovault_editor/widgets/batch_selection_banner.dart';
import 'package:audiovault_editor/widgets/resizable_sidebar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // Restore window bounds
  final bounds = await PreferencesService.loadWindowBounds();
  if (bounds != null) {
    await windowManager.setBounds(bounds);
  }

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

class _HomeScreenState extends State<HomeScreen> with WindowListener {
  final _ctrl = LibraryController();
  final _searchCtrl = TextEditingController();
  final _searchFocusNode = FocusNode();
  String? _folderLoadError;
  double _sidebarWidth = 300;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onControllerChanged);
    windowManager.addListener(this);
    _searchCtrl.addListener(_onSearchChanged);
    _restorePreferences();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _ctrl.removeListener(_onControllerChanged);
    _ctrl.dispose();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void onWindowClose() async {
    final bounds = await windowManager.getBounds();
    await PreferencesService.saveWindowBounds(bounds);
  }

  Future<void> _restorePreferences() async {
    // Restore sort order
    final sortOrder = await PreferencesService.loadSortOrder();
    if (sortOrder != null) {
      _ctrl.setSortOrder(sortOrder);
    }

    // Restore sidebar width
    final sidebarWidth = await PreferencesService.loadSidebarWidth();
    if (sidebarWidth != null && mounted) {
      setState(() => _sidebarWidth = sidebarWidth);
    }

    // Restore folder path
    final folderPath = await PreferencesService.loadFolder();
    if (folderPath != null) {
      if (await Directory(folderPath).exists()) {
        windowManager.setTitle('AudioVault Editor — ${p.basename(folderPath)}');
        await _ctrl.pickFolder(folderPath);
      } else {
        setState(() {
          _folderLoadError = 'Library folder not found: $folderPath';
        });
        await PreferencesService.clearFolder();
      }
    }
  }

  void _dismissError() {
    setState(() {
      _folderLoadError = null;
    });
  }

  void _onControllerChanged() => setState(() {});

  void _onSearchChanged() => setState(() {});

  Future<void> _pickFolder() async {
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select audiobook library folder',
    );
    if (result == null) return;
    windowManager.setTitle('AudioVault Editor — ${p.basename(result)}');
    _searchCtrl.clear();
    await _ctrl.pickFolder(result);
  }

  void _clearSearch() {
    _searchCtrl.clear();
    _ctrl.setSearchQuery('');
    _searchFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final hasBatchBanner = _ctrl.batchPaths.length >= 2;

    return Scaffold(
      body: Column(
        children: [
          if (_folderLoadError != null)
            MaterialBanner(
              content: Text(_folderLoadError!),
              actions: [
                TextButton(
                  onPressed: _dismissError,
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          Expanded(
            child: Row(
              children: [
                // ── Resizable sidebar ──
                ExcludeFocus(
                  child: ResizableSidebar(
                    initialWidth: _sidebarWidth,
                    onWidthChanged: (w) {
                      setState(() => _sidebarWidth = w);
                      PreferencesService.saveSidebarWidth(w);
                    },
                    child: Column(
                      children: [
                        _buildToolbar(),
                        Expanded(child: _buildBookList()),
                      ],
                    ),
                  ),
                ),
                // ── Detail panel ──
                Expanded(
                  child: Column(
                    children: [
                      // Batch selection banner
                      if (hasBatchBanner)
                        BatchSelectionBanner(
                          selectionCount: _ctrl.batchPaths.length,
                          onClearSelection: _ctrl.clearBatchSelection,
                          onEditAll: () {
                            // Banner is shown when batchPaths >= 2, which already
                            // triggers BatchEditScreen below — just a no-op here
                            // since the screen switches automatically.
                          },
                        ),
                      Expanded(
                        child: FocusScope(
                          child: _ctrl.batchPaths.length >= 2
                              ? BatchEditScreen(
                                  key: ValueKey(_ctrl.batchPaths.join()),
                                  books: _ctrl.books
                                      .where((b) =>
                                          _ctrl.batchPaths.contains(b.path))
                                      .toList(),
                                  onApplied: _ctrl.onBatchApplied,
                                )
                              : _ctrl.selected != null
                                  ? BookDetailScreen(
                                      key: ValueKey(_ctrl.selected!.path),
                                      book: _ctrl.selected!,
                                      allBooks: _ctrl.books,
                                      onApply: _ctrl.onBookApplied,
                                      onRescan: _ctrl.rescanSelected,
                                      onUndo: _ctrl.undoSnapshot?.path ==
                                              _ctrl.selected!.path
                                          ? _ctrl.undo
                                          : null,
                                      onDirtyChanged: (dirty) => _ctrl
                                          .markDirty(_ctrl.selected!.path,
                                              dirty: dirty),
                                      onRenamed: _ctrl.onBookRenamed,
                                    )
                                  : const Center(
                                      child: Text(
                                          'Select a book to view metadata',
                                          style:
                                              TextStyle(color: Colors.grey)),
                                    ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
            // Search field with clear button
            TextField(
              controller: _searchCtrl,
              focusNode: _searchFocusNode,
              onChanged: _ctrl.setSearchQuery,
              decoration: InputDecoration(
                hintText: 'Search...',
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 16),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        tooltip: 'Clear search',
                        onPressed: _clearSearch,
                      )
                    : null,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            // Sort button showing current order
            Align(
              alignment: Alignment.centerLeft,
              child: SortButton(
                currentOrder: _ctrl.sortOrder,
                onOrderChanged: _ctrl.setSortOrder,
              ),
            ),
            const SizedBox(height: 4),
            if (_ctrl.scanning)
              Text(
                'Scanning\u2026 ${_ctrl.scanFound} book(s) found',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              )
            else
              Text(
                '${_ctrl.filteredBooks.length} of ${_ctrl.books.length} book(s)',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            const SizedBox(height: 6),
            // Filter chips — always visible, disabled when count is 0
            Wrap(
              spacing: 4,
              children: [
                FilterChip(
                  label: Text('Dupes (${_ctrl.duplicateCount})'),
                  selected: _ctrl.showDuplicatesOnly,
                  onSelected: _ctrl.duplicateCount > 0
                      ? (_) => _ctrl.toggleShowDuplicates()
                      : null,
                  labelStyle: const TextStyle(fontSize: 11),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                FilterChip(
                  label: Text('No cover (${_ctrl.missingCoverCount})'),
                  selected: _ctrl.showMissingCoverOnly,
                  onSelected: _ctrl.missingCoverCount > 0
                      ? (_) => _ctrl.toggleShowMissingCover()
                      : null,
                  labelStyle: const TextStyle(fontSize: 11),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
          if (_ctrl.scanning)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(
                value: _ctrl.scanTotal > 0
                    ? _ctrl.scanFound / _ctrl.scanTotal
                    : null,
              ),
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
        final isChecked = _ctrl.batchPaths.contains(book.path);
        return ListTile(
          selected: isSelected,
          selectedTileColor: Colors.white10,
          dense: true,
          onTap: () => _ctrl.selectBook(book),
          // Cover thumbnail as leading
          leading: CoverThumbnail(book: book),
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
                  child: Icon(Icons.warning_amber,
                      size: 12, color: Colors.amber),
                ),
              if (_ctrl.missingCoverPaths.contains(book.path))
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.image_not_supported,
                      size: 12, color: Colors.grey),
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
          // Checkbox in trailing position (Gmail pattern)
          trailing: Checkbox(
            value: isChecked,
            onChanged: (checked) {
              _ctrl.toggleBatch(book, selected: checked == true);
            },
          ),
        );
      },
    );
  }
}
