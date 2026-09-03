import 'package:fireplace/main.dart';
import 'package:fireplace/theme/app_scroll_behavior.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // See the portrait-lock test: PasscodeProvider reads prefs at boot.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'FireplaceApp wires AppScrollBehavior into MaterialApp',
    (tester) async {
      await tester.pumpWidget(const FireplaceApp());

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.scrollBehavior, isA<AppScrollBehavior>());
    },
  );
}
