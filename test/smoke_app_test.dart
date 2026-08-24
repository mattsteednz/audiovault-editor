import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audiovault_editor/main.dart';
import 'package:audiovault_editor/controllers/library_controller.dart';
import 'package:audiovault_editor/models/audiobook.dart';
import 'package:audiovault_editor/services/scanner_service.dart';

/// Deterministic in-memory scanner for smoke tests.
class SmokeScanner extends ScannerService {
  @override
  Future<List<Audiobook>> scanFolder(String folderPath,
      {void Function(Audiobook)? onBookFound,
      void Function(int found, int total)? onProgress,
      bool Function()? cancelled}) async {
    final books = [
      const Audiobook(
          path: '/lib/dune',
          audioFiles: ['/lib/dune/book.m4b'],
          title: 'Dune',
          author: 'Frank Herbert',
          narrator: 'Simon Vance'),
      const Audiobook(
          path: '/lib/phm',
          audioFiles: ['/lib/phm/book.m4b'],
          title: 'Project Hail Mary',
          author: 'Andy Weir'),
    ];
    for (final b in books) {
      onBookFound?.call(b);
    }
    return books;
  }
}

void main() {
  testWidgets('smoke: library scan renders, selection opens detail panel',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final ctrl = LibraryController(scanner: SmokeScanner());

    await tester.pumpWidget(AudioVaultEditorApp(controller: ctrl));

    // Kick off a scan the way the toolbar would.
    ctrl.pickFolder('/lib');
    await tester.pumpAndSettle();

    // Sidebar lists both books with covers placeholder + titles.
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Project Hail Mary'), findsOneWidget);

    // Selecting a book opens the detail editor.
    await tester.tap(find.text('Dune'));
    await tester.pumpAndSettle();
    expect(find.text('Author:'), findsWidgets); // summary + form label
    expect(find.text('Narrated by:'), findsOneWidget);

    // Detail shows the selected book's narrator (summary + form field).
    expect(find.textContaining('Simon Vance'), findsWidgets);
  });
}
