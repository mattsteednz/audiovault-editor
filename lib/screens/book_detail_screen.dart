import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:audiovault_editor/models/audiobook.dart';
import 'package:audiovault_editor/services/metadata_writer.dart';
import 'package:audiovault_editor/widgets/copy_from_dialog.dart';

class BookDetailScreen extends StatefulWidget {
  final Audiobook book;
  final List<Audiobook> allBooks;
  final void Function(Audiobook updated) onApply;
  final void Function() onRescan;
  final void Function()? onUndo;
  final void Function(bool isDirty) onDirtyChanged;
  final void Function(String oldPath, String newPath)? onRenamed;

  const BookDetailScreen({
    super.key,
    required this.book,
    required this.allBooks,
    required this.onApply,
    required this.onRescan,
    this.onUndo,
    required this.onDirtyChanged,
    this.onRenamed,
  });

  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  late TextEditingController _titleCtrl;
  late TextEditingController _subtitleCtrl;
  late TextEditingController _authorCtrl;
  late TextEditingController _narratorCtrl;
  late TextEditingController _releaseDateCtrl;
  late TextEditingController _seriesCtrl;
  late TextEditingController _seriesIndexCtrl;
  late TextEditingController _descriptionCtrl;
  late TextEditingController _publisherCtrl;
  late TextEditingController _languageCtrl;
  late TextEditingController _genreCtrl;
  late List<TextEditingController> _chapterCtrls;
  late List<String> _originalChapterTitles;
  late String _originalTitle;
  late String _originalSubtitle;
  late String _originalAuthor;
  late String _originalNarrator;
  late String _originalReleaseDate;
  late String _originalSeries;
  late String _originalSeriesIndex;
  late String _originalDescription;
  late String _originalPublisher;
  late String _originalLanguage;
  late String _originalGenre;
  String? _pendingCoverPath;
  bool _coverDropHover = false;
  bool _isDirty = false;
  bool _showFileMetadata = false;
  bool _applying = false;
  bool _rescanning = false;

