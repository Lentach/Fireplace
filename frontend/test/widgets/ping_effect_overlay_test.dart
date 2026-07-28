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

  // Bug 3 residual: leaving the chat INSIDE the 800ms animation unmounts the
  // overlay before forward().then can run onComplete. Without the dispose
  // fallback the showPingEffect flag stays latched and the next chat entry
  // remounts the overlay and replays the sound (same-session replay).
  testWidgets('early unmount still reports completion exactly once', (
    tester,
  ) async {
    var completions = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PingEffectOverlay(onComplete: () => completions++),
        ),
      ),
    );
    // Mid-animation: 300ms of 800ms elapsed, onComplete not yet fired.
    await tester.pump(const Duration(milliseconds: 300));
    expect(completions, 0);

    // Route-pop equivalent: unmount the overlay before the animation ends.
    await tester.pumpWidget(const SizedBox.shrink());
    // Drain the dispose-scheduled microtask.
    await tester.pump();

    expect(completions, 1);

    // The pending forward().then must not double-fire after the timer window.
    await tester.pump(const Duration(milliseconds: 900));
    expect(completions, 1);
  });
}
