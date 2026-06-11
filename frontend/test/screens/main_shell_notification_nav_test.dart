import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Minimal widget replicating the notification-navigation branch from
/// MainShell.build() (Option A): gated on the first conversations snapshot,
/// navigates only when the conversation exists locally, and replaces any open
/// chat route via pushAndRemoveUntil.
class _NotificationNavHost extends StatefulWidget {
  const _NotificationNavHost();

  @override
  State<_NotificationNavHost> createState() => _NotificationNavHostState();
}

class _NotificationNavHostState extends State<_NotificationNavHost> {
  @override
  Widget build(BuildContext context) {
    return Consumer<ConversationsProvider>(
      builder: (context, convs, _) {
        if (convs.pendingNotificationConversationId != null &&
            convs.hasLoadedConversationsOnce) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final provider = context.read<ConversationsProvider>();
            final id = provider.consumePendingNotificationConversationId();
            if (id == null) return;
            if (provider.getConversationById(id) == null) return;
            if (provider.activeConversationId == id) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute<void>(
                  builder: (_) => Scaffold(body: Text('chat-$id'))),
              (route) => route.isFirst,
            );
          });
        }
        return const Scaffold(body: Text('main-shell'));
      },
    );
  }
}

Map<String, dynamic> _convJson(int id) => {
      'id': id,
      'userOne': {'id': 1, 'username': 'alice', 'tag': '0001'},
      'userTwo': {'id': 2, 'username': 'bob', 'tag': '0002'},
      'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      'unreadCount': 0,
    };

void main() {
  Widget buildApp(ConversationsProvider convs) {
    return ChangeNotifierProvider<ConversationsProvider>.value(
      value: convs,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const _NotificationNavHost(),
      ),
    );
  }

  testWidgets(
      'notification nav to new conv replaces existing chat route (no stacking)',
      (tester) async {
    final convs = ConversationsProvider();
    convs.onConversationsList([_convJson(1), _convJson(2)]);

    await tester.pumpWidget(buildApp(convs));
    await tester.pumpAndSettle();

    // Simulate being already in Chat A (push it on top of the root).
    final navState = tester.state<NavigatorState>(find.byType(Navigator));
    navState.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('chat-1'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('chat-1'), findsOneWidget);

    // Trigger notification navigation to a different conversation (B = 2).
    convs.requestNavigateToConversationFromNotification(2);
    await tester.pumpAndSettle();

    // Chat A must be gone — pushAndRemoveUntil removed it.
    expect(find.text('chat-1'), findsNothing);
    // Chat B is now shown.
    expect(find.text('chat-2'), findsOneWidget);

    // Stack depth: root (main-shell) + ChatB = 2, not 3.
    int routeCount = 0;
    navState.popUntil((_) {
      routeCount++;
      return false;
    });
    expect(routeCount, 2);
  });

  testWidgets('notification nav to same active conv is a no-op', (tester) async {
    final convs = ConversationsProvider();
    convs.onConversationsList([_convJson(5)]);
    convs.setActiveConversation(5);

    await tester.pumpWidget(buildApp(convs));
    await tester.pumpAndSettle();

    convs.requestNavigateToConversationFromNotification(5);
    await tester.pumpAndSettle();

    // Already active — no push happened; main-shell still visible.
    expect(find.text('main-shell'), findsOneWidget);
    expect(find.text('chat-5'), findsNothing);
  });

  testWidgets(
      'stale conversation id (not in local list) stays on the list — no broken chat mount',
      (tester) async {
    final convs = ConversationsProvider();
    convs.onConversationsList([_convJson(1)]);

    await tester.pumpWidget(buildApp(convs));
    await tester.pumpAndSettle();

    // Notification for a deleted/unknown conversation (id 99).
    convs.requestNavigateToConversationFromNotification(99);
    await tester.pumpAndSettle();

    expect(find.text('chat-99'), findsNothing);
    expect(find.text('main-shell'), findsOneWidget);
    // Consumed — must not re-fire on later rebuilds.
    expect(convs.pendingNotificationConversationId, isNull);
  });

  testWidgets(
      'pending nav is retained until the first conversations snapshot, then fires',
      (tester) async {
    final convs = ConversationsProvider();

    await tester.pumpWidget(buildApp(convs));
    await tester.pumpAndSettle();

    // Cold start: tap arrives before the server snapshot — must NOT navigate
    // yet (an unverified id would mount an empty chat with dead send).
    convs.requestNavigateToConversationFromNotification(3);
    await tester.pumpAndSettle();
    expect(find.text('chat-3'), findsNothing);
    expect(convs.pendingNotificationConversationId, 3);

    // Snapshot arrives containing the conversation — nav fires now.
    convs.onConversationsList([_convJson(3)]);
    await tester.pumpAndSettle();
    expect(find.text('chat-3'), findsOneWidget);
  });
}