  List<_ChapterRow> get _chapters => _buildChapterList();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _initControllers();
  }

  @override
  void didUpdateWidget(BookDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.book.path != widget.book.path) {
      _disposeControllers();
      _initControllers();
    }
  }

  void _initControllers() {
    _originalTitle = widget.book.title ?? '';
    _originalSubtitle = widget.book.subtitle ?? '';
    _originalAuthor = widget.book.author ?? '';
    _originalNarrator = widget.book.narrator ?? '';
    _originalReleaseDate = widget.book.releaseDate ?? '';
    _originalSeries = widget.book.series ?? '';
    _originalSeriesIndex = widget.book.seriesIndex?.toString() ?? '';
    _originalDescription = widget.book.description ?? '';
    _originalPublisher = widget.book.publisher ?? '';
    _originalLanguage = widget.book.language ?? '';
    _originalGenre = widget.book.genre ?? '';

    _titleCtrl = TextEditingController(text: _originalTitle)
      ..addListener(_onChanged);
    _subtitleCtrl = TextEditingController(text: _originalSubtitle)
      ..addListener(_onChanged);
    _authorCtrl = TextEditingController(text: _originalAuthor)
      ..addListener(_onChanged);
    _narratorCtrl = TextEditingController(text: _originalNarrator)
      ..addListener(_onChanged);
    _releaseDateCtrl = TextEditingController(text: _originalReleaseDate)
      ..addListener(_onChanged);
    _seriesCtrl = TextEditingController(text: _originalSeries)
      ..addListener(_onChanged);
    _seriesIndexCtrl = TextEditingController(text: _originalSeriesIndex)
      ..addListener(_onChanged);
    _descriptionCtrl = TextEditingController(text: _originalDescription)
      ..addListener(_onChanged);
    _publisherCtrl = TextEditingController(text: _originalPublisher)
      ..addListener(_onChanged);
    _languageCtrl = TextEditingController(text: _originalLanguage)
      ..addListener(_onChanged);
    _genreCtrl = TextEditingController(text: _originalGenre)
      ..addListener(_onChanged);

    final rows = _buildChapterList();
    _originalChapterTitles = rows.map((r) => r.title).toList();
    _chapterCtrls = [
      for (final title in _originalChapterTitles)
        TextEditingController(text: title)..addListener(_onChanged),
    ];
    _isDirty = false;
    _pendingCoverPath = null;
    _coverDropHover = false;
    _showFileMetadata = false;
  }

  void _disposeControllers() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _authorCtrl.dispose();
    _narratorCtrl.dispose();
    _releaseDateCtrl.dispose();
    _seriesCtrl.dispose();
    _seriesIndexCtrl.dispose();
    _descriptionCtrl.dispose();
    _publisherCtrl.dispose();
    _languageCtrl.dispose();
    _genreCtrl.dispose();
    for (final c in _chapterCtrls) {
      c.dispose();
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _disposeControllers();
    super.dispose();
  }

  void _onChanged() {
    final dirty = _pendingCoverPath != null ||
        _titleCtrl.text != _originalTitle ||
        _subtitleCtrl.text != _originalSubtitle ||
        _authorCtrl.text != _originalAuthor ||
        _narratorCtrl.text != _originalNarrator ||
        _releaseDateCtrl.text != _originalReleaseDate ||
        _seriesCtrl.text != _originalSeries ||
        _seriesIndexCtrl.text != _originalSeriesIndex ||
        _descriptionCtrl.text != _originalDescription ||
        _publisherCtrl.text != _originalPublisher ||
        _languageCtrl.text != _originalLanguage ||
        _genreCtrl.text != _originalGenre ||
        _chapterCtrls.indexed.any((e) =>
            e.$2.text !=
            (_originalChapterTitles.length > e.$1
                ? _originalChapterTitles[e.$1]
                : ''));
    if (dirty != _isDirty) {
      setState(() => _isDirty = dirty);
      widget.onDirtyChanged(dirty);
    }
  }

  Future<void> _apply() async {
    setState(() => _applying = true);
    final errors = <String>[];
    try {
      var book = widget.book;
      final newTitle = _titleCtrl.text.trim();
      final newSubtitle = _subtitleCtrl.text.trim();
      final newAuthor = _authorCtrl.text.trim();
      final newNarrator = _narratorCtrl.text.trim();
      final newReleaseDate = _releaseDateCtrl.text.trim();
      final newSeries = _seriesCtrl.text.trim();
      final newSeriesIndex = int.tryParse(_seriesIndexCtrl.text.trim());
      final newDescription = _descriptionCtrl.text.trim();
      final newPublisher = _publisherCtrl.text.trim();
      final newLanguage = _languageCtrl.text.trim();
      final newGenre = _genreCtrl.text.trim();

      if (_pendingCoverPath != null) {
        final coverErrors = await MetadataWriter.applyCover(book, _pendingCoverPath!);
        errors.addAll(coverErrors);
        book = book.copyWith(coverImagePath: p.join(book.path, 'cover.jpg'));
      }

      final metaErrors = await MetadataWriter.applyMetadata(book.copyWith(
        title: newTitle,
        subtitle: newSubtitle.isEmpty ? null : newSubtitle,
        author: newAuthor.isEmpty ? null : newAuthor,
        narrator: newNarrator.isEmpty ? null : newNarrator,
        releaseDate: newReleaseDate.isEmpty ? null : newReleaseDate,
        description: newDescription.isEmpty ? null : newDescription,
        publisher: newPublisher.isEmpty ? null : newPublisher,
        language: newLanguage.isEmpty ? null : newLanguage,
        genre: newGenre.isEmpty ? null : newGenre,
      ));
      errors.addAll(metaErrors);

      // Always export OPF to keep it in sync
      try {
        await MetadataWriter.exportOpf(book.copyWith(
          title: newTitle,
          subtitle: newSubtitle.isEmpty ? null : newSubtitle,
          author: newAuthor.isEmpty ? null : newAuthor,
          narrator: newNarrator.isEmpty ? null : newNarrator,
          releaseDate: newReleaseDate.isEmpty ? null : newReleaseDate,
          series: newSeries.isEmpty ? null : newSeries,
          seriesIndex: newSeriesIndex,
          description: newDescription.isEmpty ? null : newDescription,
          publisher: newPublisher.isEmpty ? null : newPublisher,
          language: newLanguage.isEmpty ? null : newLanguage,
          genre: newGenre.isEmpty ? null : newGenre,
        ));
      } catch (e) {
        errors.add('metadata.opf: $e');
      }

      Audiobook updated;
      if (book.chapters.isNotEmpty) {
        final newChapters = [
          for (int i = 0; i < book.chapters.length; i++)
            book.chapters[i].copyWith(
              title: i < _chapterCtrls.length ? _chapterCtrls[i].text.trim() : null,
            ),
        ];
        updated = book.copyWith(
          title: newTitle,
          subtitle: newSubtitle.isEmpty ? null : newSubtitle,
          author: newAuthor.isEmpty ? null : newAuthor,
          narrator: newNarrator.isEmpty ? null : newNarrator,
          releaseDate: newReleaseDate.isEmpty ? null : newReleaseDate,
          series: newSeries.isEmpty ? null : newSeries,
          seriesIndex: newSeriesIndex,
          description: newDescription.isEmpty ? null : newDescription,
          publisher: newPublisher.isEmpty ? null : newPublisher,
          language: newLanguage.isEmpty ? null : newLanguage,
          genre: newGenre.isEmpty ? null : newGenre,
          chapters: newChapters,
          pendingCoverPath: _pendingCoverPath,
          fileTitleRaw: newTitle,
          fileAuthorRaw: newAuthor.isEmpty ? null : newAuthor,
          fileNarratorRaw: newNarrator.isEmpty ? null : newNarrator,
          fileReleaseDateRaw: newReleaseDate.isEmpty ? null : newReleaseDate,
          fileSubtitleRaw: newSubtitle.isEmpty ? null : newSubtitle,
        );
      } else {
        final newNames = [
          for (int i = 0; i < book.audioFiles.length; i++)
            i < _chapterCtrls.length ? _chapterCtrls[i].text.trim() : '',
        ];
        updated = book.copyWith(
          title: newTitle,
          subtitle: newSubtitle.isEmpty ? null : newSubtitle,
          author: newAuthor.isEmpty ? null : newAuthor,
          narrator: newNarrator.isEmpty ? null : newNarrator,
          releaseDate: newReleaseDate.isEmpty ? null : newReleaseDate,
          series: newSeries.isEmpty ? null : newSeries,
          seriesIndex: newSeriesIndex,
          description: newDescription.isEmpty ? null : newDescription,
          publisher: newPublisher.isEmpty ? null : newPublisher,
          language: newLanguage.isEmpty ? null : newLanguage,
          genre: newGenre.isEmpty ? null : newGenre,
          chapterNames: newNames,
          pendingCoverPath: _pendingCoverPath,
          fileTitleRaw: newTitle,
          fileAuthorRaw: newAuthor.isEmpty ? null : newAuthor,
          fileNarratorRaw: newNarrator.isEmpty ? null : newNarrator,
          fileReleaseDateRaw: newReleaseDate.isEmpty ? null : newReleaseDate,
          fileSubtitleRaw: newSubtitle.isEmpty ? null : newSubtitle,
        );
      }

      widget.onApply(updated);
      setState(() {
        _isDirty = false;
        _pendingCoverPath = null;
        _originalTitle = newTitle;
        _originalSubtitle = newSubtitle;
        _originalAuthor = newAuthor;
        _originalNarrator = newNarrator;
        _originalReleaseDate = newReleaseDate;
        _originalSeries = newSeries;
        _originalSeriesIndex = newSeriesIndex?.toString() ?? '';
        _originalDescription = newDescription;
        _originalPublisher = newPublisher;
        _originalLanguage = newLanguage;
        _originalGenre = newGenre;
        _originalChapterTitles = _chapterCtrls.map((c) => c.text).toList();
      });
    } catch (e) {
      errors.add(e.toString());
    } finally {
      setState(() => _applying = false);
    }

    if (errors.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.red[900],
        content: Text('Errors during apply:\n${errors.join('\n')}'),
        duration: const Duration(seconds: 6),
      ));
    }
  }

  Future<void> _copyFrom() async {
    final otherBooks = widget.allBooks
        .where((b) => b.path != widget.book.path)
        .toList();
    if (otherBooks.isEmpty) return;

    final result = await showDialog<(Audiobook, Set<String>)>(
      context: context,
      builder: (ctx) => CopyFromDialog(books: otherBooks),
    );

    if (result == null) return;
    final (sourceBook, fields) = result;

    // Remove listeners temporarily to avoid triggering dirty state during bulk updates
    _authorCtrl.removeListener(_onChanged);
    _narratorCtrl.removeListener(_onChanged);
    _seriesCtrl.removeListener(_onChanged);
    _seriesIndexCtrl.removeListener(_onChanged);
    _genreCtrl.removeListener(_onChanged);
    _publisherCtrl.removeListener(_onChanged);
    _languageCtrl.removeListener(_onChanged);

    if (fields.contains('author')) {
      _authorCtrl.text = sourceBook.author ?? '';
    }
    if (fields.contains('narrator')) {
      _narratorCtrl.text = sourceBook.narrator ?? '';
    }
    if (fields.contains('series')) {
      _seriesCtrl.text = sourceBook.series ?? '';
    }
    if (fields.contains('seriesIndex')) {
      _seriesIndexCtrl.text = sourceBook.seriesIndex?.toString() ?? '';
    }
    if (fields.contains('genre')) {
      _genreCtrl.text = sourceBook.genre ?? '';
    }
    if (fields.contains('publisher')) {
      _publisherCtrl.text = sourceBook.publisher ?? '';
    }
    if (fields.contains('language')) {
      _languageCtrl.text = sourceBook.language ?? '';
    }

    // Re-add listeners and trigger change detection
    _authorCtrl.addListener(_onChanged);
    _narratorCtrl.addListener(_onChanged);
    _seriesCtrl.addListener(_onChanged);
    _seriesIndexCtrl.addListener(_onChanged);
    _genreCtrl.addListener(_onChanged);
    _publisherCtrl.addListener(_onChanged);
    _languageCtrl.addListener(_onChanged);

    _onChanged();
  }

  Future<void> _renameFolder() async {
    final book = widget.book;
    final currentName = p.basename(book.path);
    
    // Propose a new name based on metadata
    final author = _authorCtrl.text.trim().isEmpty 
        ? 'Unknown' 
        : _authorCtrl.text.trim();
    final title = _titleCtrl.text.trim().isEmpty 
        ? 'Untitled' 
        : _titleCtrl.text.trim();
    
    // Make filesystem-safe by removing invalid characters
    final proposedName = '$author - $title'
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final controller = TextEditingController(text: proposedName);
    
    final confirmed = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename folder'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Current name:', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 4),
            Text(currentName, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text('New name:', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 4),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Enter new folder name',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    controller.dispose();
    
    if (confirmed == null || confirmed.isEmpty || confirmed == currentName) {
      return;
    }

    // Perform the rename
    try {
      final parentDir = Directory(book.path).parent;
      final newPath = p.join(parentDir.path, confirmed);
      
      // Check if target already exists
      if (await Directory(newPath).exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.red[900],
            content: Text('A folder named "$confirmed" already exists'),
          ));
        }
        return;
      }

      // Rename the directory
      await Directory(book.path).rename(newPath);
      
      // Notify parent to update the book list
      widget.onRenamed?.call(book.path, newPath);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Renamed folder to "$confirmed"'),
        ));
      }
    } on FileSystemException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red[900],
          content: Text('Failed to rename folder: ${e.message}'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: cover + read-only summary ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCover(),
              const SizedBox(width: 24),
              Expanded(child: _buildSummary(theme)),
            ],
          ),
          const SizedBox(height: 12),
          // ── View toggle ──
          ToggleButtons(
            isSelected: [!_showFileMetadata, _showFileMetadata],
            onPressed: (i) {
              final showFile = i == 1;
              _titleCtrl.removeListener(_onChanged);
              _subtitleCtrl.removeListener(_onChanged);
              _authorCtrl.removeListener(_onChanged);
              _narratorCtrl.removeListener(_onChanged);
              _releaseDateCtrl.removeListener(_onChanged);
              final b = widget.book;
              _titleCtrl.text = showFile
                  ? (b.fileTitleRaw ?? b.title ?? '')
                  : (b.title ?? '');
              _subtitleCtrl.text = showFile
                  ? (b.fileSubtitleRaw ?? b.subtitle ?? '')
                  : (b.subtitle ?? '');
              _authorCtrl.text = showFile
                  ? (b.fileAuthorRaw ?? b.author ?? '')
                  : (b.author ?? '');
              _narratorCtrl.text = showFile
                  ? (b.fileNarratorRaw ?? b.narrator ?? '')
                  : (b.narrator ?? '');
              _releaseDateCtrl.text = showFile
                  ? (b.fileReleaseDateRaw ?? b.releaseDate ?? '')
                  : (b.releaseDate ?? '');
              _titleCtrl.addListener(_onChanged);
              _subtitleCtrl.addListener(_onChanged);
              _authorCtrl.addListener(_onChanged);
              _narratorCtrl.addListener(_onChanged);
              _releaseDateCtrl.addListener(_onChanged);
              setState(() => _showFileMetadata = showFile);
            },
            borderRadius: BorderRadius.circular(6),
            constraints: const BoxConstraints(minWidth: 80, minHeight: 32),
            children: const [
              Text('Merged metadata', style: TextStyle(fontSize: 12)),
              Text('File tags only', style: TextStyle(fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          // ── Action bar ──
          _buildActionBar(theme),
          const SizedBox(height: 8),
          // ── Tabs ──
          TabBar(
            controller: _tabCtrl,
            tabs: [
              const Tab(text: 'Book'),
              Tab(text: 'Chapters (${_chapters.length})'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildBookTab(theme),
                _buildChaptersTab(theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _buildTitleLine() {
    final t = _titleCtrl.text.trim();
    final s = _subtitleCtrl.text.trim();
    final y = _releaseDateCtrl.text.trim();
    final buf = StringBuffer(t.isEmpty ? 'Untitled' : t);
    if (s.isNotEmpty) buf.write(': $s');
    if (y.isNotEmpty) buf.write(' ($y)');
    return buf.toString();
  }

  Widget _buildSummary(ThemeData theme) {
    final book = widget.book;
    final sources = <String>[
      if (book.hasEmbeddedTags) 'embedded',
      if (book.hasOpf) 'metadata.opf',
      if (book.hasCue) 'cue',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_buildTitleLine(),
            style: theme.textTheme.titleLarge,
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        if (_authorCtrl.text.trim().isNotEmpty)
          _summaryRow('Author', _authorCtrl.text.trim()),
        if (_narratorCtrl.text.trim().isNotEmpty)
          _summaryRow('Narrated by', _narratorCtrl.text.trim()),
        _summaryRow('Duration', _formatDuration(book.duration) ?? '—'),
        _summaryRow('Files', _formatFiles()),
        if (sources.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                const Text('Metadata: ',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
                ...sources.map((s) => Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Chip(
                        label: Text(s),
                        labelStyle: const TextStyle(fontSize: 10),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    )),
              ],
            ),
          ),
      ],
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text('$label:',
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar(ThemeData theme) {
    final otherBooks = widget.allBooks
        .where((b) => b.path != widget.book.path)
        .toList();

    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: otherBooks.isEmpty ? null : _copyFrom,
          icon: const Icon(Icons.content_copy, size: 18),
          label: const Text('Copy from…'),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          tooltip: 'More actions',
          icon: const Icon(Icons.more_vert),
          onSelected: (value) async {
            if (value == 'rename') {
              await _renameFolder();
            } else if (value == 'export_opf') {
              try {
                await MetadataWriter.exportOpf(widget.book);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content:
                      Text('Exported metadata.opf to ${widget.book.path}'),
                ));
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  backgroundColor: Colors.red[900],
                  content: Text('Export failed: $e'),
                ));
              }
            } else if (value == 'export_cover') {
              try {
                await MetadataWriter.exportCover(widget.book);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content:
                      Text('Exported cover.jpg to ${widget.book.path}'),
                ));
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  backgroundColor: Colors.red[900],
                  content: Text('Export failed: $e'),
                ));
              }
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'export_opf',
              child: Row(
                children: [
                  Icon(Icons.upload_file, size: 18),
                  SizedBox(width: 8),
                  Text('Export OPF'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'export_cover',
              enabled: widget.book.coverImagePath != null ||
                  widget.book.coverImageBytes != null,
              child: const Row(
                children: [
                  Icon(Icons.image, size: 18),
                  SizedBox(width: 8),
                  Text('Export Cover'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'rename',
              enabled: !_applying && !_rescanning,
              child: const Row(
                children: [
                  Icon(Icons.drive_file_rename_outline, size: 18),
                  SizedBox(width: 8),
                  Text('Rename folder'),
                ],
              ),
            ),
          ],
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Undo last apply',
          onPressed: widget.onUndo,
          icon: const Icon(Icons.undo),
        ),
        IconButton(
          tooltip: 'Rescan from disk',
          onPressed: (_applying || _rescanning)
              ? null
              : () async {
                  if (_isDirty) {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Discard changes?'),
                        content: const Text(
                            'Rescanning will discard your unsaved changes.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel')),
                          FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Discard & Rescan')),
                        ],
                      ),
                    );
                    if (confirm != true) return;
                  }
                  setState(() => _rescanning = true);
                  try {
                    widget.onRescan();
                  } finally {
                    if (mounted) setState(() => _rescanning = false);
                  }
                },
          icon: _rescanning
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh),
        ),
        FilledButton.icon(
          onPressed: (_isDirty && !_applying) ? _apply : null,
          icon: _applying
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check, size: 18),
          label: const Text('Apply'),
        ),
        if (_isDirty)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text('Unsaved changes',
                style:
                    TextStyle(fontSize: 12, color: theme.colorScheme.error)),
          ),
      ],
    );
  }

  Widget _buildBookTab(ThemeData theme) {
    final book = widget.book;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _editableRow('Title', _titleCtrl, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          _editableRow('Subtitle', _subtitleCtrl),
          _editableRow('Author', _authorCtrl),
          if (book.additionalAuthors.isNotEmpty)
            _metaRow('Also by', book.additionalAuthors.join(', ')),
          _editableRow('Narrator', _narratorCtrl),
          if (book.additionalNarrators.isNotEmpty)
            _metaRow('Also narr.', book.additionalNarrators.join(', ')),
          _editableRow('Published', _releaseDateCtrl),
          _editableRow('Series', _seriesCtrl),
          _editableRow('Series #', _seriesIndexCtrl),
          _editableRow('Publisher', _publisherCtrl),
          _editableRow('Language', _languageCtrl),
          _editableRow('Genre', _genreCtrl),
          _editableRow('Description', _descriptionCtrl, maxLines: 4),
          _metaRow('ID', book.identifier),
        ],
      ),
    );
  }

  Widget _buildChaptersTab(ThemeData theme) {
    return _buildChapterTable(_chapters, theme);
  }

  Widget _buildCover() {
    final Widget image;
    if (_pendingCoverPath != null) {
      image = Image.file(File(_pendingCoverPath!), fit: BoxFit.cover);
    } else if (widget.book.coverImageBytes != null) {
      image = Image.memory(widget.book.coverImageBytes!, fit: BoxFit.cover);
    } else if (widget.book.coverImagePath != null) {
      image = Image.file(File(widget.book.coverImagePath!), fit: BoxFit.cover);
    } else {
      image = const Icon(Icons.book, size: 64, color: Colors.white54);
    }

    return DropTarget(
      onDragEntered: (_) => setState(() => _coverDropHover = true),
      onDragExited: (_) => setState(() => _coverDropHover = false),
      onDragDone: (details) {
        final files =
            details.files.where((f) => _isImagePath(f.path)).toList();
        if (files.isNotEmpty) {
          setState(() {
            _pendingCoverPath = files.first.path;
            _coverDropHover = false;
          });
          _onChanged();
        }
      },
      child: Container(
        width: 160,
        height: 160,
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(8),
          border: _coverDropHover
              ? Border.all(color: Colors.blue, width: 2)
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            if (_coverDropHover)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: Icon(Icons.add_photo_alternate,
                      size: 40, color: Colors.white),
                ),
              ),
            if (_pendingCoverPath != null)
              Positioned(
                bottom: 4,
                right: 4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('pending',
                      style: TextStyle(fontSize: 10, color: Colors.black)),
                ),
              ),
            Positioned(
              bottom: 4,
              left: 4,
              child: IconButton.filled(
                iconSize: 16,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                tooltip: 'Browse for cover image',
                onPressed: _applying ? null : _browseCover,
                icon: const Icon(Icons.folder_open),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isImagePath(String path) {
    final ext = p.extension(path).toLowerCase();
    return {'.jpg', '.jpeg', '.png', '.webp'}.contains(ext);
  }

  Future<void> _browseCover() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      dialogTitle: 'Select cover image',
    );
    final path = result?.files.firstOrNull?.path;
    if (path != null) {
      setState(() => _pendingCoverPath = path);
      _onChanged();
    }
  }

