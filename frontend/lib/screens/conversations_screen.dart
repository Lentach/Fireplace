import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../theme/rpg_theme.dart';
import '../widgets/conversation_tile.dart';
import 'chat_detail_screen.dart';
import 'new_chat_screen.dart';
import 'settings_screen.dart';
import 'friend_requests_screen.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

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

  void _logout() {
    context.read<ChatProvider>().disconnect();
    context.read<AuthProvider>().logout();
  }

  void _openChat(int conversationId) {
    final chat = context.read<ChatProvider>();
    chat.openConversation(conversationId);

    final width = MediaQuery.of(context).size.width;
    if (width < 600) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatDetailScreen(conversationId: conversationId),
        ),
      );
    }
  }

  void _startNewChat() async {
    final result = await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => const NewChatScreen()),
    );
    if (result != null && mounted) {
      _openChat(result);
    }
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void _openFriendRequests() async {
    final result = await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => const FriendRequestsScreen()),
    );
    if (result != null && mounted) {
      _openChat(result);
    }
  }

  void _deleteConversation(int conversationId) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        final mutedColor = RpgTheme.isDark(dialogContext)
            ? RpgTheme.mutedText
            : RpgTheme.textSecondaryLight;
        return AlertDialog(
          backgroundColor: colorScheme.surface,
          title: Text(
            'Delete Conversation?',
            style: RpgTheme.bodyFont(
              fontSize: 16,
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            'This will delete all messages. This action cannot be undone.',
            style: RpgTheme.bodyFont(
              fontSize: 14,
              color: colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Cancel',
                style: RpgTheme.bodyFont(fontSize: 14, color: mutedColor),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                context.read<ChatProvider>().deleteConversation(conversationId);
              },
              child: Text(
                'Delete',
                style: RpgTheme.bodyFont(
                  fontSize: 14,
                  color: RpgTheme.logoutRed,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 600;
        if (isDesktop) {
          return _buildDesktopLayout();
        }
        return _buildMobileLayout();
      },
    );
  }

  Widget _buildMobileLayout() {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'RPG CHAT',
          style: RpgTheme.pressStart2P(fontSize: 14, color: colorScheme.primary),
        ),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: Icon(Icons.person_add, color: colorScheme.primary),
                onPressed: _openFriendRequests,
                tooltip: 'Friend requests',
              ),
              Consumer<ChatProvider>(
                builder: (context, chat, _) {
                  if (chat.pendingRequestsCount == 0) {
                    return const SizedBox.shrink();
                  }
                  return Positioned(
                    right: 8,
                    top: 8,
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
          IconButton(
            icon: Icon(Icons.settings, color: colorScheme.primary),
            onPressed: _openSettings,
            tooltip: 'Settings',
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: RpgTheme.logoutRed),
            onPressed: _logout,
            tooltip: 'Logout',
          ),
        ],
      ),
      body: _buildConversationList(),
      floatingActionButton: FloatingActionButton(
        onPressed: _startNewChat,
        child: const Icon(Icons.chat_bubble_outline),
      ),
    );
  }

  Widget _buildDesktopLayout() {
    final chat = context.watch<ChatProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = RpgTheme.isDark(context);
    final borderColor =
        isDark ? RpgTheme.convItemBorder : RpgTheme.convItemBorderLight;

    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 320,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    border: Border(bottom: BorderSide(color: borderColor)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'RPG CHAT',
                          style: RpgTheme.pressStart2P(
                            fontSize: 12,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.chat_bubble_outline,
                          color: colorScheme.primary,
                          size: 20,
                        ),
                        onPressed: _startNewChat,
                        tooltip: 'New chat',
                      ),
                      Stack(
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.person_add,
                              color: colorScheme.primary,
                              size: 20,
                            ),
                            onPressed: _openFriendRequests,
                            tooltip: 'Friend requests',
                          ),
                          Consumer<ChatProvider>(
                            builder: (context, chat, _) {
                              if (chat.pendingRequestsCount == 0) {
                                return const SizedBox.shrink();
                              }
                              return Positioned(
                                right: 6,
                                top: 6,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '${chat.pendingRequestsCount}',
                                    style: RpgTheme.bodyFont(
                                      fontSize: 8,
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
                      IconButton(
                        icon: Icon(
                          Icons.settings,
                          color: colorScheme.primary,
                          size: 20,
                        ),
                        onPressed: _openSettings,
                        tooltip: 'Settings',
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.logout,
                          color: RpgTheme.logoutRed,
                          size: 20,
                        ),
                        onPressed: _logout,
                        tooltip: 'Logout',
                      ),
                    ],
                  ),
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
                              ? RpgTheme.mutedText
                              : RpgTheme.textSecondaryLight,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Select a conversation',
                          style: RpgTheme.bodyFont(
                            fontSize: 16,
                            color: isDark
                                ? RpgTheme.mutedText
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
    final conversations = chat.conversations;
    final isDark = RpgTheme.isDark(context);
    final mutedColor =
        isDark ? RpgTheme.mutedText : RpgTheme.textSecondaryLight;

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
                  color: isDark ? RpgTheme.timeColor : RpgTheme.textSecondaryLight,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      itemCount: conversations.length,
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final conv = conversations[index];
        final otherUser = chat.getOtherUser(conv);
        final displayName = chat.getOtherUserUsername(conv);
        final lastMsg = chat.lastMessages[conv.id];
        return ConversationTile(
          displayName: displayName,
          lastMessage: lastMsg,
          isActive: conv.id == chat.activeConversationId,
          onTap: () => _openChat(conv.id),
          onDelete: () => _deleteConversation(conv.id),
          otherUser: otherUser,
        );
      },
    );
  }
}
