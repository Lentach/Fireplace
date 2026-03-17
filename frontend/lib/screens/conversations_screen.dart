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
import '../theme/rpg_theme.dart';
import '../widgets/avatar_circle.dart';
import '../widgets/conversation_tile.dart';
import 'add_or_invitations_screen.dart';
import 'chat_detail_screen.dart';

class ConversationsScreen extends StatefulWidget {
  final VoidCallback? onAvatarTap;

  const ConversationsScreen({super.key, this.onAvatarTap});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
      conn.connect(auth.currentUser!.id, auth.token!, AppConfig.baseUrl);
    });
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
        MaterialPageRoute(
          builder: (_) => ChatDetailScreen(conversationId: conversationId),
        ),
      );
    }
  }

  void _startNewChat() async {
    final result = await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => const AddOrInvitationsScreen()),
    );
    if (result != null && mounted) {
      _openChat(result);
    }
  }

  void _deleteConversation(int conversationId) {
    // Dialog is handled by Dismissible widget in ConversationTile
    // This method is called after user confirms in swipe-to-delete dialog
    context.read<ConversationsProvider>().deleteConversation(conversationId);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= AppConstants.layoutBreakpointDesktop;
        if (isDesktop) {
          return _buildDesktopLayout();
        }
        return _buildMobileLayout();
      },
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        _buildCustomHeader(),
        Expanded(child: _buildConversationList()),
      ],
    );
  }

  Widget _buildCustomHeader() {
    final auth = context.watch<AuthProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final user = auth.currentUser;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: FireplaceColors.of(context).convItemBorder,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Centered title (always in the middle of the header)
            Center(
              child: Text(
                AppLocalizations.of(context).chat,
                style: RpgTheme.pressStart2P(
                  fontSize: 12,
                  color: colorScheme.primary,
                ),
              ),
            ),
            // Left: avatar (tap to go to Settings)
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: widget.onAvatarTap,
                child: AvatarCircle(
                  displayName: user?.username ?? '',
                  radius: 22,
                  profilePictureUrl: user?.profilePictureUrl,
                ),
              ),
            ),
            // Right: plus in circle with badge (badge only on plus, not on avatar)
            Align(
              alignment: Alignment.centerRight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.add_circle_outline,
                      color: colorScheme.primary,
                      size: 28,
                    ),
                    onPressed: _startNewChat,
                    tooltip: AppLocalizations.of(context).addInvitations,
                  ),
                  Consumer<FriendsProvider>(
                    builder: (context, friends, _) {
                      if (friends.pendingRequestsCount == 0) {
                        return const SizedBox.shrink();
                      }
                      return Positioned(
                        right: 4,
                        top: 4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${friends.pendingRequestsCount}',
                            style: RpgTheme.bodyFont(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopLayout() {
    final convs = context.watch<ConversationsProvider>();
    final isDark = RpgTheme.isDark(context);
    final borderColor =
        FireplaceColors.of(context).convItemBorder;

    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 320,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(bottom: BorderSide(color: borderColor)),
                  ),
                  child: _buildCustomHeader(),
                ),
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
                          color: isDark
                              ? RpgTheme.mutedDark
                              : RpgTheme.textSecondaryLight,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          AppLocalizations.of(context).selectAConversation,
                          style: RpgTheme.bodyFont(
                            fontSize: 16,
                            color: isDark
                                ? RpgTheme.mutedDark
                                : RpgTheme.textSecondaryLight,
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

  Widget _buildConversationList() {
    final convs = context.watch<ConversationsProvider>();
    final conversations = convs.sortedConversations;
    final isDark = RpgTheme.isDark(context);
    final mutedColor =
        isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight;

    if (conversations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
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
                  color: isDark ? RpgTheme.timeColorDark : RpgTheme.textSecondaryLight,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final borderColor =
        FireplaceColors.of(context).convItemBorder;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      itemCount: conversations.length,
      separatorBuilder: (_, index) => Divider(
        height: 1,
        color: borderColor,
      ),
      itemBuilder: (context, index) {
        final conv = conversations[index];
        final otherUser = convs.getOtherUser(conv);
        final displayName = convs.getOtherUserUsername(conv);
        final lastMsg = convs.lastMessages[conv.id];
        final msg = context.watch<MessagingProvider>();
        return ConversationTile(
          displayName: displayName,
          lastMessage: lastMsg,
          isActive: conv.id == convs.activeConversationId,
          unreadCount: convs.getUnreadCount(conv.id),
          onTap: () => _openChat(conv.id),
          onDelete: () => _deleteConversation(conv.id),
          otherUser: otherUser,
          isTyping: msg.isPartnerTyping(conv.id),
        );
      },
    );
  }
}
