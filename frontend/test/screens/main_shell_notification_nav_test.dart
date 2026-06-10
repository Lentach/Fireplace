import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Minimal widget replicating the notification-navigation branch from MainShell.build().
/// Tests the pushAndRemoveUntil behaviour without needing all 7 providers.
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
        if (convs.pendingNotificationConversationId != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final id = context
                .read<ConversationsProvider>()
                .consumePendingNotificationConversationId();
            if (id == null) return;
            final active =
                context.read<ConversationsProvider>().activeConversationId;
            if (active == id) return;
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

void main() {
  Widget _buildApp(ConversationsProvider convs) {
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

    await tester.pumpWidget(_buildApp(convs));
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
    convs.setActiveConversation(5);

    await tester.pumpWidget(_buildApp(convs));
    await tester.pumpAndSettle();

    convs.requestNavigateToConversationFromNotification(5);
    await tester.pumpAndSettle();

    // Already active — no push happened; main-shell still visible.
    expect(find.text('main-shell'), findsOneWidget);
    expect(find.text('chat-5'), findsNothing);
  });
}
