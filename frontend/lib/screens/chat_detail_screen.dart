import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/conversations_provider.dart';
import '../providers/friends_provider.dart';
import '../providers/messaging_provider.dart';
import '../theme/rpg_theme.dart';
import '../widgets/chat_message_bubble.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/input/chat_composer_viewport.dart';
import '../widgets/message_date_separator.dart';
import '../models/conversation_model.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../widgets/avatar_circle.dart';
import '../widgets/chat_background_pattern.dart';
import '../widgets/ping_effect_overlay.dart';
import '../widgets/top_snackbar.dart';
import '../widgets/message/pinned_message_banner.dart';
import '../widgets/message/message_context_menu_overlay.dart';
import '../utils/scroll_to_message_helper.dart';
import '../utils/pinned_banner_visibility.dart';
import '../utils/reply_preview_helper.dart';
import '../providers/encryption_provider.dart';

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

class _ChatDetailScreenState extends State<ChatDetailScreen> with WidgetsBindingObserver {
  /// Cached in [initState] so [dispose] can sync push state without relying on [context].
  late final ConversationsProvider _conversations;
  late final MessagingProvider _messaging;

  final _scrollController = ScrollController();
  Timer? _showFullHandleTimer;
  bool _showScrollToBottomButton = false;
  bool _showingFullHandle = false;
  int _newMessagesCount = 0;
  int _lastMessageCount = 0;
  int _lastLinkPreviewCount = 0;
  double _lastKeyboardHeight = 0;
  bool _isLoadingMoreLocal = false;
  double? _prePaginationScrollOffset;
  double? _prePaginationScrollExtent;
  bool _wasNearBottom = true;
  /// After the user drags the list, do not auto-scroll to bottom until they scroll back
  /// (cleared when near bottom in [_onScroll]).
  bool _userHasScrolledChat = false;
  static const double _scrollToBottomThreshold = 80;
  int? _scrollTargetListIndex;
  GlobalKey? _scrollTargetKey;

  Future<void> _scrollToMessageId(int messageId) async {
    final messaging = context.read<MessagingProvider>();
    final l10n = AppLocalizations.of(context);

    final listIndex = await loadListIndexForMessageId(
      messageId: messageId,
      getMessages: () => messaging.messages,
      hasMoreMessages: () => messaging.hasMoreMessages,
      loadOlderPage: () =>
          messaging.loadOlderMessages(widget.conversationId),
    );

    if (listIndex == null) {
      if (mounted) {
        showTopSnackBar(context, l10n.snackbarPinnedMessageUnavailable);
      }
      return;
    }

    setState(() {
      _scrollTargetListIndex = listIndex;
      _scrollTargetKey = GlobalKey();
    });

    var revealed = false;
    const maxRevealAttempts = 12;
    final itemCount = messaging.messages.length +
        (_isLoadingMoreLocal ? 1 : 0);
    for (var attempt = 0; attempt < maxRevealAttempts; attempt++) {
      if (attempt > 0 &&
          _scrollController.hasClients &&
          itemCount > 1) {
        final maxExtent = _scrollController.position.maxScrollExtent;
        final fraction = listIndex / (itemCount - 1);
        _scrollController.jumpTo(
          (maxExtent * fraction).clamp(0.0, maxExtent),
        );
      }
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final targetContext = _scrollTargetKey?.currentContext;
      if (targetContext != null) {
        await Scrollable.ensureVisible(
          targetContext, // ignore: use_build_context_synchronously
          alignment: 0.5,
          duration: const Duration(milliseconds: 300),
        );
        revealed = true;
        break;
      }
    }

    if (!revealed && mounted) {
      showTopSnackBar(context, l10n.snackbarPinnedMessageUnavailable);
    }

    if (mounted) {
      setState(() {
        _scrollTargetListIndex = null;
        _scrollTargetKey = null;
      });
    }
  }

  Widget _buildMessageListItem({
    required int listIndex,
    required MessageModel msg,
    required bool showDate,
    required bool isMine,
  }) {
    final scrollKey = listIndex == _scrollTargetListIndex
        ? (_scrollTargetKey ??= GlobalKey())
        : null;
    final bubble = Column(
      key: ValueKey(msg.id),
      children: [
        if (showDate) MessageDateSeparator(date: msg.createdAt),
        if (showDate) const SizedBox(height: 8),
        ChatMessageBubble(
          message: msg,
          isMine: isMine,
        ),
      ],
    );
    if (scrollKey == null) return bubble;
    return KeyedSubtree(key: scrollKey, child: bubble);
  }

