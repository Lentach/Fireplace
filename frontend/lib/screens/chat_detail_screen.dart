import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../theme/rpg_theme.dart';
import '../widgets/chat_message_bubble.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/message_date_separator.dart';
import '../models/user_model.dart';
import '../widgets/avatar_circle.dart';
import '../widgets/ping_effect_overlay.dart';

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
  Timer? _timerCountdownRefresh;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chat = context.read<ChatProvider>();
      if (chat.activeConversationId != widget.conversationId) {
        chat.openConversation(widget.conversationId);
      }
    });

    // Refresh every second to update countdown
    _timerCountdownRefresh = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (mounted) setState(() {});
      },
    );
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
    _timerCountdownRefresh?.cancel();
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

  String _getContactName() {
    final chat = context.read<ChatProvider>();
    final conv = chat.conversations.where((c) => c.id == widget.conversationId).firstOrNull;
    if (conv == null) return '';
    return chat.getOtherUserUsername(conv);
  }

  int _getOtherUserId() {
    final chat = context.read<ChatProvider>();
    final conv = chat.conversations.where((c) => c.id == widget.conversationId).firstOrNull;
    if (conv == null) return 0;
    return chat.getOtherUserId(conv);
  }

  UserModel? _getOtherUser() {
    final chat = context.read<ChatProvider>();
    final conv = chat.conversations.where((c) => c.id == widget.conversationId).firstOrNull;
    if (conv == null) return null;
    return chat.getOtherUser(conv);
  }

  void _unfriend() {
    final otherUserId = _getOtherUserId();
    final otherUsername = _getContactName();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Unfriend $otherUsername?'),
        content: const Text('This will delete your entire conversation history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<ChatProvider>().unfriend(otherUserId);
              if (!widget.isEmbedded && mounted) {
                Navigator.pop(context);
              }
            },
            child: const Text('Unfriend', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  bool _isDifferentDay(DateTime a, DateTime b) {
    return a.year != b.year || a.month != b.month || a.day != b.day;
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final auth = context.watch<AuthProvider>();
    final messages = chat.messages;
    final contactName = _getContactName();

    _scrollToBottom();

    final isDark = RpgTheme.isDark(context);
    final colorScheme = Theme.of(context).colorScheme;
    final messagesAreaBg =
        isDark ? RpgTheme.messagesAreaBg : RpgTheme.messagesAreaBgLight;
    final mutedColor =
        isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight;

    final body = Column(
      children: [
        Expanded(
          child: Container(
            color: messagesAreaBg,
            child: messages.isEmpty
                ? Center(
                    child: Text(
                      'No messages yet',
                      style: RpgTheme.bodyFont(
                        fontSize: 14,
                        color: mutedColor,
                      ),
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

    final otherUser = _getOtherUser();
    if (widget.isEmbedded) {
      final borderColor = isDark
          ? RpgTheme.convItemBorderDark
          : RpgTheme.convItemBorderLight;
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Row(
              children: [
                AvatarCircle(
                  email: contactName,
                  radius: 18,
                  profilePictureUrl: otherUser?.profilePictureUrl,
                ),
                const SizedBox(width: 12),
                Text(
                  contactName,
                  style: RpgTheme.bodyFont(
                    fontSize: 16,
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                body,

                // Ping effect overlay
                if (chat.showPingEffect)
                  Positioned.fill(
                    child: PingEffectOverlay(
                      onComplete: () {
                        chat.clearPingEffect();
                      },
                    ),
                  ),
              ],
            ),
          ),
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
        title: Text(
          contactName,
          style: RpgTheme.bodyFont(
            fontSize: 16,
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          // Avatar on the right
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: AvatarCircle(
              email: contactName,
              radius: 18,
              profilePictureUrl: otherUser?.profilePictureUrl,
            ),
          ),
          // Menu (three dots)
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'unfriend') {
                _unfriend();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'unfriend',
                child: Row(
                  children: [
                    Icon(Icons.person_remove, color: Colors.red),
                    const SizedBox(width: 8),
                    const Text('Unfriend'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          body,

          // Ping effect overlay
          if (chat.showPingEffect)
            Positioned.fill(
              child: PingEffectOverlay(
                onComplete: () {
                  chat.clearPingEffect();
                },
              ),
            ),
        ],
      ),
    );
  }
}
