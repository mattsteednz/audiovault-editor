import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:audiovault_editor/services/app_logger.dart';
import 'package:window_manager/window_manager.dart';
import 'package:audiovault_editor/controllers/library_controller.dart';
import 'package:audiovault_editor/models/audiobook.dart';
import 'package:audiovault_editor/screens/book_detail_screen.dart';
import 'package:audiovault_editor/screens/batch_edit_screen.dart';
import 'package:audiovault_editor/services/metadata_writer.dart';
import 'package:audiovault_editor/services/preferences_service.dart';
import 'package:audiovault_editor/services/silence_detection_service.dart';
import 'package:audiovault_editor/services/writers/atomic_file_writer.dart';
import 'package:audiovault_editor/widgets/settings_dialog.dart';
import 'package:audiovault_editor/widgets/sort_button.dart';
import 'package:audiovault_editor/widgets/cover_thumbnail.dart';
import 'package:audiovault_editor/widgets/batch_selection_banner.dart';
import 'package:audiovault_editor/widgets/resizable_sidebar.dart';
import 'package:audiovault_editor/widgets/read_only_badge.dart';

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
  const AudioVaultEditorApp({super.key, this.controller});

  /// Injectable for integration/smoke tests.
  final LibraryController? controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AudioVault Editor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
      ),
      home: HomeScreen(controller: controller),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.controller});

  /// Injectable for integration/smoke tests.
  final LibraryController? controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WindowListener {
  late final LibraryController _ctrl =
      widget.controller ?? LibraryController();
  final _searchCtrl = TextEditingController();
  final _searchFocusNode = FocusNode();
  String? _folderLoadError;
  double _sidebarWidth = 300;
  bool _advanceAfterApply = true;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onControllerChanged);
    windowManager.addListener(this);
    _searchCtrl.addListener(_onSearchChanged);
    // Intercept OS close so unsaved work can be protected.
    windowManager.setPreventClose(true);
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
    await PreferencesService.saveWindowBounds(await windowManager.getBounds());

    final dirtyCount = _ctrl.dirtyPaths.length;
    if (dirtyCount > 0 && mounted) {
      final discard = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Discard unsaved changes?'),
          content: Text(
            '$dirtyCount book(s) have unapplied edits. Closing now will '
            'discard them.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard & close'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    await windowManager.destroy();
  }

  Future<void> _restorePreferences() async {
    // Restore sort order
    final sortOrder = await PreferencesService.loadSortOrder();
    if (sortOrder != null) {
      _ctrl.setSortOrder(sortOrder);
    }

    // Restore apply-and-next preference.
    _advanceAfterApply = await PreferencesService.loadAdvanceAfterApply();

    // Restore ffmpeg override + backup setting into their live services.
    final ffmpegOverride = await PreferencesService.loadFfmpegOverride();
    if (ffmpegOverride != null) {
      SilenceDetectionService.setCustomPath(ffmpegOverride);
    }
    AtomicWriteConfig.keepBackups =
        await PreferencesService.loadKeepBackups();

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

  void _rescanLibrary() {
    final folder = _ctrl.folderPath;
    if (folder != null && !_ctrl.scanning) {
      windowManager.setTitle('AudioVault Editor — ${p.basename(folder)}');
      _ctrl.pickFolder(folder);
    }
  }

  bool _exportingOpfs = false;

  /// Writes a Calibre-compatible metadata.opf into every book folder in the
  /// current filtered view.
  Future<void> _exportOpfsForShownBooks() async {
    if (_exportingOpfs) return;
    setState(() => _exportingOpfs = true);
    final books = List.of(_ctrl.filteredBooks);
    final errors = <String>[];
    try {
      for (final b in books) {
        try {
          await MetadataWriter.exportOpf(b);
        } catch (e) {
          errors.add('${b.title ?? b.path}: $e');
        }
      }
    } finally {
      if (mounted) setState(() => _exportingOpfs = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: errors.isEmpty ? null : Colors.red[900],
      content: Text(errors.isEmpty
          ? 'Exported ${books.length} metadata.opf file(s)'
          : 'Exported with ${errors.length} error(s):\n${errors.take(5).join('\n')}'),
      duration: Duration(seconds: errors.isEmpty ? 3 : 6),
    ));
  }

  /// Bundles freshly generated OPFs for every shown book into a single .zip
  /// the user can store as a lightweight library snapshot.
  Future<void> _exportLibraryZip() async {
    if (_exportingOpfs) return;
    final books = List.of(_ctrl.filteredBooks);
    if (books.isEmpty) return;

    final stamp = DateTime.now();
    final defaultName = 'audiovault-library-'
        '${stamp.year.toString().padLeft(4, '0')}'
        '${stamp.month.toString().padLeft(2, '0')}'
        '${stamp.day.toString().padLeft(2, '0')}.zip';
    final target = await FilePicker.saveFile(
      dialogTitle: 'Save library snapshot',
      fileName: defaultName,
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (target == null) return;

    setState(() => _exportingOpfs = true);
    try {
      final archive = Archive();
      for (final b in books) {
        final folderName = p.basename(b.path);
        archive.add(ArchiveFile.string(
            '$folderName/metadata.opf', MetadataWriter.buildOpfXml(b)));
        final cover = File(p.join(b.path, 'cover.jpg'));
        if (await cover.exists()) {
          archive.add(ArchiveFile.bytes(
              '$folderName/cover.jpg', await cover.readAsBytes()));
        }
      }
      final zipBytes = ZipEncoder().encode(archive);
      await File(target).writeAsBytes(zipBytes, flush: true);
    } catch (e) {
      AppLog.e('Library snapshot export failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red[900],
          content: Text('Snapshot export failed: $e'),
        ));
      }
      return;
    } finally {
      if (mounted) setState(() => _exportingOpfs = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Exported ${books.length}-book snapshot to $target'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final hasBatchBanner = _ctrl.batchPaths.length >= 2;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyO, control: true):
            _pickFolder,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _searchFocusNode.requestFocus,
        const SingleActivator(LogicalKeyboardKey.f5): _rescanLibrary,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_searchCtrl.text.isNotEmpty) _clearSearch();
        },
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () {
          if (_ctrl.canUndo) _ctrl.undo();
        },
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): () {
          if (_ctrl.canRedo) _ctrl.redo();
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
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
                                      onUndo: _ctrl.canUndo ? _ctrl.undo : null,
                                      undoTooltip: _ctrl.topUndoLabel == null
                                          ? 'Nothing to undo'
                                          : 'Undo: ${_ctrl.topUndoLabel}',
                                      onDirtyChanged: (dirty) => _ctrl
                                          .markDirty(_ctrl.selected!.path,
                                              dirty: dirty),
                                      onRenamed: _ctrl.onBookRenamed,
                                      onNext: _advanceAfterApply
                                          ? () => _ctrl.selectNextAfter(
                                              _ctrl.selected!.path)
                                          : null,
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
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _ctrl.scanning ? null : _pickFolder,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Open Folder'),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Settings',
                child: IconButton.filledTonal(
                  onPressed: () => showSettingsDialog(context),
                  icon: const Icon(Icons.settings_outlined),
                ),
              ),
            ],
          ),
          if (_ctrl.folderPath != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _ctrl.folderPath!,
                    style:
                        const TextStyle(fontSize: 11, color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Tooltip(
                  message: 'Rescan library',
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: IconButton(
                      iconSize: 15,
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.refresh),
                      onPressed: _ctrl.scanning
                          ? null
                          : () => _ctrl.pickFolder(_ctrl.folderPath!),
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Tooltip(
                  message: 'Export library metadata',
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: _exportingOpfs
                        ? const Padding(
                            padding: EdgeInsets.all(5),
                            child: CircularProgressIndicator(strokeWidth: 1.6))
                        : PopupMenuButton<String>(
                            iconSize: 15,
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.save_alt),
                            tooltip: '',
                            onSelected: (v) {
                              if (v == 'opfs') _exportOpfsForShownBooks();
                              if (v == 'zip') _exportLibraryZip();
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                  value: 'opfs',
                                  child: Text('Write metadata.opf into each shown book folder')),
                              PopupMenuItem(
                                  value: 'zip',
                                  child: Text('Export snapshot .zip (OPFs only)')),
                            ],
                          ),
                  ),
                ),
              ],
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Scanning\u2026 ${_ctrl.scanFound} book(s) found',
                      style:
                          const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                  Tooltip(
                    message: 'Cancel scan',
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: IconButton(
                        iconSize: 14,
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.cancel_outlined),
                        onPressed: _ctrl.cancelScan,
                      ),
                    ),
                  ),
                ],
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
                FilterChip(
                  label: Text('Read-only (${_ctrl.readOnlyCount})'),
                  selected: _ctrl.showReadOnlyOnly,
                  onSelected: _ctrl.readOnlyCount > 0
                      ? (_) => _ctrl.toggleShowReadOnly()
                      : null,
                  labelStyle: const TextStyle(fontSize: 11),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                FilterChip(
                  label: Text('No chapters (${_ctrl.missingChaptersPaths.length})'),
                  selected: _ctrl.showMissingChaptersOnly,
                  onSelected: _ctrl.missingChaptersPaths.isEmpty
                      ? null
                      : (_) => _ctrl.toggleShowMissingChapters(),
                  labelStyle: const TextStyle(fontSize: 11),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (_ctrl.scanWarnings.isNotEmpty && !_ctrl.scanning) ...[
              const SizedBox(height: 4),
              Tooltip(
                textAlign: TextAlign.start,
                richMessage: TextSpan(
                  text: _ctrl.scanWarnings.take(10).join('\n'),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber,
                        size: 12, color: Colors.orange[700]),
                    const SizedBox(width: 4),
                    Text(
                      '${_ctrl.scanWarnings.length} scan warning(s)',
                      style:
                          TextStyle(fontSize: 11, color: Colors.orange[700]),
                    ),
                  ],
                ),
              ),
            ],
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
      // First-run / empty-library welcome.
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.library_music,
                size: 56, color: Colors.grey.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            const Text(
              'Welcome to AudioVault Editor',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 300,
              child: Text(
                'Open the folder that contains your audiobooks to browse, '
                'edit tags and chapters, fix covers and batch-update your '
                'library. Books are organised as folders — one per book.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 12, color: Colors.grey.shade400),
              ),
            ),
            if (_ctrl.folderPath == null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _pickFolder,
                icon: const Icon(Icons.folder_open),
                label: const Text('Open Folder'),
              ),
            ],
          ],
        ),
      );
    }

    // When sorted by series, interleave group headers so series boundaries
    // are visible at a glance.
    final showHeaders = _ctrl.sortOrder == SortOrder.seriesAsc;
    final rows = <Widget>[];
    if (showHeaders) {
      final counts = <String, int>{};
      for (final b in books) {
        final k = b.series ?? '';
        counts[k] = (counts[k] ?? 0) + 1;
      }
      String? currentGroup;
      for (final b in books) {
        final g = b.series ?? '';
        if (g != currentGroup) {
          rows.add(_buildSeriesHeader(g.isEmpty ? 'No series' : g, counts[g] ?? 0));
          currentGroup = g;
        }
        rows.add(_buildBookTile(b));
      }
    } else {
      for (final b in books) {
        rows.add(_buildBookTile(b));
      }
    }

    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index],
    );
  }

  Widget _buildSeriesHeader(String name, int count) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(
        children: [
          Text(name,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.lightBlueAccent)),
          const SizedBox(width: 6),
          Text('$count',
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildBookTile(Audiobook book) {
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
              if (_ctrl.missingChaptersPaths.contains(book.path))
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.playlist_remove,
                      size: 12, color: Colors.grey),
                ),
              if (book.readOnlyStatus != ReadOnlyStatus.writable)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: ReadOnlyBadge(),
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
  }
}
