import 'package:fireplace/main.dart';
import 'package:fireplace/widgets/portrait_lock_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'FireplaceApp wraps routes with PortraitLockShell via MaterialApp.builder',
    (tester) async {
      await tester.pumpWidget(const FireplaceApp());

      expect(find.byType(PortraitLockShell), findsOneWidget);
      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.builder, isNotNull);
    },
  );
}
