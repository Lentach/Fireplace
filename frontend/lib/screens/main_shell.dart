import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'contacts_screen.dart';
import 'conversations_screen.dart';
import 'settings_screen.dart';
import '../l10n/app_localizations.dart';
import '../constants/app_constants.dart';
import '../providers/auth_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/conversations_provider.dart';
import '../providers/friends_provider.dart';
import 'chat_detail_screen.dart';
import '../utils/pending_deep_link_stub.dart'
    if (dart.library.html) '../utils/pending_deep_link_web.dart';
import '../utils/e2e_diag_log.dart';
import '../utils/tab_visibility.dart';
import '../utils/instant_opaque_route.dart';
import '../services/unread_badge_sync.dart';
import '../widgets/top_snackbar.dart';

/// Shell after login: bottom nav with Conversations, Contacts, Settings.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  StreamSubscription<dynamic>? _tabVisibilitySub;
  UnreadBadgeSync? _unreadBadgeSync;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      final conn = context.read<ConnectionProvider>();
      auth.setOnAccessTokenChanged(conn.applyRefreshedAccessToken);
    });
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _unreadBadgeSync = UnreadBadgeSync(
          context.read<ConversationsProvider>(),
        );
      });
    }
    WidgetsBinding.instance.addObserver(this);
    if (kIsWeb) {
      _tabVisibilitySub = registerTabVisibilityListener((visible) {
        if (!mounted) return;
        E2eDiagLog.add('TAB_VIS', {'visible': visible});
        final auth = context.read<AuthProvider>();
        if (!visible) {
          if (auth.currentUser != null && auth.token != null) {
            context.read<ConversationsProvider>().setClientVisible(false);
          }
          return;
        }
        unawaited(() async {
          await auth.ensureSessionReady();
          if (!mounted) return;
          if (!auth.isLoggedIn) return;
          context.read<ConversationsProvider>().setClientVisible(true);
          context.read<ConnectionProvider>().ensureReconnectIfNeeded();
          // iOS PWA: a notification tap on a suspended WebView loses the SW's
          // click postMessage — the SW also persisted the target conversation
          // to IndexedDB, so drain it now that the tab is visible again.
          final pendingConvId = await consumePendingNotificationDeepLink();
          if (pendingConvId != null && mounted) {
            context
                .read<ConversationsProvider>()
                .requestNavigateToConversationFromNotification(pendingConvId);
          }
        }());
      });
    }
  }

  @override
  void dispose() {
    final badge = _unreadBadgeSync;
    _unreadBadgeSync = null;
    if (badge != null) {
      unawaited(badge.dispose());
    }
    _tabVisibilitySub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final auth = context.read<AuthProvider>();
    E2eDiagLog.add('LIFECYCLE', {
      'state': state.name,
      'loggedIn': auth.currentUser != null,
    });
    if (auth.currentUser == null || auth.token == null) return;

    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(() async {
          await auth.ensureSessionReady();
          if (!mounted) return;
          context.read<ConnectionProvider>().ensureReconnectIfNeeded();
          context.read<ConversationsProvider>().setClientVisible(true);
        }());
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
        // Treat inactive as background for push: iOS/Android often enter inactive
        // (app switcher, home gesture) before paused; leaving it true kept
        // pushClientState.clientVisible true so the server skipped pushes while
        // the user was no longer looking at the chat.
        context.read<ConversationsProvider>().setClientVisible(false);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Consumer2<FriendsProvider, ConversationsProvider>(
      builder: (context, friends, convs, _) {
        if (friends.pendingFriendAcceptedByName != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final name = context
                .read<FriendsProvider>()
                .consumePendingFriendAccepted();
            if (name != null && context.mounted) {
              showTopSnackBar(
                context,
                AppLocalizations.of(context).friendAcceptedYourRequest(name),
                backgroundColor: Colors.green,
              );
            }
          });
        }
        // Notification deep-link — Option A: route through the SAME open path
        // the conversations list uses, and only for conversations that exist
        // locally. Gated on the first server snapshot: consuming earlier would
        // either race an empty list (cold start) or mount a chat for a stale
        // id from an old notification (deleted conversation) — such a screen
        // renders empty and sendMessage finds no conversation, so typed text
        // vanished. Stale id ⇒ land on the conversations tab and stop.
        if (convs.pendingNotificationConversationId != null &&
            convs.hasLoadedConversationsOnce) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final provider = context.read<ConversationsProvider>();
            final id = provider.consumePendingNotificationConversationId();
            if (id == null) return;
            setState(() => _selectedIndex = 0);
            if (provider.getConversationById(id) == null) return;
            final width = MediaQuery.of(context).size.width;
            if (width >= AppConstants.layoutBreakpointDesktop) {
              provider.setActiveConversation(id);
            } else {
              if (provider.activeConversationId == id) return;
              Navigator.of(context).pushAndRemoveUntil(
                instantOpaqueRoute<void>(
                  builder: (_) => ChatDetailScreen(conversationId: id),
                ),
                (route) => route.isFirst,
              );
            }
          });
        }
        return _buildScaffold(context, theme, colorScheme);
      },
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final isDesktop =
        MediaQuery.sizeOf(context).width >=
        AppConstants.layoutBreakpointDesktop;
    final bottomNavigation = BottomNavigationBar(
      backgroundColor: theme.colorScheme.surface,
      currentIndex: _selectedIndex,
      onTap: (index) => setState(() => _selectedIndex = index),
      items: [
        BottomNavigationBarItem(
          icon: Icon(Icons.chat_bubble_outline, size: 24),
          activeIcon: _FilledChatBubbleWithLines(
            iconColor: colorScheme.primary,
            lineColor: colorScheme.onPrimary,
          ),
          label: AppLocalizations.of(context).chat,
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.people_outline),
          activeIcon: Icon(Icons.people),
          label: AppLocalizations.of(context).contacts,
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings_outlined),
          label: AppLocalizations.of(context).settings,
        ),
      ],
    );

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          ConversationsScreen(
            onAvatarTap: () => setState(() => _selectedIndex = 2),
          ),
          const ContactsScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: isDesktop
            ? EdgeInsets.zero
            : const EdgeInsets.only(bottom: 10),
        child: bottomNavigation,
      ),
    );
  }
}

