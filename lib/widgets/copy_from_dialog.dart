import 'package:flutter/material.dart';
import 'package:audiovault_editor/models/audiobook.dart';

/// Dialog for selecting a source book and fields to copy from.
class CopyFromDialog extends StatefulWidget {
  final List<Audiobook> books;

  const CopyFromDialog({super.key, required this.books});

  @override
  State<CopyFromDialog> createState() => _CopyFromDialogState();
}

class _CopyFromDialogState extends State<CopyFromDialog> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  Audiobook? _selectedBook;
  final Set<String> _selectedFields = {
    'author',
    'narrator',
    'series',
    'seriesIndex',
    'genre',
    'publisher',
    'language',
  };

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Audiobook> get _filteredBooks {
    final q = _searchQuery.toLowerCase();
    if (q.isEmpty) return widget.books;
    return widget.books.where((b) {
      return (b.title ?? '').toLowerCase().contains(q) ||
          (b.author ?? '').toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Copy metadata from…'),
      content: SizedBox(
        width: 500,
        height: 600,
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              onChanged: (q) => setState(() => _searchQuery = q),
              decoration: const InputDecoration(
                hintText: 'Search books…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _buildBookList(),
            ),
            if (_selectedBook != null) ...[
              const Divider(),
              const Text('Fields to copy:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _buildFieldCheckboxes(),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selectedBook == null || _selectedFields.isEmpty
              ? null
              : () => Navigator.pop(context, (_selectedBook!, _selectedFields)),
          child: const Text('Copy'),
        ),
      ],
    );
  }

  Widget _buildBookList() {
    final books = _filteredBooks;
    if (books.isEmpty) {
      return const Center(
        child: Text('No books found', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        final isSelected = _selectedBook?.path == book.path;
        return ListTile(
          selected: isSelected,
          selectedTileColor: Colors.white10,
          dense: true,
          onTap: () => setState(() => _selectedBook = book),
          title: Text(book.title ?? 'Untitled'),
          subtitle: Text(book.author ?? 'Unknown author'),
        );
      },
    );
  }

  Widget _buildFieldCheckboxes() {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        _buildFieldCheckbox('Author', 'author'),
        _buildFieldCheckbox('Narrator', 'narrator'),
        _buildFieldCheckbox('Series', 'series'),
        _buildFieldCheckbox('Series #', 'seriesIndex'),
        _buildFieldCheckbox('Genre', 'genre'),
        _buildFieldCheckbox('Publisher', 'publisher'),
        _buildFieldCheckbox('Language', 'language'),
      ],
    );
  }

  Widget _buildFieldCheckbox(String label, String field) {
    return FilterChip(
      label: Text(label),
      selected: _selectedFields.contains(field),
      onSelected: (selected) {
        setState(() {
          if (selected) {
            _selectedFields.add(field);
          } else {
            _selectedFields.remove(field);
          }
        });
      },
    );
  }
}
