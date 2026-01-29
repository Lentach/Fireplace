import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart';

void main() {
  testWidgets('App renders AuthGate', (WidgetTester tester) async {
    await tester.pumpWidget(const RpgChatApp());
    // Verify the app renders without errors
    expect(find.byType(AuthGate), findsOneWidget);
  });
}