Widget _editableRow(String label, TextEditingController ctrl,
      {TextStyle? style, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SizedBox(
              width: 80,
              child: Text('$label:', style: const TextStyle(color: Colors.grey)),
            ),
          ),
          Expanded(
            child: TextField(
              controller: ctrl,
              style: style,
              maxLines: maxLines,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaRow(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text('$label:', style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }

  List<_ChapterRow> _buildChapterList() {
    final book = widget.book;
    if (book.chapters.isNotEmpty) {
      return [
        for (int i = 0; i < book.chapters.length; i++)
          _ChapterRow(
            index: i + 1,
            title: book.chapters[i].title,
            start: book.chapters[i].start,
            duration: i + 1 < book.chapters.length
                ? book.chapters[i + 1].start - book.chapters[i].start
                : book.duration != null
                    ? book.duration! - book.chapters[i].start
                    : null,
          ),
      ];
    }
    return [
      for (int i = 0; i < book.audioFiles.length; i++)
        _ChapterRow(
          index: i + 1,
          title: i < book.chapterNames.length
              ? book.chapterNames[i]
              : p.basenameWithoutExtension(book.audioFiles[i]),
          duration: i < book.chapterDurations.length
              ? book.chapterDurations[i]
              : null,
          file: p.basename(book.audioFiles[i]),
        ),
    ];
  }

  Widget _buildChapterTable(List<_ChapterRow> chapters, ThemeData theme) {
    return SingleChildScrollView(
      child: DataTable(
        columnSpacing: 24,
        headingRowColor: WidgetStateProperty.all(Colors.grey[900]),
        columns: const [
          DataColumn(label: Text('#')),
          DataColumn(label: Text('Title')),
          DataColumn(label: Text('Start')),
          DataColumn(label: Text('Duration')),
          DataColumn(label: Text('File')),
        ],
        rows: [
          for (int i = 0; i < chapters.length; i++)
            DataRow(cells: [
              DataCell(Text('${chapters[i].index}')),
              DataCell(
                i < _chapterCtrls.length
                    ? TextField(
                        controller: _chapterCtrls[i],
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          border: OutlineInputBorder(),
                        ),
                      )
                    : Text(chapters[i].title),
              ),
              DataCell(Text(chapters[i].start != null
                  ? _formatDuration(chapters[i].start)!
                  : '')),
              DataCell(Text(_formatDuration(chapters[i].duration) ?? '')),
              DataCell(Text(chapters[i].file ?? '')),
            ]),
        ],
      ),
    );
  }

  String _formatFiles() {
    final files = widget.book.audioFiles;
    if (files.isEmpty) return '0';
    final ext = p
        .extension(files.first)
        .toLowerCase()
        .replaceFirst('.', '')
        .toUpperCase();
    return '${files.length} \u00d7 $ext';
  }

  String? _formatDuration(Duration? d) {
    if (d == null) return null;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

class _ChapterRow {
  final int index;
  final String title;
  final Duration? start;
  final Duration? duration;
  final String? file;

  const _ChapterRow({
    required this.index,
    required this.title,
    this.start,
    this.duration,
    this.file,
  });
}
