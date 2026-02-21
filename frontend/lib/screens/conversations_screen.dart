import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_constants.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
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
      final chat = context.read<ChatProvider>();
      chat.connect(token: auth.token!, userId: auth.currentUser!.id);
    });
  }

  void _openChat(int conversationId) {
    final chat = context.read<ChatProvider>();
    chat.openConversation(conversationId);

    final width = MediaQuery.of(context).size.width;
    if (width < AppConstants.layoutBreakpointDesktop) {
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
    context.read<ChatProvider>().deleteConversationOnly(conversationId);
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
    final isDark = RpgTheme.isDark(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: isDark
                FireplaceColors.of(context).convItemBorder,
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
                'Conversations',
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
                    tooltip: 'Add / Invitations',
                  ),
                  Consumer<ChatProvider>(
                    builder: (context, chat, _) {
                      if (chat.pendingRequestsCount == 0) {
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
                            '${chat.pendingRequestsCount}',
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
    final chat = context.watch<ChatProvider>();
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
            child: chat.activeConversationId != null
                ? ChatDetailScreen(
                    conversationId: chat.activeConversationId!,
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
                          'Select a conversation',
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
    final chat = context.watch<ChatProvider>();
    final conversations = chat.sortedConversations;
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
                'No conversations yet',
                style: RpgTheme.bodyFont(fontSize: 16, color: mutedColor),
              ),
              const SizedBox(height: 8),
              Text(
                'Start a new chat to begin',
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
        final otherUser = chat.getOtherUser(conv);
        final displayName = chat.getOtherUserUsername(conv);
        final lastMsg = chat.lastMessages[conv.id];
        return ConversationTile(
          displayName: displayName,
          lastMessage: lastMsg,
          isActive: conv.id == chat.activeConversationId,
          unreadCount: chat.getUnreadCount(conv.id),
          onTap: () => _openChat(conv.id),
          onDelete: () => _deleteConversation(conv.id),
          otherUser: otherUser,
          isTyping: chat.isPartnerTyping(conv.id),
        );
      },
    );
  }
}
