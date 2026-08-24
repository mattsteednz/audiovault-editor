import 'dart:io';
import 'dart:math' as math;
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:audiovault_editor/models/audiobook.dart';
import 'package:audiovault_editor/services/cue_writer.dart';
import 'package:audiovault_editor/services/metadata_writer.dart';
import 'package:audiovault_editor/services/opf_parser.dart';
import 'package:audiovault_editor/widgets/chapter_editor.dart';
import 'package:audiovault_editor/widgets/copy_from_dialog.dart';
import 'package:audiovault_editor/widgets/read_only_badge.dart';
import 'package:audiovault_editor/widgets/rename_folder_dialog.dart';

class BookDetailScreen extends StatefulWidget {
  final Audiobook book;
  final List<Audiobook> allBooks;
  final void Function(Audiobook updated) onApply;
  final void Function() onRescan;
  final void Function()? onUndo;
  final String undoTooltip;
  final void Function(bool isDirty) onDirtyChanged;
  final void Function(String oldPath, String newPath)? onRenamed;

  /// Invoked after a successful Apply — used by the apply-and-next workflow
  /// to advance selection to the next book.
  final VoidCallback? onNext;

  const BookDetailScreen({
    super.key,
    required this.book,
    required this.allBooks,
    required this.onApply,
    required this.onRescan,
    this.onUndo,
    this.undoTooltip = 'Nothing to undo',
    required this.onDirtyChanged,
    this.onRenamed,
    this.onNext,
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
  List<ChapterEntry>? _pendingChapters;
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
  bool _chapterHasErrors = false;
  bool _showFileMetadata = false;
  bool _applying = false;
  bool _rescanning = false;

  int get _chapterCount {
    if (_pendingChapters != null) return _pendingChapters!.length;
    if (widget.book.chapters.isNotEmpty) return widget.book.chapters.length;
    return widget.book.audioFiles.length;
  }

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _initControllers();
  }

  @override
  void didUpdateWidget(BookDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-seed whenever a new book object arrives (different path OR the same
    // book refreshed via Apply/Rescan), so on-disk state is never stale in
    // the form fields.
    if (!identical(oldWidget.book, widget.book)) {
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

    _pendingChapters = null;
    _isDirty = false;
    _chapterHasErrors = false;
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
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _disposeControllers();
    super.dispose();
  }

  void _onChanged() {
    final dirty = _pendingCoverPath != null ||
        _pendingChapters != null ||
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
        _genreCtrl.text != _originalGenre;
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

      // Write chapters for single-file M4B books
      if (_pendingChapters != null && widget.book.audioFiles.length == 1) {
        final chapterList = _pendingChapters!
            .map((e) => Chapter(title: e.title, start: e.start))
            .toList();
        final chapterErrors = await MetadataWriter.applyChapters(
          book,
          chapterList,
        );
        errors.addAll(chapterErrors);
      }

      Audiobook updated;
      Audiobook buildUpdated({List<Chapter>? chapters, List<String>? chapterNames}) {
        return book.copyWith(
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
          chapters: chapters,
          chapterNames: chapterNames,
          pendingCoverPath: _pendingCoverPath,
          fileTitleRaw: newTitle,
          fileAuthorRaw: newAuthor.isEmpty ? null : newAuthor,
          fileNarratorRaw: newNarrator.isEmpty ? null : newNarrator,
          fileReleaseDateRaw: newReleaseDate.isEmpty ? null : newReleaseDate,
          fileSubtitleRaw: newSubtitle.isEmpty ? null : newSubtitle,
        );
      }

      if (book.chapters.isNotEmpty) {
        final newChapters = _pendingChapters != null
            ? _pendingChapters!.map((e) => Chapter(title: e.title, start: e.start)).toList()
            : book.chapters;
        updated = buildUpdated(chapters: newChapters);
      } else {
        final newNames = _pendingChapters != null
            ? _pendingChapters!.map((e) => e.title).toList()
            : book.chapterNames;
        updated = buildUpdated(chapterNames: newNames);
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
        _pendingChapters = null;
      });
    } catch (e) {
      errors.add(e.toString());
    } finally {
      if (mounted) setState(() => _applying = false);
    }

    if (errors.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.red[900],
        content: Text('Errors during apply:\n${errors.join('\n')}'),
        duration: const Duration(seconds: 6),
      ));
    } else if (errors.isEmpty && mounted && widget.onNext != null) {
      // Apply-and-next: advance to the following book in the current view.
      final next = widget.onNext!;
      WidgetsBinding.instance.addPostFrameCallback((_) => next());
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

    final confirmed =
        await showRenameFolderDialog(context, currentName: currentName, proposedName: proposedName);

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

  /// Assigns [updates] without firing dirty-detection per field; dirty state
  /// is re-evaluated once at the end.
  void _silentlyApply(Map<TextEditingController, String> updates) {
    final all = [
      _titleCtrl,
      _subtitleCtrl,
      _authorCtrl,
      _narratorCtrl,
      _releaseDateCtrl,
      _seriesCtrl,
      _seriesIndexCtrl,
      _descriptionCtrl,
      _publisherCtrl,
      _languageCtrl,
      _genreCtrl,
    ];
    for (final c in all) {
      c.removeListener(_onChanged);
    }
    updates.forEach((c, v) => c.text = v);
    for (final c in all) {
      c.addListener(_onChanged);
    }
    _onChanged();
  }

  /// Loads `<book folder>/metadata.opf` into the form fields (no disk writes
  /// until Apply).
  Future<void> _importOpfFromFolder() async {
    final opfFile = File(p.join(widget.book.path, 'metadata.opf'));
    if (!await opfFile.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No metadata.opf found in this book\'s folder'),
      ));
      return;
    }
    try {
      final opf = parseOpf(await opfFile.readAsString());
      _silentlyApply({
        if (opf.title != null) _titleCtrl: opf.title!,
        if (opf.subtitle != null) _subtitleCtrl: opf.subtitle!,
        if (opf.author != null) _authorCtrl: opf.author!,
        if (opf.narrator != null) _narratorCtrl: opf.narrator!,
        if (opf.releaseDate != null) _releaseDateCtrl: opf.releaseDate!,
        if (opf.series != null) _seriesCtrl: opf.series!,
        if (opf.seriesIndex != null)
          _seriesIndexCtrl: opf.seriesIndex.toString(),
        if (opf.description != null) _descriptionCtrl: opf.description!,
        if (opf.publisher != null) _publisherCtrl: opf.publisher!,
        if (opf.language != null) _languageCtrl: opf.language!,
        if (opf.genre != null) _genreCtrl: opf.genre!,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Loaded metadata.opf — review and hit Apply to write it to tags'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.red[900],
        content: Text('Failed to parse metadata.opf: $e'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final readOnly = widget.book.readOnlyStatus != ReadOnlyStatus.writable;
    final canApply = !readOnly && _isDirty && !_applying && !_chapterHasErrors;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (canApply) _apply();
        },
      },
      child: Focus(
        autofocus: true,
        child: Padding(
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
          Tooltip(
            message: _isDirty
                ? 'Apply or discard your changes before switching views'
                : '',
            child: ToggleButtons(
            isSelected: [!_showFileMetadata, _showFileMetadata],
            onPressed: _isDirty
                ? null
                : (i) {
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
              Tab(text: 'Chapters ($_chapterCount)'),
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
        ),
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
        if (book.readOnlyStatus != ReadOnlyStatus.writable) ...[
          const SizedBox(height: 4),
          ReadOnlyBadge(
            prominent: true,
            tooltip: book.readOnlyStatus == ReadOnlyStatus.folderReadOnly
                ? 'Folder is read-only — metadata changes cannot be saved'
                : 'One or more audio files are read-only — metadata changes cannot be saved',
          ),
        ],
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

    // Wrap (not Row+Spacer) so the bar degrades gracefully on narrow windows.
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
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
            } else if (value == 'reveal') {
              // Open the book's folder in Windows Explorer.
              await Process.run('explorer.exe', [widget.book.path]);
            } else if (value == 'import_opf') {
              await _importOpfFromFolder();
            } else if (value == 'export_cue') {
              try {
                final book = widget.book;
                // CUE sheets only work with single-file books
                if (book.audioFiles.length != 1) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    backgroundColor: Colors.orange[800],
                    content: const Text('CUE sheets can only be exported for single-file books'),
                  ));
                  return;
                }
                
                final chapters = _pendingChapters != null
                    ? _pendingChapters!.map((e) => Chapter(title: e.title, start: e.start)).toList()
                    : book.chapters;
                final entries = chapters.map((c) => ChapterEntry(title: c.title, start: c.start)).toList();
                await CueWriter.write(
                  book.path,
                  book.title ?? 'chapters',
                  p.basename(book.audioFiles[0]),
                  entries,
                );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Exported CUE sheet to ${book.path}'),
                ));
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  backgroundColor: Colors.red[900],
                  content: Text('CUE export failed: $e'),
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
            PopupMenuItem(
              value: 'export_cue',
              enabled: widget.book.audioFiles.length == 1,
              child: const Row(
                children: [
                  Icon(Icons.queue_music, size: 18),
                  SizedBox(width: 8),
                  Text('Export CUE'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'reveal',
              child: Row(
                children: [
                  Icon(Icons.folder_open, size: 18),
                  SizedBox(width: 8),
                  Text('Show in Explorer'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'import_opf',
              enabled:
                  File(p.join(widget.book.path, 'metadata.opf')).existsSync(),
              child: const Row(
                children: [
                  Icon(Icons.download, size: 18),
                  SizedBox(width: 8),
                  Text('Load folder\'s metadata.opf'),
                ],
              ),
            ),
          ],
        ),
        IconButton(
          tooltip: widget.undoTooltip,
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
        Builder(builder: (context) {
          final bool isReadOnly =
              widget.book.readOnlyStatus != ReadOnlyStatus.writable;
          final applyButton = FilledButton.icon(
            onPressed:
                (!isReadOnly && _isDirty && !_applying && !_chapterHasErrors)
                    ? _apply
                    : null,
            icon: _applying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check, size: 18),
            label: const Text('Apply'),
          );
          if (isReadOnly) {
            return Tooltip(
              message: 'Cannot save — folder or files are read-only',
              child: applyButton,
            );
          }
          return applyButton;
        }),
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
          _editableRow('Title', _titleCtrl),
          const SizedBox(height: 4),
          _editableRow('Subtitle', _subtitleCtrl),
          _editableRow('Author', _authorCtrl),
          if (book.additionalAuthors.isNotEmpty)
            _metaRow('Also by', book.additionalAuthors.join(', ')),
          _editableRow('Narrator', _narratorCtrl),
          if (book.additionalNarrators.isNotEmpty)
            _metaRow('Also narr.', book.additionalNarrators.join(', ')),
          _editableRow('Published', _releaseDateCtrl,
              hint: 'YYYY or DD-MM-YYYY'),
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
    return ChapterEditor(
      book: widget.book,
      onChanged: (chapters) {
        _pendingChapters = chapters;
        _onChanged();
      },
      onApplied: () {
        _pendingChapters = null;
      },
      onHasErrors: (hasErrors) {
        setState(() => _chapterHasErrors = hasErrors);
      },
    );
  }

  Widget _buildCover() {
    final Widget image;
    // Decode at display resolution (2x headroom for DPR) instead of full art.
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
    final coverCacheSize =
        (160 * math.max(1.5, dpr)).round().clamp(160, 1024);
    if (_pendingCoverPath != null) {
      image = Image.file(File(_pendingCoverPath!),
          fit: BoxFit.cover, cacheWidth: coverCacheSize);
    } else if (widget.book.coverImageBytes != null) {
      image = Image.memory(widget.book.coverImageBytes!,
          fit: BoxFit.cover, cacheWidth: coverCacheSize);
    } else if (widget.book.coverImagePath != null) {
      image = Image.file(File(widget.book.coverImagePath!),
          fit: BoxFit.cover, cacheWidth: coverCacheSize);
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
      {int maxLines = 1, String? hint}) {
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
              maxLines: maxLines,
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border: const OutlineInputBorder(),
                hintText: hint,
                hintStyle: const TextStyle(color: Colors.grey, fontSize: 12),
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
