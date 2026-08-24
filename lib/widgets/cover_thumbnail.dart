import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:audiovault_editor/models/audiobook.dart';

/// A small square thumbnail showing a book's cover image, or a placeholder icon.
///
/// Images are decoded at thumbnail resolution (via [Image.cacheWidth]) rather
/// than at full embedded-art resolution, which keeps memory and scroll jank
/// under control in large libraries.
class CoverThumbnail extends StatelessWidget {
  final Audiobook book;
  final double size;

  const CoverThumbnail({
    super.key,
    required this.book,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    // Decode no larger than needed for the on-screen pixel size.
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
    final cacheSize = math.max(1, (size * dpr).round());

    Widget image;

    if (book.coverImageBytes != null) {
      image = Image.memory(
        book.coverImageBytes!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: cacheSize,
        errorBuilder: (context, error, stack) => _placeholder(),
      );
    } else if (book.coverImagePath != null) {
      image = Image.file(
        File(book.coverImagePath!),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: cacheSize,
        errorBuilder: (context, error, stack) => _placeholder(),
      );
    } else {
      image = _placeholder();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        width: size,
        height: size,
        child: image,
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: size,
      height: size,
      color: Colors.grey[800],
      child: Icon(
        Icons.book,
        size: size * 0.6,
        color: Colors.grey[600],
      ),
    );
  }
}