  Widget? _buildPinnedMessageBanner(
    BuildContext context,
    ConversationModel conv,
    MessagingProvider messaging,
    ConversationsProvider convs,
  ) {
    if (!shouldShowPinnedMessageBanner(conv)) return null;
    final l10n = AppLocalizations.of(context);
    final preview = conv.pinnedMessagePreview;
    if (preview == null) return null;
    final encryption = context.read<EncryptionProvider>();
    final pinnedId = conv.pinnedMessageId!;
    final localRow = messaging.messageById(pinnedId);
    final previewModel = resolvePinnedPreviewMessage(
      serverPreview: preview,
      localMessage: localRow,
    );
    final previewText = replyPreviewForMessage(
      l10n,
      previewModel,
      encryption: encryption,
    );
    return PinnedMessageBanner(
      previewText: previewText,
      senderLabel: previewModel.senderUsername.isNotEmpty
          ? previewModel.senderUsername
          : convs.getOtherUserUsername(conv),
      onTap: () => _scrollToMessageId(conv.pinnedMessageId!),
      onUnpin: () => messaging.unpinMessage(conv.id),
    );
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    // With reverse:true, pixels=0 is the bottom (newest). Near-bottom = pixels <= threshold.
    final atBottom = pos.pixels <= _scrollToBottomThreshold;
    _wasNearBottom = atBottom;
    if (atBottom) {
      _userHasScrolledChat = false;
    }
    if (_showScrollToBottomButton != !atBottom && mounted) {
      setState(() => _showScrollToBottomButton = !atBottom);
    }

    // Near visual top (oldest messages) = pixels near maxScrollExtent → load older.
    // Require maxScrollExtent > 0 so short non-scrollable threads do not satisfy
    // pixels >= maxScrollExtent - 300 while sitting at the bottom.
    final maxExtent = pos.maxScrollExtent;
    if (maxExtent > 0 && pos.pixels >= maxExtent - 300) {
      final messaging = context.read<MessagingProvider>();
      if (!messaging.isLoadingMore && messaging.hasMoreMessages) {
        _prePaginationScrollOffset = _scrollController.offset;
        _prePaginationScrollExtent = _scrollController.position.maxScrollExtent;
        setState(() => _isLoadingMoreLocal = true);
        messaging.loadOlderMessages(widget.conversationId);
      }
    }
  }

