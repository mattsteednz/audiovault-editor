import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audiovault_editor/controllers/library_controller.dart';
import 'package:audiovault_editor/models/audiobook.dart';
import 'package:audiovault_editor/services/scanner_service.dart';

/// Deterministic scanner stub — no filesystem access.
class FakeScanner extends ScannerService {
  FakeScanner(this.books);

  final List<Audiobook> books;
  bool Function()? lastCancelled;

  @override
  Future<List<Audiobook>> scanFolder(String folderPath,
      {void Function(Audiobook)? onBookFound,
      void Function(int found, int total)? onProgress,
      bool Function()? cancelled}) async {
    lastCancelled = cancelled;
    final out = <Audiobook>[];
    for (final b in books) {
      if (!(cancelled?.call() ?? false)) {
        out.add(b);
        onBookFound?.call(b);
      }
      onProgress?.call(out.length, books.length);
      // Yield to the event loop so cancellation callbacks can interleave.
      await Future<void>.delayed(Duration.zero);
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
  String path, {
  String? title,
  String? author,
  String? coverImagePath,
  ReadOnlyStatus readOnlyStatus = ReadOnlyStatus.writable,
}) =>
    Audiobook(
      path: path,
      audioFiles: const [],
      title: title,
      author: author,
      coverImagePath: coverImagePath,
      readOnlyStatus: readOnlyStatus,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('LibraryController.pickFolder', () {
    test('populates books, clears transient state, saves folder', () async {
      final ctrl = LibraryController(
        scanner: FakeScanner([
          book('/l/a', title: 'A', author: 'X'),
          book('/l/b', title: 'B', author: 'Y'),
        ]),
      );

      await ctrl.pickFolder('/lib');

      expect(ctrl.folderPath, '/lib');
      expect(ctrl.scanning, isFalse);
      expect(ctrl.books, hasLength(2));
      expect(ctrl.selected, isNull);
      expect(ctrl.batchPaths, isEmpty);
      expect(ctrl.dirtyPaths, isEmpty);
      // Folder preference persisted.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('folder_path'), '/lib');
    });

    test('reports scanning state transitions and progress', () async {
      final ctrl = LibraryController(scanner: FakeScanner([
        book('/l/a', title: 'A'),
      ]));

      var sawScanning = false;
      ctrl.addListener(() {
        if (ctrl.scanning) sawScanning = true;
      });

      expect(ctrl.scanning, isFalse);
      final f = ctrl.pickFolder('/lib');
      expect(ctrl.scanning, isTrue);
      await f;
      expect(ctrl.scanning, isFalse);
      expect(sawScanning, isTrue);
    });
  });

  group('LibraryController flags recompute', () {
    test('duplicate + missing-cover sets computed after scan', () async {
      final ctrl = LibraryController(
        scanner: FakeScanner([
          book('/l/a', title: 'Same Title!', author: 'Auth'),
          book('/l/b', title: 'same title', author: 'AUTH'),
          book('/l/c', title: 'Unique'),
        ]),
      );

      await ctrl.pickFolder('/lib');

      // a+b normalise to the same key; c has no cover either but dupes are
      // keyed on title+author only.
      expect(ctrl.duplicateCount, 2);
      expect(ctrl.duplicatePaths, containsAll(['/l/a', '/l/b']));
      expect(ctrl.missingCoverCount, 3);
    });

    test('onBatchApplied recomputes stale flags', () async {
      final ctrl = LibraryController(
        scanner: FakeScanner([
          book('/l/a', title: 'A', author: 'X'),
          book('/l/b', title: 'A', author: 'X'), // duplicate of /l/a
        ]),
      );
      await ctrl.pickFolder('/lib');
      expect(ctrl.duplicateCount, 2);

      // Batch apply renames one of the duplicates so they no longer collide.
      ctrl.toggleBatch(ctrl.books.first, selected: true);
      ctrl.onBatchApplied([
        book('/l/a', title: 'Renamed', author: 'X'),
      ]);

      expect(ctrl.duplicateCount, 0, reason: 'flags must be recomputed');
      expect(ctrl.batchPaths, isEmpty);
    });

    test('rescanSelected refreshes flags for the rescanned book', () async {
      var current = [
        book('/l/a', title: 'A', author: 'X'),
      ];
      final scanner = FakeScanner(current);
      final ctrl = LibraryController(scanner: scanner);
      await ctrl.pickFolder('/lib');
      ctrl.selectBook(ctrl.books.single);
      expect(ctrl.missingCoverCount, 1);

      // Simulate the user adding cover.jpg externally, then rescanning.
      current = [book('/l/a', title: 'A', author: 'X', coverImagePath: '/l/a/cover.jpg')];
      scanner.books.clear();
      scanner.books.addAll(current);

      await ctrl.rescanSelected();

      expect(ctrl.missingCoverCount, 0, reason: 'flags must be recomputed');
      expect(ctrl.selected!.coverImagePath, '/l/a/cover.jpg');
    });

    test('undo restores previous state and recomputes flags', () async {
      final applied = <Audiobook>[];
      final ctrl = LibraryController(
        scanner: FakeScanner([book('/l/a', title: 'A')]),
        applySnapshot: (b) async => applied.add(b),
      );
      await ctrl.pickFolder('/lib');

      ctrl.selectBook(ctrl.books.single);
      ctrl.onBookApplied(book('/l/a', title: 'B'));
      expect(ctrl.canUndo, isTrue);
      expect(ctrl.topUndoLabel, 'Apply tags');

      await ctrl.undo();

      expect(applied, hasLength(1));
      expect(ctrl.canUndo, isFalse);
      expect(ctrl.selected!.title, 'A');
    });

    test('undo survives an injected write failure without throwing',
        () async {
      final ctrl = LibraryController(
        scanner: FakeScanner([book('/l/a', title: 'A')]),
        applySnapshot: (b) async => throw Exception('disk error'),
      );
      await ctrl.pickFolder('/lib');
      ctrl.selectBook(ctrl.books.single);
      ctrl.onBookApplied(book('/l/a', title: 'B'));

      await ctrl.undo(); // must not throw

      expect(ctrl.selected!.title, 'A');
      expect(ctrl.canUndo, isFalse);
    });

    test('redo re-applies after undo', () async {
      final ctrl = LibraryController(
        scanner: FakeScanner([book('/l/a', title: 'A')]),
        applySnapshot: (b) async {},
      );
      await ctrl.pickFolder('/lib');
      ctrl.selectBook(ctrl.books.single);
      ctrl.onBookApplied(book('/l/a', title: 'B'));

      await ctrl.undo();
      expect(ctrl.selected!.title, 'A');
      expect(ctrl.canRedo, isTrue);

      await ctrl.redo();
      expect(ctrl.selected!.title, 'B');
      expect(ctrl.canRedo, isFalse);
    });

    test('undo stack is capped at 25 entries', () async {
      final ctrl = LibraryController(
        scanner: FakeScanner([book('/l/a', title: '0')]),
        applySnapshot: (b) async {},
      );
      await ctrl.pickFolder('/lib');
      ctrl.selectBook(ctrl.books.single);

      for (int i = 1; i <= 30; i++) {
        ctrl.onBookApplied(book('/l/a', title: 'v$i'));
      }
      expect(ctrl.canUndo, isTrue);

      var undone = 0;
      while (ctrl.canUndo) {
        await ctrl.undo();
        undone++;
      }
      expect(undone, 25,
          reason: 'stack must be capped at _maxUndoEntries');
      // Oldest surviving state is v5 (30 - 25).
      expect(ctrl.selected!.title, 'v5');
    });
  });

  group('LibraryController read-only status flags', () {
    test('readOnly count and filter work', () async {
      final ctrl = LibraryController(
        scanner: FakeScanner([
          book('/l/a', title: 'A', readOnlyStatus: ReadOnlyStatus.filesReadOnly),
          book('/l/b', title: 'B'),
        ]),
      );
      await ctrl.pickFolder('/lib');

      expect(ctrl.readOnlyCount, 1);
      expect(ctrl.showReadOnlyOnly, isFalse);

      ctrl.toggleShowReadOnly();
      expect(ctrl.showReadOnlyOnly, isTrue);
      expect(ctrl.filteredBooks.map((b) => b.path), ['/l/a']);

      ctrl.toggleShowReadOnly();
      expect(ctrl.filteredBooks, hasLength(2));
    });
  });

  group('LibraryController filtering & sorting', () {
    Future<LibraryController> seeded() async {
      final ctrl = LibraryController(
        scanner: FakeScanner([
          book('/l/1', title: 'Banana', author: 'Ann'),
          book('/l/2', title: 'Apple', author: 'Bob'),
          book('/l/3', title: 'Cherry', author: 'Cid'),
        ]),
      );
      await ctrl.pickFolder('/lib');
      return ctrl;
    }

    test('search filters by title and author', () async {
      final ctrl = await seeded();

      ctrl.setSearchQuery('app');
      expect(ctrl.filteredBooks.map((b) => b.title), ['Apple']);

      ctrl.setSearchQuery('bob');
      expect(ctrl.filteredBooks.map((b) => b.title), ['Apple']);

      ctrl.setSearchQuery('');
      expect(ctrl.filteredBooks, hasLength(3));
    });

    test('sort orders are applied', () async {
      final ctrl = await seeded();

      ctrl.setSortOrder(SortOrder.titleDesc);
      expect(ctrl.filteredBooks.map((b) => b.title).first, 'Cherry');

      ctrl.setSortOrder(SortOrder.authorAsc);
      expect(ctrl.filteredBooks.map((b) => b.author).first, 'Ann');
    });

    test('filteredBooks cache invalidates on notifyListeners', () async {
      final ctrl = await seeded();
      final first = ctrl.filteredBooks;
      identical(first, ctrl.filteredBooks); // cached between notifications

      ctrl.setSearchQuery('apple');
      final second = ctrl.filteredBooks;
      expect(identical(first, second), isFalse,
          reason: 'cache must invalidate when state changes');
      expect(second, hasLength(1));
    });
  });

  group('LibraryController batch selection', () {
    test('toggleBatch does not change the selected detail book', () async {
      final ctrl = LibraryController(
        scanner: FakeScanner([
          book('/l/a', title: 'A'),
          book('/l/b', title: 'B'),
        ]),
      );
      await ctrl.pickFolder('/lib');

      ctrl.selectBook(ctrl.books[0]);
      ctrl.toggleBatch(ctrl.books[1], selected: true);

      expect(ctrl.batchPaths, contains('/l/b'));
      expect(ctrl.selected!.path, '/l/a',
          reason: 'checkbox toggling must not switch the detail view');
    });

    test('clearBatchSelection empties selection', () async {
      final ctrl = LibraryController(
        scanner: FakeScanner([book('/l/a', title: 'A')]),
      );
      await ctrl.pickFolder('/lib');
      ctrl.toggleBatch(ctrl.books.single, selected: true);
      expect(ctrl.batchPaths, hasLength(1));

      ctrl.clearBatchSelection();
      expect(ctrl.batchPaths, isEmpty);
    });
  });

  group('LibraryController markDirty', () {
    test('adds/removes path and notifies', () async {
      final ctrl = LibraryController(
        scanner: FakeScanner([book('/l/a', title: 'A')]),
      );
      await ctrl.pickFolder('/lib');

      var notified = 0;
      ctrl.addListener(() => notified++);

      ctrl.markDirty('/l/a', dirty: true);
      expect(ctrl.dirtyPaths, ['/l/a']);
      expect(notified, 1);

      ctrl.markDirty('/l/a', dirty: true);
      expect(notified, 2, reason: 'notify even when set content unchanged');

      ctrl.markDirty('/l/a', dirty: false);
      expect(ctrl.dirtyPaths, isEmpty);
    });
  });
}
