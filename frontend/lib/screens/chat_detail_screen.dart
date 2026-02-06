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
  bool _showScrollToBottomButton = false;
  int _newMessagesCount = 0;
  int _lastMessageCount = 0;
  static const double _scrollToBottomThreshold = 80;

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final atBottom = pos.pixels >= pos.maxScrollExtent - _scrollToBottomThreshold;
    if (_showScrollToBottomButton != !atBottom && mounted) {
      setState(() => _showScrollToBottomButton = !atBottom);
    }
  }

  void _onNewMessages(int currentCount, int added) {
    if (added <= 0) return;
    _lastMessageCount = currentCount;
    if (!_showScrollToBottomButton) {
      _scrollToBottom();
    } else {
      setState(() => _newMessagesCount += added);
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chat = context.read<ChatProvider>();
      if (chat.activeConversationId != widget.conversationId) {
        chat.openConversation(widget.conversationId);
      }
      _scrollToBottomOnce();
    });

    // Refresh every second to update countdown and remove expired messages
    _timerCountdownRefresh = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (!mounted) return;
        context.read<ChatProvider>().removeExpiredMessages();
        setState(() {});
      },
    );
  }

  @override
  void didUpdateWidget(ChatDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      _lastMessageCount = 0;
      _newMessagesCount = 0;
      context.read<ChatProvider>().openConversation(widget.conversationId);
      _scrollToBottomOnce();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _timerCountdownRefresh?.cancel();
    super.dispose();
  }

  void _scrollToBottomOnce() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    if (mounted) setState(() => _newMessagesCount = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
      if (mounted) setState(() => _lastMessageCount = context.read<ChatProvider>().messages.length);
    });
  }

  Widget _buildScrollToBottomButton() {
    return Positioned(
      bottom: 72,
      right: 16,
      child: Material(
        elevation: 2,
        borderRadius: BorderRadius.circular(24),
        color: Theme.of(context).colorScheme.surface,
        child: InkWell(
          onTap: _scrollToBottom,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.keyboard_arrow_down, size: 28),
                if (_newMessagesCount > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: const BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                      ),
                      constraints: const BoxConstraints(minWidth: 18),
                      child: Text(
                        _newMessagesCount > 99 ? '99+' : '$_newMessagesCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
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

    if (messages.isNotEmpty && messages.length != _lastMessageCount) {
      final added = messages.length - _lastMessageCount;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_lastMessageCount == 0) {
          _lastMessageCount = messages.length;
          return;
        }
        _onNewMessages(messages.length, added);
      });
    }

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
                Expanded(
                  child: Center(
                    child: Text(
                      contactName,
                      style: RpgTheme.bodyFont(
                        fontSize: 16,
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
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
                if (_showScrollToBottomButton) _buildScrollToBottomButton(),
              ],
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
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
          if (_showScrollToBottomButton) _buildScrollToBottomButton(),
        ],
      ),
    );
  }
}
