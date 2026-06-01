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
}
