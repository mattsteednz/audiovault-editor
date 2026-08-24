import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiovault_editor/models/chapter_entry.dart';
import 'package:audiovault_editor/widgets/quick_edit_dialog.dart';

/// Opens the dialog; returns (resultFuture, editorTextGetter).
Future<(Future<List<ChapterEntry>?>, String Function())> _open(
  WidgetTester tester, {
  required List<ChapterEntry> initial,
  required bool isSingleFile,
  Duration? bookDuration = const Duration(hours: 1),
}) async {
  final navKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: const Scaffold(body: SizedBox.shrink())));

  String text() =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  final result = showDialog<List<ChapterEntry>>(
    context: navKey.currentContext!,
    builder: (_) => QuickEditDialog(
      initialEntries: initial,
      isSingleFile: isSingleFile,
      bookDuration: bookDuration,
      onSave: (entries) => Navigator.of(navKey.currentContext!).pop(entries),
    ),
  );
  await tester.pumpAndSettle();
  return (result, text);
}

FilledButton _saveButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));

void main() {
  testWidgets('multi-file books default to Names-only mode (no toggle)',
      (tester) async {
    final (result, text) = await _open(tester, initial: [
      const ChapterEntry(title: 'Part One', start: Duration.zero),
      const ChapterEntry(title: 'Part Two', start: Duration.zero),
    ], isSingleFile: false, bookDuration: null);

    // Mode toggle is hidden for multi-file books.
    expect(find.text('Names + Times'), findsNothing);
    expect(text(), 'Part One\nPart Two');

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await result;
  });

  testWidgets('single-file books default to Names+Times mode',
      (tester) async {
    final (result, text) = await _open(tester, initial: [
      const ChapterEntry(title: 'Intro', start: Duration.zero),
      const ChapterEntry(title: 'Story', start: Duration(minutes: 5)),
    ], isSingleFile: true);

    expect(find.text('Names + Times'), findsOneWidget);
    expect(text(), 'Intro, 00:00:00\nStory, 00:05:00');

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await result;
  });

  testWidgets('switching to Times-only re-serialises without titles',
      (tester) async {
    final (result, text) = await _open(tester, initial: [
      const ChapterEntry(title: 'Intro', start: Duration.zero),
      const ChapterEntry(title: 'Story', start: Duration(minutes: 5)),
    ], isSingleFile: true);

    await tester.tap(find.text('Times'));
    await tester.pumpAndSettle();

    expect(text(), '00:00:00\n00:05:00');
    expect(text().contains('Intro'), isFalse);

    await tester.tap(find.text('Names'));
    await tester.pumpAndSettle();
    expect(text(), 'Intro\nStory');

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await result;
  });

  testWidgets('invalid timestamp disables Save and shows error count',
      (tester) async {
    final (result, _) = await _open(tester, initial: [
      const ChapterEntry(title: 'A', start: Duration.zero),
    ], isSingleFile: true);

    await tester.enterText(find.byType(TextField), 'A, banana');
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('error'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNull);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await result;
  });

  testWidgets('conflicting timestamps block Save', (tester) async {
    final (result, _) = await _open(tester, initial: [
      const ChapterEntry(title: 'A', start: Duration.zero),
      const ChapterEntry(title: 'B', start: Duration(minutes: 5)),
    ], isSingleFile: true);

    await tester.enterText(find.byType(TextField), 'A, 00:01:00\nB, 00:01:00');
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Timestamp conflicts detected'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNull);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await result;
  });

  testWidgets('start beyond book duration blocks Save', (tester) async {
    final (result, _) = await _open(tester, initial: [
      const ChapterEntry(title: 'A', start: Duration.zero),
    ], isSingleFile: true, bookDuration: const Duration(minutes: 10));

    await tester.enterText(find.byType(TextField), 'A, 00:59:00');
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Start time exceeds book duration'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNull);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await result;
  });

  testWidgets('Names-only save merges new titles onto original timestamps',
      (tester) async {
    List<ChapterEntry>? saved;
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: SizedBox.shrink())));
    final result = showDialog<List<ChapterEntry>>(
      context: navKey.currentContext!,
      builder: (_) => QuickEditDialog(
        initialEntries: [
          const ChapterEntry(title: 'Old A', start: Duration(minutes: 3)),
          const ChapterEntry(title: 'Old B', start: Duration(minutes: 9)),
        ],
        isSingleFile: false,
        onSave: (e) => Navigator.of(navKey.currentContext!).pop(e),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Fresh A\nFresh B');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    saved = await result;
    expect(saved![0].title, 'Fresh A');
    expect(saved[0].start, const Duration(minutes: 3));
    expect(saved[1].title, 'Fresh B');
    expect(saved[1].start, const Duration(minutes: 9));
  });
}
