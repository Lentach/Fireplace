import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('App renders AuthGate once the passcode gate resolves',
      (WidgetTester tester) async {
    await tester.pumpWidget(const FireplaceApp());

    // The gate covers the app while PasscodeProvider is still reading its
    // credential (`PasscodeLockState.unknown`), so the shell only appears
    // after that first async hop. Without a passcode configured — and with
    // no SharedPreferences mock here, which makes the store throw — the gate
    // must fail OPEN rather than hold a blank surface forever.
    await tester.pump();

    expect(find.byType(AuthGate), findsOneWidget);
  });
}
