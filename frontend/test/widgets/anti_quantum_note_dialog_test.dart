import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/widgets/anti_quantum_note_dialog.dart';

void main() {
  testWidgets('shows title and TTL chips', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AntiQuantumNoteDialog(
          onSend: (_, __) async {},
        ),
      ),
    ));

    expect(find.text('Anti-Quantum Note'), findsOneWidget);
    expect(find.text('2h'), findsOneWidget);
    expect(find.text('6h'), findsOneWidget);
    expect(find.text('12h'), findsOneWidget);
    expect(find.text('Generate & Send'), findsOneWidget);
  });

  testWidgets('Generate & Send disabled when text is empty', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AntiQuantumNoteDialog(
          onSend: (_, __) async {},
        ),
      ),
    ));

    final btn = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(btn.onPressed, isNull);
  });

  testWidgets('Generate & Send enabled when text is non-empty', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AntiQuantumNoteDialog(
          onSend: (_, __) async {},
        ),
      ),
    ));

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();

    final btn = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(btn.onPressed, isNotNull);
  });

  testWidgets('calls onSend with content and selected TTL', (tester) async {
    String? capturedContent;
    int? capturedTtl;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AntiQuantumNoteDialog(
          onSend: (content, ttl) async {
            capturedContent = content;
            capturedTtl = ttl;
          },
        ),
      ),
    ));

    await tester.enterText(find.byType(TextField), 'secret text');
    await tester.pump();

    // Tap 12h chip
    await tester.tap(find.text('12h'));
    await tester.pump();

    // Tap Generate & Send
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(capturedContent, 'secret text');
    expect(capturedTtl, 43200);
  });
}
