import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/widgets/ping_effect_overlay.dart';
import 'package:fireplace/widgets/ping_glyph.dart';

void main() {
  testWidgets(
    'PingEffectOverlay pumps, completes, and disposes without throw',
    (tester) async {
      var completed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PingEffectOverlay(onComplete: () => completed = true),
          ),
        ),
      );
      await tester.pump();
      final glyph = tester.widget<PingGlyph>(find.byType(PingGlyph));
      expect(glyph.size, 50);
      expect(glyph.color, Colors.white);
      await tester.pump(const Duration(milliseconds: 900));
      expect(completed, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
