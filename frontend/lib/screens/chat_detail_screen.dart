import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../theme/rpg_theme.dart';
import '../widgets/chat_message_bubble.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/message_date_separator.dart';
import '../widgets/avatar_circle.dart';

class ChatDetailScreen extends StatefulWidget {
  final int conversationId;
  final bool isEmbedded;

  const ChatDetailScreen({
    super.key,
    required this.conversationId,
    this.isEmbedded = false,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chat = context.read<ChatProvider>();
      if (chat.activeConversationId != widget.conversationId) {
        chat.openConversation(widget.conversationId);
      }
    });
  }

  @override
  void didUpdateWidget(ChatDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      context.read<ChatProvider>().openConversation(widget.conversationId);
    }
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

  String _getContactEmail() {
    final chat = context.read<ChatProvider>();
    final conv = chat.conversations.where((c) => c.id == widget.conversationId).firstOrNull;
    if (conv == null) return '';
    return chat.getOtherUserEmail(conv);
  }

  bool _isDifferentDay(DateTime a, DateTime b) {
    return a.year != b.year || a.month != b.month || a.day != b.day;
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final auth = context.watch<AuthProvider>();
    final messages = chat.messages;
    final contactEmail = _getContactEmail();

    _scrollToBottom();

    final body = Column(
      children: [
        Expanded(
          child: Container(
            color: RpgTheme.messagesAreaBg,
            child: messages.isEmpty
                ? Center(
                    child: Text(
                      'No messages yet',
                      style: RpgTheme.bodyFont(fontSize: 14, color: RpgTheme.mutedText),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final showDate = index == 0 ||
                          _isDifferentDay(
                            messages[index - 1].createdAt,
                            msg.createdAt,
                          );
                      return Column(
                        children: [
                          if (showDate) MessageDateSeparator(date: msg.createdAt),
                          ChatMessageBubble(
                            message: msg,
                            isMine: msg.senderId == auth.currentUser!.id,
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ),
        const ChatInputBar(),
      ],
    );

    if (widget.isEmbedded) {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: RpgTheme.boxBg,
              border: Border(bottom: BorderSide(color: RpgTheme.convItemBorder)),
            ),
            child: Row(
              children: [
                AvatarCircle(email: contactEmail, radius: 18),
                const SizedBox(width: 12),
                Text(
                  contactEmail,
                  style: RpgTheme.bodyFont(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            context.read<ChatProvider>().clearActiveConversation();
            Navigator.of(context).pop();
          },
        ),
        title: Row(
          children: [
            AvatarCircle(email: contactEmail, radius: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                contactEmail,
                style: RpgTheme.bodyFont(
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: body,
    );
  }
}