  void _onNewMessages(int currentCount, int added) {
    if (_isLoadingMoreLocal) {
      final messaging = context.read<MessagingProvider>();
      if (!messaging.isLoadingMore) {
        setState(() => _isLoadingMoreLocal = false);
        final preOffset = _prePaginationScrollOffset;
        final preExtent = _prePaginationScrollExtent;
        _prePaginationScrollOffset = null;
        _prePaginationScrollExtent = null;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (preOffset == null || preExtent == null) return;
          if (!_scrollController.hasClients) return;
          final newExtent = _scrollController.position.maxScrollExtent;
          _scrollController.jumpTo(preOffset + (newExtent - preExtent));
        });
        return;
      }
      final preOffset = _prePaginationScrollOffset;
      final preExtent = _prePaginationScrollExtent;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (preOffset == null || preExtent == null) return;
        if (!_scrollController.hasClients) return;
        final newExtent = _scrollController.position.maxScrollExtent;
        final delta = newExtent - preExtent;
        _prePaginationScrollOffset = preOffset + delta;
        _prePaginationScrollExtent = newExtent;
        _scrollController.jumpTo(preOffset + delta);
      });
      return;
    }
    // Non-pagination path.
    if (added <= 0) return;

    // Initial full snapshot: opening the chat. _lastMessageCount was 0 so added == currentCount.
    // Do NOT badge — this is the open render, not an incoming message.
    // pixels=0 already shows newest with reverse:true; no explicit scroll needed.
    if (_lastMessageCount == 0 && added == currentCount) {
      _lastMessageCount = currentCount;
      final messaging = context.read<MessagingProvider>();
      _lastLinkPreviewCount =
          messaging.messages.where((m) => m.linkPreviewUrl != null).length;
      return;
    }

    // Subsequent incoming message.
    _lastMessageCount = currentCount;
    final messaging = context.read<MessagingProvider>();
    _lastLinkPreviewCount =
        messaging.messages.where((m) => m.linkPreviewUrl != null).length;
    if (_wasNearBottom && !_userHasScrolledChat) {
      _scrollToBottom();
    } else {
      setState(() => _newMessagesCount++);
    }
  }

  /// Clears server push-suppression when this route/widget is torn down without the
  /// AppBar back handler (Android system back, block menu, auto-pop after conv removed).
  /// Skips when another conversation is already active (desktop list switch).
  void _clearActiveConversationIfThisChat() {
    if (_conversations.activeConversationDeletedByOther) {
      _conversations.clearActiveIfDeletedByOther();
      return;
    }
    if (_conversations.activeConversationId == widget.conversationId) {
      _conversations.closeConversation(notify: false);
      _messaging.clearMessages();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _conversations.notifyActiveConversationChanged();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _conversations = context.read<ConversationsProvider>();
    _messaging = context.read<MessagingProvider>();
    _scrollController.addListener(_onScroll);
    // Active id + pushClientState immediately; listener notify deferred (initState).
    _conversations.openConversation(widget.conversationId, notify: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _conversations.notifyActiveConversationChanged();
      _messaging.loadCachedMessages(widget.conversationId);
      _messaging.getMessages(widget.conversationId);
    });

    // Countdown tick + expiry prune run on [ConversationsScreen] (always mounted in
    // [MainShell] IndexedStack) so we avoid duplicate 1 Hz timers when chat is open.
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
      _userHasScrolledChat = false;
      _isLoadingMoreLocal = false;
      _prePaginationScrollOffset = null;
      _prePaginationScrollExtent = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final convs = context.read<ConversationsProvider>();
        final messaging = context.read<MessagingProvider>();
        messaging.loadCachedMessages(widget.conversationId);
        convs.openConversation(widget.conversationId);
        messaging.getMessages(widget.conversationId);
      });
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) return;
    dismissMessageContextMenu();

    final bottom = View.of(context).viewInsets.bottom;
    if (bottom > 0 &&
        _lastKeyboardHeight == 0 &&
        _messaging.messages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!mounted || !_scrollController.hasClients) return;
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        });
      });
    }
    _lastKeyboardHeight = bottom;
  }

  @override
  void dispose() {
    dismissMessageContextMenu();
    WidgetsBinding.instance.removeObserver(this);
    _clearActiveConversationIfThisChat();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
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
    if (!mounted || !_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _onScrollToBottomButtonTap() {
    _scrollToBottom();
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
    return context.read<ConversationsProvider>().getConversationById(widget.conversationId);
  }

  String _getContactName() {
    final conv = _getActiveConversation();
    return conv != null
        ? context.read<ConversationsProvider>().getOtherUserUsername(conv)
        : '';
  }

  UserModel? _getOtherUser() {
    final conv = _getActiveConversation();
    return conv != null ? context.read<ConversationsProvider>().getOtherUser(conv) : null;
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

  String? _getHeaderStatusText(BuildContext context, MessagingProvider msg) {
    final l10n = AppLocalizations.of(context);
    if (msg.isRecordingVoice) return l10n.recordingVoice;
    if (msg.isPartnerRecordingVoice(widget.conversationId)) return l10n.recordingVoice;
    if (msg.isPartnerTyping(widget.conversationId)) return l10n.typing;
    return null;
  }

  bool _isDifferentDay(DateTime a, DateTime b) {
    final la = a.toLocal();
    final lb = b.toLocal();
    return la.year != lb.year || la.month != lb.month || la.day != lb.day;
  }

  Widget _buildMessagesArea({
    required double listBottomPadding,
    required List<MessageModel> messages,
    required Color mutedColor,
    required Color messagesAreaBg,
    required int currentUserId,
  }) {
    return SafeArea(
      bottom: false,
      child: ChatBackgroundPattern(
        dotColor: mutedColor.withValues(alpha: 0.08),
        backgroundColor: messagesAreaBg,
        child: messages.isEmpty
            ? Center(
                child: Text(
                  AppLocalizations.of(context).noMessagesYet,
                  style: RpgTheme.bodyFont(
                    fontSize: 14,
                    color: mutedColor,
                  ),
                ),
              )
            : NotificationListener<ScrollStartNotification>(
                onNotification: (notification) {
                  dismissMessageContextMenu();
                  return false;
                },
                child: NotificationListener<UserScrollNotification>(
                  onNotification: (notification) {
                    _userHasScrolledChat = true;
                    return false;
                  },
                  child: ListView.builder(
                    reverse: true,
                    controller: _scrollController,
                    findChildIndexCallback: (Key key) {
                      if (key is ValueKey<int>) {
                        final idx =
                            messages.indexWhere((m) => m.id == key.value);
                        if (idx == -1) return null;
                        return messages.length - 1 - idx;
                      }
                      return null;
                    },
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 20,
                      top: 8,
                      bottom: 8 + listBottomPadding,
                    ),
                    itemCount:
                        messages.length + (_isLoadingMoreLocal ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_isLoadingMoreLocal && index == messages.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final msgIndex = messages.length - 1 - index;
                      final msg = messages[msgIndex];
                      final showDate = msgIndex == 0 ||
                          _isDifferentDay(
                            messages[msgIndex - 1].createdAt,
                            msg.createdAt,
                          );
                      return _buildMessageListItem(
                        listIndex: index,
                        msg: msg,
                        showDate: showDate,
                        isMine: msg.senderId == currentUserId,
                      );
                    },
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildComposerFooter({
    required UserModel? otherUser,
    required Color mutedColor,
    required ColorScheme colorScheme,
  }) {
    if (otherUser != null &&
        context.read<FriendsProvider>().blockedByUserIds.contains(otherUser.id)) {
      return SafeArea(
        top: false,
        left: true,
        right: true,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          child: Center(
            child: Text(
              AppLocalizations.of(context).cantTypeToThisUser,
              style: RpgTheme.bodyFont(
                fontSize: 13,
                color: mutedColor,
              ).copyWith(fontStyle: FontStyle.italic),
            ),
          ),
        ),
      );
    }
    return const ChatInputBar();
  }

  @override
  Widget build(BuildContext context) {
    final messaging = context.watch<MessagingProvider>();
    final convs = context.watch<ConversationsProvider>();
    final auth = context.watch<AuthProvider>();
    final messages = messaging.messages;
    final contactName = _getContactName();

    if (messages.isNotEmpty && messages.length != _lastMessageCount) {
      final added = messages.length - _lastMessageCount;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
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

    final isDark = RpgTheme.isDark(context);
    final colorScheme = Theme.of(context).colorScheme;
    final messagesAreaBg = FireplaceColors.of(context).messagesAreaBg;
    final mutedColor =
        isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight;
    final otherUser = _getOtherUser();
    final activeConv = convs.getConversationById(widget.conversationId);
    final statusText = _getHeaderStatusText(context, messaging);
    final headerTitle = _buildHeaderTitle(context, contactName, otherUser, statusText);
    final pinnedBanner = activeConv != null
        ? _buildPinnedMessageBanner(
            context,
            activeConv,
            messaging,
            convs,
          )
        : null;
    final deletedByOther = activeConv == null && convs.activeConversationDeletedByOther;
    // Auto-pop only when conv gone and NOT deleted by other (e.g. unfriend/block)
    if (activeConv == null && convs.conversations.isNotEmpty && !deletedByOther) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (Navigator.canPop(context)) {
          _clearActiveConversationIfThisChat();
          Navigator.pop(context);
          if (mounted) {
            showTopSnackBar(
              context,
              AppLocalizations.of(context).cantMessageThisUser,
              backgroundColor: colorScheme.error,
            );
          }
        }
      });
    }

    final currentUserId = auth.currentUser!.id;
    final composerFooter = _buildComposerFooter(
      otherUser: otherUser,
      mutedColor: mutedColor,
      colorScheme: colorScheme,
    );

    // When other user deleted the conversation, show message instead of auto-close
    final Widget body;
    if (deletedByOther) {
      body = SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.delete_outline, size: 48, color: mutedColor),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context).conversationDeletedByOther,
                  textAlign: TextAlign.center,
                  style: RpgTheme.bodyFont(fontSize: 14, color: mutedColor),
                ),
              ],
            ),
          ),
        ),
      );
    } else if (widget.isEmbedded) {
      // Pinned banner is rendered by the embedded shell above this [body].
      body = Column(
        children: [
          Expanded(
            child: _buildMessagesArea(
              listBottomPadding: 0,
              messages: messages,
              mutedColor: mutedColor,
              messagesAreaBg: messagesAreaBg,
              currentUserId: currentUserId,
            ),
          ),
          composerFooter,
        ],
      );
    } else {
      body = Column(
        children: [
          ?pinnedBanner,
          Expanded(
            child: ChatComposerViewport(
              messageListBuilder: (listBottomPadding) => _buildMessagesArea(
                listBottomPadding: listBottomPadding,
                messages: messages,
                mutedColor: mutedColor,
                messagesAreaBg: messagesAreaBg,
                currentUserId: currentUserId,
              ),
              composer: composerFooter,
            ),
          ),
        ],
      );
    }

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
                    child: headerTitle,
                  ),
                ),
              ],
            ),
          ),
          ?pinnedBanner,
          Expanded(
            child: Stack(
              children: [
                body,

                // Ping effect overlay
                if (messaging.showPingEffect)
                  Positioned.fill(
                    child: PingEffectOverlay(
                      onComplete: () {
                        messaging.clearPingEffect();
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
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _clearActiveConversationIfThisChat();
            Navigator.of(context).pop();
          },
        ),
        title: headerTitle,
        actions: [
          if (otherUser != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'block') {
                  context.read<FriendsProvider>().blockUser(otherUser.id);
                  _clearActiveConversationIfThisChat();
                  Navigator.of(context).pop();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  value: 'block',
                  child: Text(AppLocalizations.of(context).blockUser),
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
          if (messaging.showPingEffect)
            Positioned.fill(
              child: PingEffectOverlay(
                onComplete: () {
                  messaging.clearPingEffect();
                },
              ),
            ),
          if (_showScrollToBottomButton) _buildScrollToBottomButton(),
        ],
      ),
    );
  }
}
