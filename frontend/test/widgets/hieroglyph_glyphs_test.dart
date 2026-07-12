import 'dart:ui';

import 'package:fireplace/theme/glass_theme.dart';
import 'package:fireplace/widgets/chat_background_pattern.dart';
import 'package:fireplace/widgets/hieroglyph_glyphs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registry is the v7 set: 36 unique glyphs, exactly one leaf', () {
    expect(kHieroGlyphs.length, 36);
    final names = kHieroGlyphs.map((g) => g.name).toList();
    expect(names.toSet().length, 36, reason: 'names must be unique');
    expect(kHieroGlyphs.where((g) => g.isLeaf).length, 1);
  });

  test('deleted glyphs are gone; remaining high runes present', () {
    final names = kHieroGlyphs.map((g) => g.name).toSet();
    for (final gone in ['was', 'reed', 'pool', 'gul', 'ohm', 'ber', 'sur']) {
      expect(names, isNot(contains(gone)), reason: '$gone should be deleted');
    }
    for (final rune in ['vex', 'lo', 'jah', 'cham', 'zod']) {
      expect(names, contains(rune), reason: '$rune rune should remain');
    }
  });

  test('every glyph paints on a canvas without throwing', () {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final fill = Paint()..style = PaintingStyle.fill;
    for (final g in kHieroGlyphs) {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      expect(() => g.paintFn(canvas, stroke, fill), returnsNormally,
          reason: 'glyph "${g.name}" must paint without error');
      recorder.endRecording().dispose();
    }
  });

  testWidgets(
      'ChatBackgroundPattern renders the real painter over a full tall column '
      'without throwing', (tester) async {
    // Tall surface so the real _TempleColumnsPainter deals many rows across
    // several columns, exercising the actual bag-shuffle over the whole set.
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const <ThemeExtension<dynamic>>[
          GlassTheme.dark,
        ]),
        home: const Scaffold(
          body: ChatBackgroundPattern(
            patternColor: Color(0xFF8FC4D0),
            backgroundColor: Color(0xFF000000),
            child: SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(ChatBackgroundPattern), findsOneWidget);
  });
}
