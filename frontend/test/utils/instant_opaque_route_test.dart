import 'package:fireplace/utils/instant_opaque_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'instant opaque route never exposes the previous route during push',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      instantOpaqueRoute<void>(
                        builder: (_) =>
                            const Scaffold(body: Text('chat-detail-route')),
                      ),
                    );
                  },
                  child: const Text('conversation-list-route'),
                ),
              );
            },
          ),
        ),
      );

      expect(find.text('conversation-list-route'), findsOneWidget);

      await tester.tap(find.text('conversation-list-route'));
      await tester.pump();

      expect(find.text('chat-detail-route'), findsOneWidget);
      expect(find.text('conversation-list-route'), findsNothing);
    },
  );
}
