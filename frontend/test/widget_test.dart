import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/main.dart';

void main() {
  testWidgets('App renders AuthGate', (WidgetTester tester) async {
    await tester.pumpWidget(const FireplaceApp());
    // Verify the app renders without errors
    expect(find.byType(AuthGate), findsOneWidget);
  });
}
