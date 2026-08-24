import 'package:flutter/material.dart';
import 'package:audiovault_editor/models/audiobook.dart';
import 'package:audiovault_editor/services/metadata_writer.dart';

class BatchEditScreen extends StatefulWidget {
  final List<Audiobook> books;
  final void Function(List<Audiobook> updated) onApplied;

  const BatchEditScreen(
      {super.key, required this.books, required this.onApplied});

  @override
  State<BatchEditScreen> createState() => _BatchEditScreenState();
}

class _BatchEditScreenState extends State<BatchEditScreen> {
  final _authorCtrl = TextEditingController();
  final _narratorCtrl = TextEditingController();
  final _releaseDateCtrl = TextEditingController();
  final _seriesCtrl = TextEditingController();
  final _seriesIndexCtrl = TextEditingController();
  final _publisherCtrl = TextEditingController();
  final _languageCtrl = TextEditingController();
  final _genreCtrl = TextEditingController();

  bool _applying = false;
  int _progress = 0;

  @override
  void dispose() {
    _authorCtrl.dispose();
    _narratorCtrl.dispose();
    _releaseDateCtrl.dispose();
    _seriesCtrl.dispose();
    _seriesIndexCtrl.dispose();
    _publisherCtrl.dispose();
    _languageCtrl.dispose();
    _genreCtrl.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    // Guard against accidental bulk writes to many books.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apply to all selected books?'),
        content: Text(
          'The filled-in fields will be written to the tags of all '
          '${widget.books.length} selected book(s). Blank fields are left '
          'unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final author = _authorCtrl.text.trim();
    final narrator = _narratorCtrl.text.trim();
    final releaseDate = _releaseDateCtrl.text.trim();
    final series = _seriesCtrl.text.trim();
    final seriesIndex = int.tryParse(_seriesIndexCtrl.text.trim());
    final publisher = _publisherCtrl.text.trim();
    final language = _languageCtrl.text.trim();
    final genre = _genreCtrl.text.trim();

    setState(() {
      _applying = true;
      _progress = 0;
    });

    final errors = <String>[];
    final updated = <Audiobook>[];

    for (final book in widget.books) {
      // Blank inputs keep each book's existing value on disk AND in memory,
      // so a single patched model is used both for writing and for updating
      // the app state (they must never diverge).
      final patched = book.copyWith(
        author: author.isNotEmpty ? author : book.author,
        narrator: narrator.isNotEmpty ? narrator : book.narrator,
        releaseDate: releaseDate.isNotEmpty ? releaseDate : book.releaseDate,
        series: series.isNotEmpty ? series : book.series,
        seriesIndex: seriesIndex ?? book.seriesIndex,
        publisher: publisher.isNotEmpty ? publisher : book.publisher,
        language: language.isNotEmpty ? language : book.language,
        genre: genre.isNotEmpty ? genre : book.genre,
      );

      final errs = await MetadataWriter.applyMetadata(patched);
      if (errs.isNotEmpty) {
        errors.add('${book.title ?? book.path}: ${errs.join(', ')}');
      }

      updated.add(patched);
      setState(() => _progress++);
    }

    setState(() => _applying = false);

    if (errors.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.red[900],
        content: Text('Errors:\n${errors.join('\n')}'),
        duration: const Duration(seconds: 6),
      ));
    }

    widget.onApplied(updated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Batch edit — ${widget.books.length} books selected',
              style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Only non-empty fields will be written. Blank fields are skipped.',
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
          const SizedBox(height: 16),
          _field('Author', _authorCtrl),
          _field('Narrator', _narratorCtrl),
          _field('Published', _releaseDateCtrl),
          _field('Series', _seriesCtrl),
          _field('Series #', _seriesIndexCtrl),
          _field('Publisher', _publisherCtrl),
          _field('Language', _languageCtrl),
          _field('Genre', _genreCtrl),
          const SizedBox(height: 16),
          if (_applying) ...[
            Text('$_progress / ${widget.books.length}'),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _progress / widget.books.length,
            ),
          ] else
            FilledButton.icon(
              onPressed: _apply,
              icon: const Icon(Icons.check, size: 18),
              label: Text('Apply to ${widget.books.length} books'),
            ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text('$label:', style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(
            child: TextField(
              controller: ctrl,
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
}
