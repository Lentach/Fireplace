import 'package:fireplace/widgets/input/recording_waveform.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('RecordingWaveform paints without error', (tester) async {
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(milliseconds: 1200),
    )..value = 0.3;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 120,
          height: 24,
          child: RecordingWaveform(
            progress: controller.value,
            color: const Color(0xFFFF0000),
          ),
        ),
      ),
    );

    expect(find.byType(RecordingWaveform), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('degenerate size (0x0) hits the guard without painting/throwing',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 0,
          height: 0,
          child: RecordingWaveform(
            progress: 0.5,
            color: Color(0xFFFF0000),
          ),
        ),
      ),
    );

    expect(find.byType(RecordingWaveform), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('barCount:0 hits the guard without painting/throwing',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 120,
          height: 24,
          child: RecordingWaveform(
            progress: 0.5,
            color: Color(0xFFFF0000),
            barCount: 0,
          ),
        ),
      ),
    );

    expect(find.byType(RecordingWaveform), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'painter geometry is progress-driven (shouldRepaint across progress)',
      (tester) async {
    // The waveform's whole contract is that bar geometry is a function of
    // progress. The CustomPainter must therefore report a repaint when only
    // progress changes; a regression that ignored progress would return false
    // and freeze the animation.
    Future<CustomPainter> painterFor(double progress) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 120,
            height: 24,
            child: RecordingWaveform(
              progress: progress,
              color: const Color(0xFFFF0000),
            ),
          ),
        ),
      );
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(RecordingWaveform),
          matching: find.byType(CustomPaint),
        ),
      );
      return paint.painter!;
    }

    final p0 = await painterFor(0.0);
    final p0again = await painterFor(0.0);
    final p5 = await painterFor(0.5);

    // Distinct progress -> must repaint (geometry differs).
    expect(p5.shouldRepaint(p0), isTrue);
    // Identical progress -> must NOT repaint (proves it actually compares
    // progress rather than always returning true).
    expect(p0again.shouldRepaint(p0), isFalse);
  });
}
