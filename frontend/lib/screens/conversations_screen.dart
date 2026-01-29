import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../theme/rpg_theme.dart';
import '../widgets/conversation_tile.dart';
import 'chat_detail_screen.dart';
import 'new_chat_screen.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'RPG CHAT',
          style: RpgTheme.pressStart2P(fontSize: 14, color: RpgTheme.gold),
        ),
        actions: [
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

    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 320,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: const BoxDecoration(
                    color: RpgTheme.boxBg,
                    border: Border(bottom: BorderSide(color: RpgTheme.convItemBorder)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'RPG CHAT',
                          style: RpgTheme.pressStart2P(fontSize: 12, color: RpgTheme.gold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chat_bubble_outline, color: RpgTheme.purple, size: 20),
                        onPressed: _startNewChat,
                        tooltip: 'New chat',
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout, color: RpgTheme.logoutRed, size: 20),
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
          Container(width: 1, color: RpgTheme.convItemBorder),
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
                        Icon(Icons.chat_bubble_outline, size: 64, color: RpgTheme.mutedText),
                        const SizedBox(height: 16),
                        Text(
                          'Select a conversation',
                          style: RpgTheme.bodyFont(fontSize: 16, color: RpgTheme.mutedText),
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

    if (conversations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 48, color: RpgTheme.mutedText),
              const SizedBox(height: 16),
              Text(
                'No conversations yet',
                style: RpgTheme.bodyFont(fontSize: 16, color: RpgTheme.mutedText),
              ),
              const SizedBox(height: 8),
              Text(
                'Start a new chat to begin',
                style: RpgTheme.bodyFont(fontSize: 13, color: RpgTheme.timeColor),
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
        final email = chat.getOtherUserEmail(conv);
        final lastMsg = chat.lastMessages[conv.id];
        return ConversationTile(
          email: email,
          lastMessage: lastMsg,
          isActive: conv.id == chat.activeConversationId,
          onTap: () => _openChat(conv.id),
        );
      },
    );
  }
}
