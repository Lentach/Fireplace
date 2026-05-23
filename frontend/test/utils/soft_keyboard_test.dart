import 'package:fireplace/utils/soft_keyboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('showSoftKeyboardIfHidden is no-op on web', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () => showSoftKeyboardIfHidden(
                context: context,
                hasFocus: true,
              ),
              child: const Text('show'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pump();
  });
}
