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
import '../widgets/top_snackbar.dart';

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
  Timer? _showFullHandleTimer;
  bool _showScrollToBottomButton = false;
  bool _showingFullHandle = false;
  int _newMessagesCount = 0;
  int _lastMessageCount = 0;
  int _lastLinkPreviewCount = 0;
  double _lastKeyboardHeight = 0;
  /// When true, ListView uses large cacheExtent so all items are built and scroll-to-bottom lands at real end.
  bool _expandCacheForScroll = false;
  static const double _scrollToBottomThreshold = 80;
  static const double _largeCacheExtent = 10000;

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
    final chat = context.read<ChatProvider>();
    _lastLinkPreviewCount = chat.messages.where((m) => m.linkPreviewUrl != null).length;
    // When opening conversation, expand cache so ListView builds all items and maxScrollExtent is correct.
    final isInitialLoad = added == currentCount && currentCount > 0;
    if (isInitialLoad) {
      setState(() => _expandCacheForScroll = true);
      // Defer scroll until after the rebuild with expanded cache has been laid out.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _scrollToBottom();
        });
      });
    } else {
      _scrollToBottom();
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Always reload messages from server when entering/re-entering chat
      // to ensure timed messages reflect their current state
      context.read<ChatProvider>().openConversation(widget.conversationId);
    });

    // Refresh every second: remove expired and tick countdown. No setState here -
    // countdownTickNotifier triggers only bubble rebuilds via ValueListenableBuilder,
    // avoiding full-screen rebuild that blocked the recording timer.
    _timerCountdownRefresh = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (!mounted) return;
        final chat = context.read<ChatProvider>();
        if (chat.isRecordingVoice) return; // Skip during recording to avoid starving recording timer
        chat.removeExpiredMessages();
        chat.countdownTickNotifier.value++;
      },
    );
  }

  @override
  void didUpdateWidget(ChatDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      _showFullHandleTimer?.cancel();
      _showingFullHandle = false;
      _lastMessageCount = 0;
      _lastLinkPreviewCount = 0;
      _newMessagesCount = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<ChatProvider>().openConversation(widget.conversationId);
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _timerCountdownRefresh?.cancel();
    _showFullHandleTimer?.cancel();
    super.dispose();
  }

  void _onAvatarTap() {
    _showFullHandleTimer?.cancel();
    if (!mounted) return;
    setState(() => _showingFullHandle = true);
    _showFullHandleTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showingFullHandle = false);
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
      ).then((_) {
        if (mounted) {
          setState(() {
            _lastMessageCount = context.read<ChatProvider>().messages.length;
            _expandCacheForScroll = false;
          });
        }
      });
    });
  }

  void _onScrollToBottomButtonTap() {
    setState(() => _expandCacheForScroll = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToBottom();
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
          onTap: _onScrollToBottomButtonTap,
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

  /// statusText: e.g. "typing..." or "Recording voice..."
  Widget _buildHeaderTitle(
    BuildContext context,
    String contactName,
    UserModel? otherUser,
    String? statusText,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = Theme.of(context).colorScheme.primary;
    final baseStyle = RpgTheme.bodyFont(
      fontSize: 16,
      color: colorScheme.onSurface,
      fontWeight: FontWeight.w600,
    );
    final nameWidget = AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.25, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
              reverseCurve: Curves.easeIn,
            )),
            child: child,
          ),
        );
      },
      child: _showingFullHandle && otherUser != null
          ? Text.rich(
              key: const ValueKey<bool>(true),
              TextSpan(
                style: baseStyle,
                children: [
                  TextSpan(text: otherUser.username),
                  TextSpan(
                    text: '#${otherUser.tag}',
                    style: RpgTheme.bodyFont(
                      fontSize: 16,
                      color: accentColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              overflow: TextOverflow.ellipsis,
            )
          : Text(
              key: const ValueKey<bool>(false),
              contactName,
              style: baseStyle,
              overflow: TextOverflow.ellipsis,
            ),
    );
    if (statusText == null || statusText.isEmpty) return nameWidget;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        nameWidget,
        Text(
          statusText,
          style: RpgTheme.bodyFont(
            fontSize: 12,
            color: accentColor,
          ).copyWith(fontStyle: FontStyle.italic),
        ),
      ],
    );
  }

  String? _getHeaderStatusText(ChatProvider chat) {
    if (chat.isRecordingVoice) return 'Recording voice...';
    if (chat.isPartnerRecordingVoice(widget.conversationId)) return 'Recording voice...';
    if (chat.isPartnerTyping(widget.conversationId)) return 'typing...';
    return null;
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

    // When a link preview arrives, the same message is updated in place (no count change)
    // but the bubble grows; scroll to bottom so the expanded message stays visible.
    final linkPreviewCount = messages.where((m) => m.linkPreviewUrl != null).length;
    if (messages.isNotEmpty && linkPreviewCount > _lastLinkPreviewCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _lastLinkPreviewCount = linkPreviewCount);
        _scrollToBottom();
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
    final messagesAreaBg = FireplaceColors.of(context).messagesAreaBg;
    final mutedColor =
        isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight;
    final otherUser = _getOtherUser();
    final activeConv = chat.getConversationById(widget.conversationId);
    if (activeConv == null && chat.conversations.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
          if (mounted) {
            showTopSnackBar(
              context,
              "You can't message this user",
              backgroundColor: colorScheme.error,
            );
          }
        }
      });
    }

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
                      cacheExtent: _expandCacheForScroll ? _largeCacheExtent : null,
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
          if (otherUser != null && chat.blockedByUserIds.contains(otherUser.id))
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              child: Center(
                child: Text(
                  "You can't type to this user",
                  style: RpgTheme.bodyFont(
                    fontSize: 13,
                    color: mutedColor,
                  ).copyWith(fontStyle: FontStyle.italic),
                ),
              ),
            )
          else
            const ChatInputBar(),
        ],
      ),
    );

    if (widget.isEmbedded) {
      final borderColor = FireplaceColors.of(context).convItemBorder;
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
                GestureDetector(
                  onTap: _onAvatarTap,
                  child: AvatarCircle(
                    displayName: contactName,
                    radius: 18,
                    profilePictureUrl: otherUser?.profilePictureUrl,
                  ),
                ),
                Expanded(
                  child: Center(
                    child: _buildHeaderTitle(context, contactName, otherUser, _getHeaderStatusText(chat)),
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
        title: _buildHeaderTitle(context, contactName, otherUser, _getHeaderStatusText(chat)),
        actions: [
          if (otherUser != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'block') {
                  context.read<ChatProvider>().blockUser(otherUser!.id);
                  Navigator.of(context).pop();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem<String>(
                  value: 'block',
                  child: Text('Block user'),
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: _onAvatarTap,
              child: AvatarCircle(
                displayName: contactName,
                radius: 18,
                profilePictureUrl: otherUser?.profilePictureUrl,
              ),
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