/// Filled chat bubble icon with three horizontal lines inside (Apple-like minimalist style).
class _FilledChatBubbleWithLines extends StatelessWidget {
  final Color iconColor;
  final Color lineColor;

  const _FilledChatBubbleWithLines({
    required this.iconColor,
    required this.lineColor,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(24, 24),
      painter: _ChatBubblePainter(bubbleColor: iconColor, lineColor: lineColor),
    );
  }
}

/// Custom painter for clean Apple-style chat bubble with 3 lines.
class _ChatBubblePainter extends CustomPainter {
  final Color bubbleColor;
  final Color lineColor;

  _ChatBubblePainter({required this.bubbleColor, required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = bubbleColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Draw rounded rectangle bubble (main body)
    final bubbleRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(2, 3, size.width - 4, size.height - 8),
      const Radius.circular(11),
    );
    canvas.drawRRect(bubbleRect, paint);

    // Draw tail (small triangle at bottom left)
    final tailPath = Path()
      ..moveTo(6, size.height - 5)
      ..lineTo(3, size.height - 2)
      ..lineTo(8, size.height - 5)
      ..close();
    canvas.drawPath(tailPath, paint);

    // Draw three horizontal lines inside (white/contrast color)
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    const lineWidth = 10.0;
    final centerX = size.width / 2;
    final startY = 9.0;
    const lineSpacing = 3.0;

    // Line 1
    canvas.drawLine(
      Offset(centerX - lineWidth / 2, startY),
      Offset(centerX + lineWidth / 2, startY),
      linePaint,
    );

    // Line 2
    canvas.drawLine(
      Offset(centerX - lineWidth / 2, startY + lineSpacing),
      Offset(centerX + lineWidth / 2, startY + lineSpacing),
      linePaint,
    );

    // Line 3
    canvas.drawLine(
      Offset(centerX - lineWidth / 2, startY + lineSpacing * 2),
      Offset(centerX + lineWidth / 2, startY + lineSpacing * 2),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(_ChatBubblePainter oldDelegate) {
    return oldDelegate.bubbleColor != bubbleColor ||
        oldDelegate.lineColor != lineColor;
  }
}
