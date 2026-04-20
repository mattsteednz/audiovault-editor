import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../models/audiobook.dart';
import '../services/metadata_writer.dart';

class BookDetailScreen extends StatefulWidget {
  final Audiobook book;
  final void Function(Audiobook updated) onApply;

  const BookDetailScreen({super.key, required this.book, required this.onApply});

  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen> {
  late TextEditingController _titleCtrl;
  late TextEditingController _authorCtrl;
  late TextEditingController _narratorCtrl;
  late TextEditingController _releaseDateCtrl;
  late List<TextEditingController> _chapterCtrls;
  late List<String> _originalChapterTitles;
  late String _originalTitle;
  late String _originalAuthor;
  late String _originalNarrator;
  late String _originalReleaseDate;
  String? _pendingCoverPath;
  bool _coverDropHover = false;
  bool _isDirty = false;

  List<_ChapterRow> get _chapters => _buildChapterList();

  @override
  void initState() {
    super.initState();
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
    _originalTitle = widget.book.title;
    _originalAuthor = widget.book.author ?? '';
    _originalNarrator = widget.book.narrator ?? '';
    _originalReleaseDate = widget.book.releaseDate ?? '';

    _titleCtrl = TextEditingController(text: _originalTitle)
      ..addListener(_onChanged);
    _authorCtrl = TextEditingController(text: _originalAuthor)
      ..addListener(_onChanged);
    _narratorCtrl = TextEditingController(text: _originalNarrator)
      ..addListener(_onChanged);
    _releaseDateCtrl = TextEditingController(text: _originalReleaseDate)
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
  }

  void _disposeControllers() {
    _titleCtrl.dispose();
    _authorCtrl.dispose();
    _narratorCtrl.dispose();
    _releaseDateCtrl.dispose();
    for (final c in _chapterCtrls) {
      c.dispose();
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _onChanged() {
    final dirty = _pendingCoverPath != null ||
        _titleCtrl.text != _originalTitle ||
        _authorCtrl.text != _originalAuthor ||
        _narratorCtrl.text != _originalNarrator ||
        _releaseDateCtrl.text != _originalReleaseDate ||
        _chapterCtrls.indexed.any((e) =>
            e.$2.text !=
            (_originalChapterTitles.length > e.$1
                ? _originalChapterTitles[e.$1]
                : ''));
    if (dirty != _isDirty) setState(() => _isDirty = dirty);
  }

  Future<void> _apply() async {
    var book = widget.book;
    final newTitle = _titleCtrl.text.trim();
    final newAuthor = _authorCtrl.text.trim();
    final newNarrator = _narratorCtrl.text.trim();
    final newReleaseDate = _releaseDateCtrl.text.trim();

    if (_pendingCoverPath != null) {
      await MetadataWriter.applyCover(book, _pendingCoverPath!);
      // Point the book at the newly written cover.jpg
      book = book.copyWith(
        coverImagePath: p.join(book.path, 'cover.jpg'),
      );
    }

    // Write text metadata into audio files
    await MetadataWriter.applyMetadata(book.copyWith(
      title: newTitle,
      author: newAuthor.isEmpty ? null : newAuthor,
      narrator: newNarrator.isEmpty ? null : newNarrator,
      releaseDate: newReleaseDate.isEmpty ? null : newReleaseDate,
    ));

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
        author: newAuthor.isEmpty ? null : newAuthor,
        narrator: newNarrator.isEmpty ? null : newNarrator,
        releaseDate: newReleaseDate.isEmpty ? null : newReleaseDate,
        chapters: newChapters,
        pendingCoverPath: _pendingCoverPath,
      );
    } else {
      final newNames = [
        for (int i = 0; i < book.audioFiles.length; i++)
          i < _chapterCtrls.length ? _chapterCtrls[i].text.trim() : '',
      ];
      updated = book.copyWith(
        title: newTitle,
        author: newAuthor.isEmpty ? null : newAuthor,
        narrator: newNarrator.isEmpty ? null : newNarrator,
        releaseDate: newReleaseDate.isEmpty ? null : newReleaseDate,
        chapterNames: newNames,
        pendingCoverPath: _pendingCoverPath,
      );
    }

    widget.onApply(updated);
    setState(() {
      _isDirty = false;
      _pendingCoverPath = null;
      _originalTitle = _titleCtrl.text;
      _originalAuthor = _authorCtrl.text;
      _originalNarrator = _narratorCtrl.text;
      _originalReleaseDate = _releaseDateCtrl.text;
      _originalChapterTitles = _chapterCtrls.map((c) => c.text).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chapters = _chapters;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCover(),
              const SizedBox(width: 24),
              Expanded(child: _buildMetadata(theme)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Chapters (${chapters.length})',
                  style: theme.textTheme.titleMedium),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () async {
                  await MetadataWriter.exportMetadata(widget.book);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                          'Exported metadata.opf + cover.jpg to ${widget.book.path}'),
                    ));
                  }
                },
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Export metadata'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _isDirty ? _apply : null,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Apply'),
              ),
              if (_isDirty)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text('Unsaved changes',
                      style: TextStyle(
                          fontSize: 12, color: theme.colorScheme.error)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildChapterTable(chapters, theme)),
        ],
      ),
    );
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
          ],
        ),
      ),
    );
  }

  bool _isImagePath(String path) {
    final ext = p.extension(path).toLowerCase();
    return {'.jpg', '.jpeg', '.png', '.webp'}.contains(ext);
  }

  Widget _buildMetadata(ThemeData theme) {
    final series = widget.book.series != null
        ? '${widget.book.series}${widget.book.seriesIndex != null ? ' #${widget.book.seriesIndex}' : ''}'
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _editableRow('Title', _titleCtrl, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        _editableRow('Author', _authorCtrl),
        _editableRow('Narrator', _narratorCtrl),
        _editableRow('Published', _releaseDateCtrl),
        _metaRow('Series', series),
        _metaRow('Duration', _formatDuration(widget.book.duration)),
        _metaRow('Publisher', widget.book.publisher),
        _metaRow('Language', widget.book.language),
        _metaRow('Files', _formatFiles()),
      ],
    );
  }

  Widget _editableRow(String label, TextEditingController ctrl,
      {TextStyle? style}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 80,
            child: Text('$label:', style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(
            child: TextField(
              controller: ctrl,
              style: style,
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
          start: null,
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
