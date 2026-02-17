import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../theme/rpg_theme.dart';
import '../widgets/chat_message_bubble.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/message_date_separator.dart';
import '../models/conversation_model.dart';
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
  double _lastKeyboardHeight = 0;
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
    // Always scroll to bottom for new messages (especially after sending)
    _scrollToBottom();
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Always reload messages from server when entering/re-entering chat
      // to ensure timed messages reflect their current state
      context.read<ChatProvider>().openConversation(widget.conversationId);
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<ChatProvider>().openConversation(widget.conversationId);
      });
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
    // Delay scroll to give time for message to render and avoid stealing keyboard focus
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      if (mounted) setState(() => _lastMessageCount = context.read<ChatProvider>().messages.length);
    });
  }

  Widget _buildScrollToBottomButton() {
    return Positioned(
      bottom: 140,
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

  ConversationModel? _getActiveConversation() {
    return context.read<ChatProvider>().getConversationById(widget.conversationId);
  }

  String _getContactName() {
    final conv = _getActiveConversation();
    return conv != null
        ? context.read<ChatProvider>().getOtherUserUsername(conv)
        : '';
  }

  UserModel? _getOtherUser() {
    final conv = _getActiveConversation();
    return conv != null ? context.read<ChatProvider>().getOtherUser(conv) : null;
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
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    if (messages.isNotEmpty && messages.length != _lastMessageCount) {
      final added = messages.length - _lastMessageCount;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Always scroll to bottom when message count changes (including initial load)
        // so the user sees the newest message when entering the chat.
        _onNewMessages(messages.length, added);
      });
    }

    // Auto-scroll when keyboard opens to keep newest message visible
    if (keyboardHeight > 0 && _lastKeyboardHeight == 0 && messages.isNotEmpty) {
      // Keyboard just opened - scroll to bottom after layout settles
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Wait for keyboard animation to finish
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!mounted || !_scrollController.hasClients) return;
          final maxExtent = _scrollController.position.maxScrollExtent;
          if (maxExtent > 0) {
            _scrollController.animateTo(
              maxExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      });
    }
    _lastKeyboardHeight = keyboardHeight;

    final isDark = RpgTheme.isDark(context);
    final colorScheme = Theme.of(context).colorScheme;
    final messagesAreaBg =
        isDark ? RpgTheme.messagesAreaBg : RpgTheme.messagesAreaBgLight;
    final mutedColor =
        isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight;

    final body = SafeArea(
      child: Column(
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
                      padding: const EdgeInsets.only(
                        left: 12,
                        right: 12,
                        top: 8,
                        bottom: 8,
                      ),
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
      ),
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
      resizeToAvoidBottomInset: true,
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
