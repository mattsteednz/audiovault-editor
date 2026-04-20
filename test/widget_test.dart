import 'package:flutter_test/flutter_test.dart';
import 'package:audiovault_editor/main.dart';

void main() {
  testWidgets('App renders', (WidgetTester tester) async {
    await tester.pumpWidget(const AudioVaultEditorApp());
    expect(find.text('Open Folder'), findsOneWidget);
  });
}
