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

    final glyph = tester.widget<PingGlyph>(find.byType(PingGlyph));
    expect(glyph.size, 24);
    expect(glyph.color, color);
    expect(tester.getSize(find.byType(PingGlyph)), const Size.square(24));
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
