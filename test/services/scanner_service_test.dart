import 'package:flutter_test/flutter_test.dart';
import 'package:audiovault_editor/services/scanner_service.dart';

void main() {
  group('ScannerService.naturalSort', () {
    // naturalSort is private, so we test it via the public sort behaviour
    // by checking that scanFolder returns books in sorted order.
    // For the comparator logic itself we test through a thin wrapper exposed
    // on the class for testability.

    test('sorts purely numeric segments numerically', () {
      final names = ['track10.mp3', 'track2.mp3', 'track1.mp3'];
      names.sort(ScannerService.naturalSortCompare);
      expect(names, ['track1.mp3', 'track2.mp3', 'track10.mp3']);
    });

    test('sorts mixed alpha-numeric correctly', () {
      final names = ['Chapter 9.mp3', 'Chapter 10.mp3', 'Chapter 2.mp3'];
      names.sort(ScannerService.naturalSortCompare);
      expect(names,
          ['Chapter 2.mp3', 'Chapter 9.mp3', 'Chapter 10.mp3']);
    });

    test('handles equal strings', () {
      expect(ScannerService.naturalSortCompare('a.mp3', 'a.mp3'), 0);
    });

    test('pure alpha sorts lexicographically', () {
      final names = ['beta.mp3', 'alpha.mp3', 'gamma.mp3'];
      names.sort(ScannerService.naturalSortCompare);
      expect(names, ['alpha.mp3', 'beta.mp3', 'gamma.mp3']);
    });

    test('numbers before letters', () {
      final names = ['b.mp3', '1.mp3', 'a.mp3'];
      names.sort(ScannerService.naturalSortCompare);
      expect(names.first, '1.mp3');
    });
  });
}
