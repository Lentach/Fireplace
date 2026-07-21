import 'dart:ui';

import 'package:fireplace/widgets/message/ping_message_content.dart';
import 'package:fireplace/widgets/ping_glyph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('PingGlyph honors its requested compact size and color', (
    tester,
  ) async {
    const color = Color(0xFFEF6C00);
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(child: PingGlyph(size: 24, color: color)),
      ),
    );

    // The widget actually lays out at the requested size.
    expect(tester.getSize(find.byType(PingGlyph)), const Size.square(24));

    // The painter must actually stroke with the requested color: a real
    // rendered-pixel probe, not a constructor field read-back that cannot fail.
    final painter = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byType(PingGlyph),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;

    final bytes = await tester.runAsync(() async {
      final recorder = PictureRecorder();
      painter.paint(Canvas(recorder), const Size.square(24));
      final image = await recorder.endRecording().toImage(24, 24);
      final data = await image.toByteData(format: ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    });

    var found = false;
    for (var i = 0; i + 3 < bytes!.length; i += 4) {
      if (bytes[i + 3] < 250) continue; // opaque core pixels only
      final r = bytes[i], g = bytes[i + 1], b = bytes[i + 2];
      if ((r - 0xEF).abs() <= 4 && (g - 0x6C).abs() <= 4 && b <= 4) {
        found = true;
        break;
      }
    }
    expect(found, isTrue,
        reason: 'painter must stroke with the requested color');
  });

  testWidgets('ping message uses the shared glyph beside its label', (
    tester,
  ) async {
    const color = Color(0xFF123456);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PingMessageContent(isMine: false, textColor: color),
        ),
      ),
    );

    final glyph = tester.widget<PingGlyph>(find.byType(PingGlyph));
    expect(glyph.size, 18);
    expect(glyph.color, color);
    expect(find.text('PING!'), findsOneWidget);
    expect(find.byIcon(Icons.campaign), findsNothing);
  });
}
