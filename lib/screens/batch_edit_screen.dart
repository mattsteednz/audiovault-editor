import 'package:flutter/material.dart';
import '../models/audiobook.dart';
import '../services/metadata_writer.dart';

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

  bool _applying = false;
  int _progress = 0;

  @override
  void dispose() {
    _authorCtrl.dispose();
    _narratorCtrl.dispose();
    _releaseDateCtrl.dispose();
    _seriesCtrl.dispose();
    _seriesIndexCtrl.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final author = _authorCtrl.text.trim();
    final narrator = _narratorCtrl.text.trim();
    final releaseDate = _releaseDateCtrl.text.trim();
    final series = _seriesCtrl.text.trim();
    final seriesIndex = int.tryParse(_seriesIndexCtrl.text.trim());

    setState(() {
      _applying = true;
      _progress = 0;
    });

    final errors = <String>[];
    final updated = <Audiobook>[];

    for (final book in widget.books) {
      final patched = book.copyWith(
        author: author.isNotEmpty ? author : null,
        narrator: narrator.isNotEmpty ? narrator : null,
        releaseDate: releaseDate.isNotEmpty ? releaseDate : null,
        series: series.isNotEmpty ? series : null,
        seriesIndex: seriesIndex,
      );

      // Only write fields that were filled in
      final toWrite = book.copyWith(
        author: author.isNotEmpty ? author : book.author,
        narrator: narrator.isNotEmpty ? narrator : book.narrator,
        releaseDate: releaseDate.isNotEmpty ? releaseDate : book.releaseDate,
        series: series.isNotEmpty ? series : book.series,
        seriesIndex: seriesIndex ?? book.seriesIndex,
      );

      final errs = await MetadataWriter.applyMetadata(toWrite);
      if (errs.isNotEmpty) {
        errors.add('${book.title ?? book.path}: ${errs.join(', ')}');
      }

      try {
        await MetadataWriter.exportOpf(toWrite);
      } catch (e) {
        errors.add('${book.title ?? book.path} OPF: $e');
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
