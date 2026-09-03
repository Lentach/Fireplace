import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_constants.dart';
import '../config/app_config.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/conversations_provider.dart';
import '../providers/encryption_provider.dart';
import '../providers/friends_provider.dart';
import '../providers/messaging_provider.dart';
import '../providers/passcode_provider.dart';
import '../theme/rpg_theme.dart';
import '../widgets/avatar_circle.dart';
import '../widgets/chat_honeycomb_picker.dart';
import '../widgets/hex_avatar.dart';
import '../widgets/conversation_tile.dart';
import '../widgets/conversation_list_skeleton.dart';
import '../widgets/main_tab_screen_header.dart';
import '../utils/instant_opaque_route.dart';
import 'chat_detail_screen.dart';
import 'passcode_lock_screen.dart';
import 'invitations_screen.dart';

class ConversationsScreen extends StatefulWidget {
  final VoidCallback? onAvatarTap;

  const ConversationsScreen({super.key, this.onAvatarTap});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  Timer? _listCountdownTimer;

  @override
  void initState() {
    super.initState();
    final messaging = context.read<MessagingProvider>();
    _listCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (messaging.isRecordingVoice) return;
      messaging.removeExpiredMessages();
      context.read<ConversationsProvider>().pruneExpiredLastMessages();
      messaging.countdownTickNotifier.value++;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthProvider>();
      final conn = context.read<ConnectionProvider>();
      final enc = context.read<EncryptionProvider>();
      final friends = context.read<FriendsProvider>();
      final convs = context.read<ConversationsProvider>();
      final msg = context.read<MessagingProvider>();

      // Wire all sub-providers into ConnectionProvider
      conn.setProviders(
        encryption: enc,
        friends: friends,
        conversations: convs,
        messaging: msg,
      );

      // Wire MessagingProvider dependencies
      msg.setEncryptionProvider(enc);
      msg.setConversationsProvider(convs);

      // Start connection via ConnectionProvider (owns socket lifecycle)
      await auth.ensureSessionReady();
      if (!mounted) return;
      conn.connect(auth.currentUser!.id, auth.token!, AppConfig.baseUrl);
    });
  }

  @override
  void dispose() {
    _listCountdownTimer?.cancel();
    super.dispose();
  }

  void _openChat(int conversationId) {
    final convs = context.read<ConversationsProvider>();
    final width = MediaQuery.of(context).size.width;
    if (width >= AppConstants.layoutBreakpointDesktop) {
      // Desktop: only set active so ChatDetailScreen shows; it will call openConversation (avoids double getMessages)
      convs.setActiveConversation(conversationId);
    } else {
      // Mobile: only navigate; ChatDetailScreen initState will call openConversation (avoids double getMessages)
      Navigator.of(context).push(
        instantOpaqueRoute(
          builder: (_) => ChatDetailScreen(conversationId: conversationId),
        ),
      );
    }
  }

  Future<void> _showNewChatPicker() async {
    final friends = context.read<FriendsProvider>();
    final choice = await showChatHoneycombPicker(
      context,
      friends: friends.friends,
      inviters: [for (final request in friends.friendRequests) request.sender],
    );
    if (choice == null || !mounted) return;

    switch (choice) {
      case ChatPickerReviewInvitations() || ChatPickerInviteNew():
        // Reviewing inbound invitations and inviting someone new are the
        // same destination: InvitationsScreen owns both halves of the
        // relationship layer (and the accept/decline retry machinery).
        await _openInvitations();
      case ChatPickerFriend(:final friend):
        _startChatWith(friend.id);
    }
  }

  /// The "+" badge counts inbound invitations, so the sheet behind it has to
  /// reach them. Accepting stays in `InvitationsScreen`, which owns the
  /// failure and retry machinery; this only routes there and back.
  Future<void> _openInvitations() async {
    final peerUserId = await Navigator.of(
      context,
    ).push<int>(MaterialPageRoute(builder: (_) => const InvitationsScreen()));
    if (peerUserId == null || !mounted) return;
    _startChatWith(peerUserId);
  }

  void _startChatWith(int userId) {
    final convs = context.read<ConversationsProvider>();
    final existingConversation = convs.conversations
        .where((conversation) => convs.getOtherUser(conversation)?.id == userId)
        .firstOrNull;
    if (existingConversation != null) {
      _openChat(existingConversation.id);
      return;
    }

    // The backend creates the conversation and emits `openConversation`; the
    // build path below consumes that pending ID through this screen's normal
    // open-chat path.
    convs.startConversation(userId);
  }

  void _deleteConversation(int conversationId) {
    // Dialog is handled by Dismissible widget in ConversationTile
    // This method is called after user confirms in swipe-to-delete dialog
    final msg = context.read<MessagingProvider>();
    final convs = context.read<ConversationsProvider>();
    // Clear message state in sync with optimistic list removal (see deleteConversation).
    msg.onConversationDeleted(conversationId);
    convs.deleteConversation(conversationId);
  }

  @override
  Widget build(BuildContext context) {
    final convs = context.watch<ConversationsProvider>();
    if (convs.pendingOpenConversationId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final conversationId = context
            .read<ConversationsProvider>()
            .consumePendingOpen();
        if (conversationId != null && mounted) {
          _openChat(conversationId);
        }
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop =
            constraints.maxWidth >= AppConstants.layoutBreakpointDesktop;
        if (isDesktop) {
          return _buildDesktopLayout();
        }
        return _buildMobileLayout();
      },
    );
  }

  Widget _buildMobileLayout() {
    // Floating glass chrome: the list runs full-bleed behind the header
    // capsules (and behind the bottom nav via MainShell's extendBody);
    // clearance is applied as list padding, not layout slots.
    return Stack(
      children: [
        Positioned.fill(child: _buildConversationList(floatingChrome: true)),
        Positioned(top: 0, left: 0, right: 0, child: _buildCustomHeader()),
      ],
    );
  }

  Widget _buildCustomHeader() {
    final auth = context.watch<AuthProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final user = auth.currentUser;
    final l10n = AppLocalizations.of(context);
    return MainTabScreenHeader(
      title: l10n.chat,
      leading: Semantics(
        button: true,
        label: l10n.avatarOpenProfileSemantics,
        child: GestureDetector(
          onTap: widget.onAvatarTap,
          child: AvatarCircle(
            displayName: user?.username ?? '',
            radius: 22,
            profilePictureUrl: user?.profilePictureUrl,
          ),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Zangi parity (owner ask): the padlock sits immediately left of
          // `+`, lower emphasis than it. Enabled → lock the app right now;
          // not configured → open the setup screen, so the Chats screen is a
          // door to the feature and not just a switch for it.
          Consumer<PasscodeProvider>(
            builder: (context, passcode, _) => IconButton(
              key: const Key('conversations-passcode-button'),
              icon: Icon(
                passcode.isEnabled ? Icons.lock_outline : Icons.lock_open,
                color: colorScheme.onSurface,
                size: 22,
              ),
              tooltip: passcode.isEnabled
                  ? l10n.passcodeLockNowTooltip
                  : l10n.passcodeSetUpTooltip,
              onPressed: () {
                if (passcode.isEnabled) {
                  passcode.lockNow();
                  return;
                }
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PasscodeLockScreen(),
                  ),
                );
              },
            ),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                key: const Key('conversations-new-chat-button'),
                icon: Icon(
                  Icons.add_circle_outline,
                  color: colorScheme.primary,
                  size: 28,
                ),
                onPressed: _showNewChatPicker,
                tooltip: l10n.chatPickerOpenTooltip,
              ),
              Consumer<FriendsProvider>(
                builder: (context, friends, _) {
                  if (friends.pendingRequestsCount == 0) {
                    return const SizedBox.shrink();
                  }
                  return Positioned(
                    right: 2,
                    top: 2,
                    // Pointy-top hex like every other badge in the app (owner
                    // ruling 2026-08-03: no circles for counts).
                    child: HexCountBadge(
                      label: '${friends.pendingRequestsCount}',
                      size: 18,
                      background: colorScheme.error,
                      textStyle: RpgTheme.bodyFont(
                        fontSize: 10,
                        color: colorScheme.onError,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout() {
    final convs = context.watch<ConversationsProvider>();
    final borderColor = FireplaceColors.of(context).convItemBorder;

    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 320,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildCustomHeader(),
                Expanded(child: _buildConversationList()),
              ],
            ),
          ),
          Container(width: 1, color: borderColor),
          Expanded(
            child: convs.activeConversationId != null
                ? ChatDetailScreen(
                    conversationId: convs.activeConversationId!,
                    isEmbedded: true,
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 64,
                          color: FireplaceColors.of(context).mutedText,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          AppLocalizations.of(context).selectAConversation,
                          style: RpgTheme.bodyFont(
                            fontSize: 16,
                            color: FireplaceColors.of(context).mutedText,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationList({bool floatingChrome = false}) {
    final convs = context.watch<ConversationsProvider>();
    final conversations = convs.sortedConversations;
    final isDark = RpgTheme.isDark(context);
    final mutedColor = FireplaceColors.of(context).mutedText;

    final media = MediaQuery.paddingOf(context);
    final listPadding = floatingChrome
        ? EdgeInsets.fromLTRB(
            8,
            media.top + MainTabScreenHeader.clearance,
            8,
            media.bottom + 8,
          )
        : EdgeInsets.fromLTRB(8, 8, 8, media.bottom + 8);

    // Show the loading skeleton only while the first fetch is plausibly in
    // flight; on a known connection error fall through to the empty state so it
    // never shimmers forever.
    if (!convs.hasLoadedConversationsOnce &&
        context.watch<ConnectionProvider>().errorMessage == null) {
      return ConversationListSkeleton(padding: listPadding);
    }

    if (conversations.isEmpty) {
      return Padding(
        padding: listPadding,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.forum_outlined, size: 48, color: mutedColor),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context).noConversationsYet,
                  style: RpgTheme.bodyFont(fontSize: 16, color: mutedColor),
                ),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context).startNewChatToBegin,
                  style: RpgTheme.bodyFont(
                    fontSize: 13,
                    color: isDark
                        ? RpgTheme.timeColorDark
                        : RpgTheme.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Rows carry their own spacing and rounded surface now (live rows are
    // tinted, cold rows shrink); hairline dividers fought that hierarchy.
    return ListView.builder(
      padding: listPadding,
      itemCount: conversations.length,
      itemBuilder: (context, index) {
        final conv = conversations[index];
        final otherUser = convs.getOtherUser(conv);
        final displayName = convs.getOtherUserUsername(conv);
        final lastMsg = convs.lastMessages[conv.id];
        return Selector<MessagingProvider, bool>(
          selector: (_, messaging) => messaging.isPartnerTyping(conv.id),
          builder: (context, isTyping, _) {
            return ConversationTile(
              key: ValueKey<int>(conv.id),
              conversationId: conv.id,
              displayName: displayName,
              lastMessage: lastMsg,
              isActive: conv.id == convs.activeConversationId,
              unreadCount: convs.getUnreadCount(conv.id),
              isMuted: conv.isNotificationMuted,
              onTap: () => _openChat(conv.id),
              onDelete: () => _deleteConversation(conv.id),
              otherUser: otherUser,
              isTyping: isTyping,
            );
          },
        );
      },
    );
  }
}
