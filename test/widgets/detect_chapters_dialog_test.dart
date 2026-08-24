// Controllers here live exactly as long as their test; closing them in
// teardown adds noise without value.
// ignore_for_file: close_sinks
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiovault_editor/models/chapter_entry.dart';
import 'package:audiovault_editor/services/silence_detection_service.dart';
import 'package:audiovault_editor/widgets/detect_chapters_dialog.dart';

/// Fake detection service driven by a queue of streams — one per detect()
/// call. No ffmpeg involved.
class FakeDetector extends SilenceDetectionService {
  final List<Stream<SilenceDetectionProgress>> streams;
  int calls = 0;
  bool cancelCalled = false;

  FakeDetector(this.streams);

  factory FakeDetector.single(List<SilenceDetectionProgress> events) {
    final ctrl = StreamController<SilenceDetectionProgress>();
    for (final e in events) {
      ctrl.add(e);
    }
    // Keep the controller open so terminal-event semantics stay realistic.
    final detector = FakeDetector([ctrl.stream]);
    detector._ownedControllers.add(ctrl);
    return detector;
  }

  final _ownedControllers = <StreamController<SilenceDetectionProgress>>[];

  /// Closes controllers owned by this fake (call from test teardown).
  void dispose() {
    for (final c in _ownedControllers) {
      // ignore: unawaited_futures
      c.close();
    }
  }

  @override
  Stream<SilenceDetectionProgress> detect({
    required String filePath,
    required double noiseFloorDb,
    required double minSilenceSecs,
    Duration? totalDuration,
  }) {
    if (calls >= streams.length) {
      throw StateError('unexpected extra detect() call');
    }
    return streams[calls++];
  }

  @override
  void cancel() => cancelCalled = true;
}

Future<Future<List<ChapterEntry>?>> _openDialog(
  WidgetTester tester, {
  required SilenceDetectionService service,
  int existingChapterCount = 0,
}) async {
  final navKey = GlobalKey<NavigatorState>();
  late Future<List<ChapterEntry>?> result;
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navKey,
      home: const Scaffold(body: SizedBox.shrink()),
    ),
  );

  // Open outside pumpWidget's guarded zone.
  result = showDetectChaptersDialog(
    context: navKey.currentContext!,
    filePath: '/books/x/book.m4b',
    totalDuration: const Duration(hours: 2),
    existingChapterCount: existingChapterCount,
    service: service,
  );
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('validation blocks detection on out-of-range floor',
      (tester) async {
    final detector = FakeDetector.single([
      SilenceDetectionComplete(const [Duration(seconds: 10)]),
    ]);
    final result = await _openDialog(tester, service: detector);

    await tester.enterText(
        find.widgetWithText(TextField, 'e.g. -45'), '-500');
    await tester.tap(find.text('Detect'));
    await tester.pump();

    expect(find.text('Enter a value between -90 and -20'), findsOneWidget);
    expect(detector.calls, 0);
    expect(find.text('Scanning audio…'), findsNothing);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await result;
  });

  testWidgets('successful detection shows preview and Apply returns entries',
      (tester) async {
    final detector = FakeDetector.single([
      SilenceDetectionComplete([
        const Duration(minutes: 5),
        const Duration(minutes: 30),
      ]),
    ]);
    final result = await _openDialog(tester, service: detector);

    await tester.tap(find.text('Detect'));
    await tester.pumpAndSettle();

    expect(find.text('Found 3 chapters'), findsOneWidget);
    expect(find.text('Chapter 1'), findsOneWidget);

    await tester.tap(find.text('Apply chapters'));
    await tester.pumpAndSettle();

    final entries = await result;
    expect(entries, hasLength(3));
    expect(entries![0].start, Duration.zero);
    expect(entries[1].start, const Duration(minutes: 5));
  });

  testWidgets('boundaries closer than 5s to previous are filtered',
      (tester) async {
    final detector = FakeDetector.single([
      SilenceDetectionComplete([
        const Duration(seconds: 3), // <5s from zero -> dropped
        const Duration(minutes: 10),
        const Duration(minutes: 10, seconds: 2), // <5s gap -> dropped
      ]),
    ]);
    final result = await _openDialog(tester, service: detector);

    await tester.tap(find.text('Detect'));
    await tester.pumpAndSettle();
    expect(find.text('Found 2 chapters'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await result;
  });

  testWidgets('auto-retries when more than 100 chapters detected',
      (tester) async {
    final hugeList = List.generate(150, (i) => Duration(minutes: i));
    final retryCtrl = StreamController<SilenceDetectionProgress>();
    final detector = FakeDetector([
      Stream.value(SilenceDetectionComplete(hugeList)),
      retryCtrl.stream,
    ]);
    final result = await _openDialog(tester, service: detector);

    await tester.tap(find.text('Detect'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('retrying'), findsOneWidget);
    expect(find.textContaining('attempt 2/5'), findsOneWidget);

    retryCtrl.add(SilenceDetectionComplete([
      const Duration(minutes: 20),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('Found 2 chapters'), findsOneWidget);
    expect(detector.calls, 2);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await result;
  });

  testWidgets('error event surfaces a snackbar and returns to params',
      (tester) async {
    final detector = FakeDetector.single([
      SilenceDetectionError('ffmpeg exploded'),
    ]);
    final result = await _openDialog(tester, service: detector);

    await tester.tap(find.text('Detect'));
    await tester.pumpAndSettle();

    expect(find.textContaining('ffmpeg exploded'), findsOneWidget);
    expect(find.text('Detect'), findsOneWidget); // back at params view

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await result;
  });

  testWidgets('cancel pops the dialog and kills the detector', (tester) async {
    final detector = FakeDetector.single([]);
    final result = await _openDialog(tester, service: detector);

    await tester.tap(find.text('Detect'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(detector.cancelCalled, isTrue);
    expect(await result, isNull);
  });

  testWidgets('asks for confirmation before replacing existing chapters',
      (tester) async {
    final detector = FakeDetector.single([
      SilenceDetectionComplete([const Duration(minutes: 1)]),
    ]);
    final result = await _openDialog(tester, service: detector, existingChapterCount: 4);

    await tester.tap(find.text('Detect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply chapters'));
    await tester.pumpAndSettle();

    expect(find.text('Replace existing chapters?'), findsOneWidget);
    expect(find.textContaining('replace the 4 existing'), findsOneWidget);

    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    final entries = await result;
    expect(entries, hasLength(2));
  });
}
