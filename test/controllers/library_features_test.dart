import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audiovault_editor/controllers/library_controller.dart';
import 'package:audiovault_editor/models/audiobook.dart';
import 'package:audiovault_editor/services/scanner_service.dart';

/// Deterministic scanner stub — no filesystem access.
class StubScanner extends ScannerService {
  StubScanner(this.books);
  final List<Audiobook> books;

  @override
  Future<List<Audiobook>> scanFolder(String folderPath,
      {void Function(Audiobook)? onBookFound,
      void Function(int found, int total)? onProgress,
      bool Function()? cancelled}) async {
    final out = <Audiobook>[];
    for (final b in books) {
      if (!(cancelled?.call() ?? false)) {
        out.add(b);
        onBookFound?.call(b);
      }
    }
    return out;
  }

  @override
  Future<Audiobook?> scanBook(String folderPath) async {
    for (final b in books) {
      if (b.path == folderPath) return b;
    }
    return null;
  }
}

Audiobook book(
  String path,
  String title, {
  String? author,
  String? narrator,
  String? series,
  List<String>? audioFiles,
}) =>
    Audiobook(
      path: path,
      title: title,
      author: author,
      narrator: narrator,
      series: series,
      audioFiles: audioFiles ?? ['$path/book.m4b'],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('search covers narrator and series', () {
    late LibraryController ctrl;
    setUp(() async {
      ctrl = LibraryController(scanner: StubScanner([
        book('/l/1', 'Dune', author: 'Frank Herbert',
            narrator: 'Simon Vance', series: 'Dune Chronicles'),
        book('/l/2', 'Project Hail Mary', author: 'Andy Weir',
            narrator: 'Ray Porter'),
      ]));
      await ctrl.pickFolder('/l');
    });

    test('matches narrator', () {
      ctrl.setSearchQuery('porter');
      expect(ctrl.filteredBooks.map((b) => b.title), ['Project Hail Mary']);
    });

    test('matches series', () {
      ctrl.setSearchQuery('chronicles');
      expect(ctrl.filteredBooks.map((b) => b.title), ['Dune']);
    });
  });

  group('missing-chapters flag', () {
    test('single-file without chapters is flagged; multi-file is not',
        () async {
      final ctrl = LibraryController(scanner: StubScanner([
        const Audiobook(path: '/l/a', audioFiles: ['/l/a/x.m4b']),
        const Audiobook(path: '/l/b', audioFiles: ['/l/b/x.m4b'],
            chapters: [Chapter(title: 'C1', start: Duration.zero)]),
        const Audiobook(path: '/l/c', audioFiles: ['/l/c/1.mp3', '/l/c/2.mp3']),
      ]));
      await ctrl.pickFolder('/l');

      expect(ctrl.missingChaptersPaths, ['/l/a']);
      expect(ctrl.showMissingChaptersOnly, isFalse);

      ctrl.toggleShowMissingChapters();
      expect(ctrl.showMissingChaptersOnly, isTrue);
      expect(ctrl.filteredBooks.map((b) => b.path), ['/l/a']);
    });
  });

  group('selectNextAfter (apply-and-next)', () {
    late LibraryController ctrl;
    setUp(() async {
      ctrl = LibraryController(scanner: StubScanner([
        book('/l/1', 'A'),
        book('/l/2', 'B'),
        book('/l/3', 'C'),
      ]));
      await ctrl.pickFolder('/l');
    });

    test('advances to next book', () {
      ctrl.selectNextAfter('/l/2');
      expect(ctrl.selected!.path, '/l/3');
    });

    test('stays on last book', () {
      ctrl.selectBook(ctrl.books.last);
      ctrl.selectNextAfter('/l/3');
      expect(ctrl.selected!.path, '/l/3');
    });

    test('ignores unknown paths', () {
      ctrl.selectBook(ctrl.books.first);
      ctrl.selectNextAfter('/nowhere');
      expect(ctrl.selected!.path, '/l/1');
    });

    test('skips books hidden by the active filter', () async {
      // Give /l/2 a cover so enabling the No-cover chip hides it.
      final withCovers = [
        ctrl.books[0],
        ctrl.books[1].copyWith(coverImagePath: '/l/2/cover.jpg'),
        ctrl.books[2],
      ];
      ctrl.onBatchApplied(withCovers);
      ctrl.toggleShowMissingCover();
      expect(ctrl.filteredBooks.map((b) => b.path), ['/l/1', '/l/3']);

      // Advancing from /l/1 must land on /l/3, skipping hidden /l/2.
      ctrl.selectNextAfter('/l/1');
      expect(ctrl.selected!.path, '/l/3');
    });
  });

  group('last-book restore', () {
    test('restores selection after scan when the book still exists',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{'last_book_path': '/l/2'});
      final ctrl = LibraryController(scanner: StubScanner([
        book('/l/1', 'A'),
        book('/l/2', 'B'),
      ]));
      await ctrl.pickFolder('/l');
      expect(ctrl.selected?.path, '/l/2');
    });

    test('clears stale selection silently', () async {
      SharedPreferences.setMockInitialValues({
        'last_book_path': '/gone/book.m4b',
      });
      final ctrl = LibraryController(scanner: StubScanner([book('/l/1', 'A')]));
      await ctrl.pickFolder('/l');
      expect(ctrl.selected, isNull);
    });
  });
}
