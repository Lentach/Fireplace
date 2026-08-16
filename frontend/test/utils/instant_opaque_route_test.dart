import 'package:fireplace/utils/instant_opaque_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({bool disableAnimations = false}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: disableAnimations),
      child: child!,
    ),
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
  );
}

void main() {
  testWidgets(
    'instant opaque route never exposes the previous route during push',
    (tester) async {
      await tester.pumpWidget(_host());

      expect(find.text('conversation-list-route'), findsOneWidget);

      await tester.tap(find.text('conversation-list-route'));
      await tester.pump();

      // The forward transition must stay ZERO-DURATION and OPAQUE: a single
      // pump lands fully on the chat route with the previous tab not painted.
      // This guards the mobile-web half-transition freeze that painted the
      // conversations tab and the chat room together.
      expect(find.text('chat-detail-route'), findsOneWidget);
      expect(find.text('conversation-list-route'), findsNothing);
    },
  );

  testWidgets('pop fades the chat route out over ~180ms', (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('conversation-list-route'));
    await tester.pump();
    expect(find.text('chat-detail-route'), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();

    // Mid-fade: both routes are painted, the popped route is translucent.
    await tester.pump(const Duration(milliseconds: 90));
    expect(find.text('chat-detail-route'), findsOneWidget);
    expect(find.text('conversation-list-route'), findsOneWidget);
    final fade = tester.widget<FadeTransition>(
      find
          .ancestor(
            of: find.text('chat-detail-route'),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(fade.opacity.value, closeTo(0.5, 0.01));

    await tester.pump(const Duration(milliseconds: 90));
    await tester.pumpAndSettle();
    expect(find.text('chat-detail-route'), findsNothing);
    expect(find.text('conversation-list-route'), findsOneWidget);
  });

  testWidgets('reduce-motion pop skips the fade entirely', (tester) async {
    await tester.pumpWidget(_host(disableAnimations: true));
    await tester.tap(find.text('conversation-list-route'));
    await tester.pump();
    expect(find.text('chat-detail-route'), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));

    // No FadeTransition wraps the popped route under reduce-motion; it stays
    // fully opaque until the route is torn down.
    expect(
      find.ancestor(
        of: find.text('chat-detail-route'),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );

    await tester.pumpAndSettle();
    expect(find.text('chat-detail-route'), findsNothing);
    expect(find.text('conversation-list-route'), findsOneWidget);
  });
}
