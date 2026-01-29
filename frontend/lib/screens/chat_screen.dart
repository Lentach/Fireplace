import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/rpg_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../widgets/rpg_box.dart';
import '../widgets/blinking_cursor.dart';
import '../widgets/sidebar.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_input_bar.dart';
import '../widgets/no_chat_selected.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      final chat = context.read<ChatProvider>();
      chat.connect(token: auth.token!, userId: auth.currentUser!.id);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _logout() {
    context.read<ChatProvider>().disconnect();
    context.read<AuthProvider>().logout();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final chat = context.watch<ChatProvider>();

    // Auto-scroll when messages change
    if (chat.activeConversationId != null) {
      _scrollToBottom();
    }

    return Scaffold(
      backgroundColor: RpgTheme.background,
      body: Center(
        child: RpgBox(
          width: 700,
          height: 520,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.only(bottom: 8),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: RpgTheme.tabBorder, width: 2),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          '\u2694\uFE0F ${auth.currentUser?.email ?? ''}',
                          style: RpgTheme.pressStart2P(
                            fontSize: 8,
                            color: RpgTheme.headerGreen,
                          ).copyWith(
                            shadows: [
                              const Shadow(
                                blurRadius: 6,
                                color: Color(0x4444FF44),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        const BlinkingCursor(),
                      ],
                    ),
                    GestureDetector(
                      onTap: _logout,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: RpgTheme.tabBg,
                          border: Border.all(color: RpgTheme.logoutRed, width: 2),
                        ),
                        child: Text(
                          '\u2716 LOGOUT',
                          style: RpgTheme.pressStart2P(
                            fontSize: 7,
                            color: RpgTheme.logoutRed,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Body
              Expanded(
                child: Row(
                  children: [
                    const Sidebar(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: chat.activeConversationId == null
                          ? const NoChatSelected()
                          : Column(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: RpgTheme.messagesAreaBg,
                                      border: Border.all(
                                        color: RpgTheme.convItemBorder,
                                        width: 2,
                                      ),
                                    ),
                                    child: ListView.separated(
                                      controller: _scrollController,
                                      itemCount: chat.messages.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 8),
                                      itemBuilder: (context, index) {
                                        final msg = chat.messages[index];
                                        return MessageBubble(
                                          message: msg,
                                          isMine: msg.senderId ==
                                              auth.currentUser!.id,
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const MessageInputBar(),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
