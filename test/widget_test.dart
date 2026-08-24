import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audiovault_editor/main.dart';

void main() {
  testWidgets('App renders with welcome state and toolbar', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(const AudioVaultEditorApp());
    await tester.pump();

    // Welcome screen (empty library) shows its own call-to-action alongside
    // the toolbar button.
    expect(find.text('Welcome to AudioVault Editor'), findsOneWidget);
    expect(find.text('Open Folder'), findsWidgets);
    expect(find.text('Settings'), findsNothing); // gear is icon-only
  });
}
