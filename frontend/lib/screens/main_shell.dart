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
import '../utils/notification_nav_decision.dart';
import '../services/unread_badge_sync.dart';
import '../widgets/top_snackbar.dart';
import '../widgets/console_glyphs.dart';
import '../widgets/glass/glass_bottom_nav.dart';
import 'user_card_screen.dart';

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

  void _openMyProfile() {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    Navigator.of(context).push(
      instantOpaqueRoute(
        builder: (_) => UserCardScreen(
          data: UserCardVisualData.fromUser(
            user,
            isSelf: true,
            hasConversation: false,
          ),
        ),
      ),
    );
  }

  void _openAcceptedConversation(int conversationId) {
    if (!mounted) return;

    if (MediaQuery.of(context).size.width >=
        AppConstants.layoutBreakpointDesktop) {
      setState(() => _selectedIndex = 0);
      context.read<ConversationsProvider>().openConversation(conversationId);
      return;
    }

    Navigator.of(context).push(
      instantOpaqueRoute(
        builder: (_) => ChatDetailScreen(conversationId: conversationId),
      ),
    );
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final accepted = context
              .read<FriendsProvider>()
              .consumePendingFriendAccepted();
          if (accepted == null) return;

          final l10n = AppLocalizations.of(context);
          final message = l10n.friendAcceptedYourRequest(accepted.name);
          if (accepted.chatReady && accepted.conversationId != null) {
            showTopSnackBar(
              context,
              message,
              onTap: () => _openAcceptedConversation(accepted.conversationId!),
              actionLabel: l10n.invitationOpenChat,
            );
          } else {
            showTopSnackBar(context, message);
          }
        });
        // Notification deep-link — Option A: route through the SAME open path
        // the conversations list uses, and only for conversations that exist
        // locally. Gated on the first server snapshot: consuming earlier would
        // either race an empty list (cold start) or mount a chat for a stale
        // id from an old notification (deleted conversation) — such a screen
        // renders empty and sendMessage finds no conversation, so typed text
        // vanished. Stale id ⇒ land on the conversations tab and stop.
        if (shouldConsumeNotificationNav(
          pendingConversationId: convs.pendingNotificationConversationId,
          hasLoadedConversationsOnce: convs.hasLoadedConversationsOnce,
        )) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final provider = context.read<ConversationsProvider>();
            final id = provider.consumePendingNotificationConversationId();
            final decision = decideNotificationNav(
              consumedId: id,
              conversationExistsLocally:
                  id != null && provider.getConversationById(id) != null,
              isDesktop:
                  MediaQuery.of(context).size.width >=
                  AppConstants.layoutBreakpointDesktop,
              isAlreadyActive: provider.activeConversationId == id,
            );
            if (decision.switchToConversationsTab) {
              setState(() => _selectedIndex = 0);
            }
            if (decision.action == NotificationNavAction.setActiveDesktop) {
              provider.setActiveConversation(id!);
            } else if (decision.action ==
                NotificationNavAction.pushMobileChat) {
              Navigator.of(context).pushAndRemoveUntil(
                instantOpaqueRoute<void>(
                  builder: (_) => ChatDetailScreen(conversationId: id!),
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
    final bottomNavigation = GlassBottomNav(
      currentIndex: _selectedIndex,
      onTap: (index) => setState(() => _selectedIndex = index),
      destinations: [
        GlassNavDestination(
          icon: const ConsoleGlyphIcon(ConsoleGlyph.chats),
          label: AppLocalizations.of(context).chat,
        ),
        GlassNavDestination(
          icon: const ConsoleGlyphIcon(ConsoleGlyph.contacts),
          label: AppLocalizations.of(context).contacts,
        ),
        GlassNavDestination(
          icon: const ConsoleGlyphIcon(ConsoleGlyph.settings),
          label: AppLocalizations.of(context).settings,
        ),
      ],
    );

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          ConversationsScreen(onAvatarTap: _openMyProfile),
          const ContactsScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: SafeArea(top: false, child: bottomNavigation),
    );
  }
}
