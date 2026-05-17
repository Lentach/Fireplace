import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../l10n/app_localizations.dart';
import '../../models/message_model.dart';
import '../../providers/conversations_provider.dart';
import '../../providers/messaging_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/rpg_theme.dart';
import '../../utils/message_expiry.dart';
import '../chat_action_tiles.dart';
import '../hearth_fade_arc.dart';
import '../top_snackbar.dart' show showTopSnackBar;
import 'recording_controller.dart';
import 'reply_preview_bar.dart';

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({super.key});

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  MessageModel? _lastReplyingTo;
  bool _showActionPanel = false;
  late final AnimationController _actionPanelController;
  late final Animation<double> _actionPanelAnimation;

  Timer? _typingDebounceTimer;

  // Recording state mirrored from RecordingController via callback
  bool _isRecording = false;
  bool _isSendingVoice = false;

  // GlobalKey to access RecordingControllerState.buildRecordingBar()
  final _recordingKey = GlobalKey<RecordingControllerState>();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (_controller.text.trim().isEmpty) return;
      _typingDebounceTimer?.cancel();
      _typingDebounceTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) context.read<MessagingProvider>().emitTyping();
      });
    });

    _actionPanelController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _actionPanelAnimation = CurvedAnimation(
      parent: _actionPanelController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _actionPanelController.dispose();
    _typingDebounceTimer?.cancel();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final messaging = context.read<MessagingProvider>();
    final convs = context.read<ConversationsProvider>();
    final expiresIn = convs.conversationDisappearingTimer;
    messaging.sendMessage(text, expiresIn: expiresIn);

    _controller.clear();
    // IME "Send" on multiline can unfocus on the next frame even while the node still
    // reports hasFocus synchronously; schedule a refocus only when focus is actually lost.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focusNode.canRequestFocus) return;
      if (!_focusNode.hasFocus) {
        _focusNode.requestFocus();
      }
    });
  }

  void _toggleActionPanel() {
    setState(() {
      _showActionPanel = !_showActionPanel;
      if (_showActionPanel) {
        _actionPanelController.forward();
      } else {
        _actionPanelController.reverse();
      }
    });
  }

  /// Called by [RecordingController] when recording state changes.
  void _onRecordingStateChanged(bool isRecording) {
    setState(() => _isRecording = isRecording);
  }

  /// Called by [RecordingController] when a voice message is ready.
  Future<void> _handleVoiceSent({
    required int duration,
    String? localAudioPath,
    Uint8List? audioBytes,
  }) async {
    final messaging = context.read<MessagingProvider>();
    final convs = context.read<ConversationsProvider>();
    final l10n = AppLocalizations.of(context);
    final conversationId = convs.activeConversationId;
    final failedToSendMessage = l10n.snackbarFailedToSendVoiceMessage;
    final noActiveConversationMessage = l10n.snackbarNoActiveConversation;

    setState(() => _isSendingVoice = true);
    try {
      if (conversationId == null) {
        if (!mounted) return;
        showTopSnackBar(context, noActiveConversationMessage);
        return;
      }

      final conversation = convs.conversations.firstWhere(
        (c) => c.id == conversationId,
      );
      final recipientId = conversation.userOne.id == convs.currentUserId
          ? conversation.userTwo.id
          : conversation.userOne.id;

      await messaging.sendVoiceMessage(
        recipientId: recipientId,
        duration: duration,
        conversationId: conversationId,
        localAudioPath: localAudioPath,
        localAudioBytes: audioBytes?.toList(),
      );
    } catch (e) {
      if (!mounted) return;
      showTopSnackBar(context, failedToSendMessage);
      debugPrint('Send voice error: $e');
    } finally {
      if (mounted) {
        setState(() => _isSendingVoice = false);
      }
    }
  }

  String _bannerDurationLabel(AppLocalizations l10n, int seconds) {
    final parts = splitDisappearingSeconds(seconds);
    final summaryParts = <String>[];
    if (parts.days > 0) {
      summaryParts.add(l10n.disappearingTimerDays(parts.days));
    }
    if (parts.hours > 0) {
      summaryParts.add(l10n.disappearingTimerHours(parts.hours));
    }
    if (parts.minutes > 0) {
      summaryParts.add(l10n.disappearingTimerMinutes(parts.minutes));
    }
    if (parts.seconds > 0) {
      summaryParts.add(l10n.disappearingTimerSeconds(parts.seconds));
    }
    return summaryParts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final messaging = context.watch<MessagingProvider>();
    final convs = context.watch<ConversationsProvider>();
    final replyingTo = messaging.replyingToMessage;

    if (replyingTo != null && _lastReplyingTo != replyingTo) {
      _lastReplyingTo = replyingTo;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_focusNode.hasFocus && _focusNode.canRequestFocus) {
          _focusNode.requestFocus();
        }
      });
    } else if (replyingTo == null) {
      _lastReplyingTo = null;
    }

    final activeTimer = convs.conversationDisappearingTimer;
    final l10n = AppLocalizations.of(context);
    final isDark = RpgTheme.isDark(context);
    final colorScheme = Theme.of(context).colorScheme;
    final fc = FireplaceColors.of(context);
    final themePref = context.watch<SettingsProvider>().themePreference;
    final ephemeral = RpgTheme.ephemeralAccent(
      context,
      themePreference: themePref,
    );
    final mediaQuery = MediaQuery.of(context);
    final pad = mediaQuery.padding;
    final isCompactLayout =
        mediaQuery.size.width < AppConstants.layoutBreakpointDesktop;
    // Phone / narrow PWA: keep trailing mic off the physical right edge so OS back-swipe
    // and browser edge gestures are less likely to steal the long-press.
    const trailingGestureBufferDp = 14.0;
    final trailingGestureBuffer =
        isCompactLayout ? trailingGestureBufferDp : 0.0;
    // Insets for notches / home indicator: chat body no longer applies horizontal SafeArea
    // around the composer (see ChatDetailScreen), so we pad here instead.
    final composerHorizontalPadding = EdgeInsets.fromLTRB(
      8.0 + pad.left,
      8.0,
      4.0 + pad.right + trailingGestureBuffer,
      8.0,
    );
    final keyboardVisible = mediaQuery.viewInsets.bottom > 0;
    final bottomSystemInset =
        math.max(mediaQuery.viewPadding.bottom, mediaQuery.padding.bottom);
    const additionalBottomSpacing = 16.0;
    final needsErgonomicBuffer = bottomSystemInset > 0;
    final webMobileFallbackInset = !needsErgonomicBuffer &&
            kIsWeb &&
            isCompactLayout &&
            !keyboardVisible
        ? 16.0
        : 0.0;
    final bottomInteractivePadding = keyboardVisible
        ? 0.0
        : (needsErgonomicBuffer
            ? bottomSystemInset + additionalBottomSpacing
            : webMobileFallbackInset);

    // Cap multiline growth: Row/Expanded can still pass a tall maxHeight; keep the
    // composer Telegram-like even under large text scale or IME quirks.
    final textScaler = MediaQuery.textScalerOf(context);
    final maxComposerHeight =
        (textScaler.scale(22.0) * 6 + 36).clamp(120.0, 400.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
          // Reply preview
          if (replyingTo != null)
            ReplyPreviewBar(
              message: replyingTo,
              onDismiss: () => messaging.clearReplyingTo(),
            ),

          if (activeTimer != null)
            Material(
              color: ephemeral.withValues(alpha: 0.12),
              child: Semantics(
                label: l10n.disappearingComposerBannerSemantics(
                  _bannerDurationLabel(l10n, activeTimer),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CustomPaint(
                        size: const Size(14, 14),
                        painter: HearthFadeArcPainter(
                          color: ephemeral,
                          trackColor: ephemeral.withValues(alpha: 0.35),
                          dotted: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          l10n.disappearingComposerBanner(
                            _bannerDurationLabel(l10n, activeTimer),
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: RpgTheme.bodyFont(
                            fontSize: 11,
                            color: ephemeral,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Input row
          Container(
            padding: composerHorizontalPadding,
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(top: BorderSide(color: fc.convItemBorder)),
            ),
            child: Row(
              children: [
                // Action panel toggle (hidden during recording)
                if (!_isRecording)
                  IconButton(
                    icon: Icon(
                      _showActionPanel
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                    ),
                    iconSize: 24,
                    color: isDark
                        ? RpgTheme.mutedDark
                        : RpgTheme.textSecondaryLight,
                    onPressed: _toggleActionPanel,
                  ),

                // Text field or recording bar
                Expanded(
                  child: _isRecording
                      ? (_recordingKey.currentState
                              ?.buildRecordingBar(context) ??
                          const SizedBox.shrink())
                      : CallbackShortcuts(
                          bindings: <ShortcutActivator, VoidCallback>{
                            // Web/desktop: multiline fields often lack an IME “Send”; keep one send path.
                            const SingleActivator(
                              LogicalKeyboardKey.enter,
                              control: true,
                            ): _send,
                            const SingleActivator(
                              LogicalKeyboardKey.enter,
                              meta: true,
                            ): _send,
                          },
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: maxComposerHeight,
                            ),
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              style: RpgTheme.bodyFont(
                                fontSize: 14,
                                color: colorScheme.onSurface,
                              ),
                              decoration: InputDecoration(
                                hintText: AppLocalizations.of(context)
                                    .chatMessageHint,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide(color: fc.tabBorder),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide(color: fc.tabBorder),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide(
                                    color: RpgTheme.primaryColor(context),
                                    width: 1.5,
                                  ),
                                ),
                                filled: true,
                                fillColor: fc.inputBg,
                              ),
                              // Cap height so the composer does not consume the whole screen (matches
                              // WhatsApp/Telegram-style behavior: grow to a few lines, then scroll inside).
                              minLines: 1,
                              maxLines: 6,
                              // Send via IME action (mobile) or Ctrl/Cmd+Enter (web/desktop).
                              // Plain Enter still inserts '\n' in this multiline field.
                              textInputAction: TextInputAction.send,
                              // Default [onEditingComplete] unfocuses after "Send", which dismisses
                              // the keyboard while the node can still report focused in the same sync turn.
                              onEditingComplete: () {},
                              onSubmitted: (_) => _send(),
                            ),
                          ),
                        ),
                ),

                const SizedBox(width: 2),

                // RecordingController is ALWAYS in the widget tree here.
                // CLAUDE.md: "mic must stay in widget tree — GestureDetector unmounts -> no events."
                RecordingController(
                  key: _recordingKey,
                  onVoiceSent: _handleVoiceSent,
                  onRecordingStateChanged: _onRecordingStateChanged,
                  isSendingVoice: _isSendingVoice,
                ),
              ],
            ),
          ),

        if (!_showActionPanel && bottomInteractivePadding > 0)
          Container(
            height: bottomInteractivePadding,
            color: colorScheme.surface,
          ),

        // Action tiles with slide animation
        SizeTransition(
          sizeFactor: _actionPanelAnimation,
          axisAlignment: -1.0,
          child: ChatActionTiles(bottomPadding: bottomInteractivePadding),
        ),
      ],
    );
  }
}
