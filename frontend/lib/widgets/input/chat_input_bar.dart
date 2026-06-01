import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
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
import '../../utils/reply_preview_helper.dart';
import '../../utils/soft_keyboard.dart';
import '../../utils/web_focus_guard.dart';
import '../../utils/web_ios_webkit.dart';
import '../../utils/web_viewport_scroll.dart';
import '../chat_action_tiles.dart';
import '../hearth_fade_arc.dart';
import '../top_snackbar.dart' show showTopSnackBar;
import 'focus_guard_area.dart';
import 'recording_controller.dart';
import 'reply_preview_bar.dart';

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({super.key});

  @override
  State<ChatInputBar> createState() => ChatInputBarState();
}

class ChatInputBarState extends State<ChatInputBar>
    with SingleTickerProviderStateMixin {
  static const Duration _kTrailingSendFadeDuration = Duration(milliseconds: 175);

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  MessageModel? _lastReplyingTo;
  bool _showActionPanel = false;
  late final AnimationController _actionPanelController;
  late final Animation<double> _actionPanelAnimation;

  Timer? _typingDebounceTimer;
  MessagingProvider? _messagingProvider;

  // Set in _send(); cleared after 500ms. While true the FocusNode listener
  // fires a microtask restore the instant iOS blur reaches Flutter — much
  // faster than waiting for the next postFrameCallback.
  bool _sendJustFired = false;
  Timer? _sendJustFiredTimer;

  // Recording state mirrored from RecordingController via callback
  bool _isRecording = false;
  bool _isRecordingLocked = false;
  bool _isSendingVoice = false;

  // GlobalKey to access RecordingControllerState.buildRecordingBar()
  final _recordingKey = GlobalKey<RecordingControllerState>();

  /// Rebuilds only the recording bar hint (slide-up / trash), not the whole composer.
  final ValueNotifier<int> _recordingBarVisualTick = ValueNotifier(0);

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

    if (kIsWeb) {
      _focusNode.addListener(_onComposerFocusForWebViewport);
      _focusNode.addListener(_onFocusLostAfterSend);
      ensureFocusGuardListenerInstalled();
    }
  }

  void _requestComposerFocus() {
    if (!mounted || !_focusNode.canRequestFocus) return;
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
    showSoftKeyboardIfHidden(context: context, hasFocus: true);
  }

  void _onComposerFocusForWebViewport() {
    if (!kIsWeb) return;
    if (!_focusNode.hasFocus) {
      setIOSWebViewportScrollLocked(false);
      return;
    }
    if (!isIOSWebKit()) return;
    setIOSWebViewportScrollLocked(true);
    resetWebDocumentScroll();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focusNode.hasFocus) return;
      resetWebDocumentScroll();
    });
  }

  void _onMessagingProviderChanged() {
    final replyingTo = _messagingProvider?.replyingToMessage;
    _onReplyTargetChanged(replyingTo);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final messaging = context.read<MessagingProvider>();
    if (_messagingProvider != messaging) {
      _messagingProvider?.removeListener(_onMessagingProviderChanged);
      _messagingProvider = messaging;
      messaging.addListener(_onMessagingProviderChanged);
      messaging.setComposerFocusRequest(_requestComposerFocus);
      _onReplyTargetChanged(messaging.replyingToMessage);
    }
  }

  void _onReplyTargetChanged(MessageModel? replyingTo) {
    if (replyingTo != null && _lastReplyingTo != replyingTo) {
      _lastReplyingTo = replyingTo;
      // Fallback when reply was set without a user gesture (e.g. tests).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_focusNode.canRequestFocus) return;
        if (!_focusNode.hasFocus) {
          _focusNode.requestFocus();
        }
        showSoftKeyboardIfHidden(context: context, hasFocus: true);
      });
    } else if (replyingTo == null) {
      _lastReplyingTo = null;
    }
  }

  @override
  void dispose() {
    if (kIsWeb) {
      _focusNode.removeListener(_onComposerFocusForWebViewport);
      _focusNode.removeListener(_onFocusLostAfterSend);
      setIOSWebViewportScrollLocked(false);
    }
    _sendJustFiredTimer?.cancel();
    _messagingProvider?.setComposerFocusRequest(null);
    _messagingProvider?.removeListener(_onMessagingProviderChanged);
    _controller.dispose();
    _focusNode.dispose();
    _actionPanelController.dispose();
    _recordingBarVisualTick.dispose();
    _typingDebounceTimer?.cancel();
    super.dispose();
  }

  // Fires the moment Flutter learns the composer lost focus. If a send just
  // happened we restore immediately in a microtask — faster than waiting for
  // the next postFrameCallback, so the keyboard barely dips before coming back.
  void _onFocusLostAfterSend() {
    if (!isIOSWebKit()) return;
    if (_focusNode.hasFocus || !_sendJustFired) return;
    _sendJustFired = false;
    _sendJustFiredTimer?.cancel();
    Future.microtask(() {
      if (!mounted || !_focusNode.canRequestFocus) return;
      _focusNode.requestFocus();
      showSoftKeyboardIfHidden(context: context, hasFocus: true).ignore();
    });
  }

  void _onRecordingBarVisualChanged() {
    _recordingBarVisualTick.value++;
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final messaging = context.read<MessagingProvider>();
    final convs = context.read<ConversationsProvider>();
    final expiresIn = convs.conversationDisappearingTimer;
    messaging.sendMessage(text, expiresIn: expiresIn);

    // Arm the fast-restore listener for iOS before clearing text.
    if (kIsWeb && isIOSWebKit()) {
      _sendJustFired = true;
      _sendJustFiredTimer?.cancel();
      // Disarm after 500ms so an intentional blur right after send is respected.
      _sendJustFiredTimer = Timer(const Duration(milliseconds: 500), () {
        _sendJustFired = false;
      });
    }

    _controller.clear();
    // Fallback for non-iOS or when FocusNode listener fires before the blur.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focusNode.canRequestFocus) return;
      if (!_focusNode.hasFocus) _focusNode.requestFocus();
      showSoftKeyboardIfHidden(context: context, hasFocus: true);
    });
  }

  void _toggleActionPanel() {
    final hadComposerFocus = _focusNode.hasFocus;
    setState(() {
      _showActionPanel = !_showActionPanel;
      if (_showActionPanel) {
        _actionPanelController.forward();
      } else {
        _actionPanelController.reverse();
      }
    });
    if (kIsWeb && isIOSWebKit()) {
      if (hadComposerFocus) {
        // Keyboard was open: keep it open and reset any iOS document scroll.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_focusNode.canRequestFocus) return;
          if (!_focusNode.hasFocus) {
            _focusNode.requestFocus();
          }
          showSoftKeyboardIfHidden(context: context, hasFocus: true);
          resetWebDocumentScroll();
        });
      } else if (_showActionPanel) {
        // Panel just opened from keyboard-hidden state. iOS may auto-focus the
        // textarea on any canvas tap (no active editable → guard does not fire).
        // Dismiss the auto-focus so the keyboard does not appear unexpectedly,
        // and reset any document scroll iOS may have applied.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_showActionPanel) return;
          if (_focusNode.hasFocus) _focusNode.unfocus();
          resetWebDocumentScroll();
        });
      }
    }
  }

  /// Called by [RecordingController] when recording state changes.
  void _onRecordingStateChanged(bool isRecording) {
    setState(() {
      _isRecording = isRecording;
      if (!isRecording) {
        _isRecordingLocked = false;
      }
    });
  }

  /// Called by [RecordingController] when slide-up lock is entered or cleared.
  void _onRecordingLockChanged(bool isLocked) {
    setState(() => _isRecordingLocked = isLocked);
  }

  /// Widget tests: mirror [RecordingController.onRecordingStateChanged] without mic hardware.
  @visibleForTesting
  void setRecordingForTest(bool isRecording) {
    setState(() => _isRecording = isRecording);
  }

  /// Widget tests: exercise trailing spinner / send precedence without upload pipeline.
  @visibleForTesting
  void setSendingVoiceForTest(bool isSendingVoice) {
    setState(() => _isSendingVoice = isSendingVoice);
  }

  /// Widget tests: mirror slide-up lock without mic hardware.
  @visibleForTesting
  void setRecordingLockedForTest(bool isLocked) {
    setState(() => _isRecordingLocked = isLocked);
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

  /// Trailing mic + text-send overlay. [ValueListenableBuilder] limits rebuilds to this slot.
  Widget _buildTrailingSlot(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _controller,
      builder: (context, value, _) {
        final showTextSend = !_isRecording &&
            !_isSendingVoice &&
            value.text.trim().isNotEmpty;
        final showVoiceSend =
            _isRecording && _isRecordingLocked && !_isSendingVoice;

        // ExcludeFocus on the whole trailing slot (mic + send overlay) so long-press
        // never steals focus from the text field. RecordingController does not add a
        // second ExcludeFocus — one ancestor is enough.
        return ExcludeFocus(
          child: SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ExcludeSemantics(
                  excluding: showTextSend || showVoiceSend,
                  child: AnimatedOpacity(
                    opacity: (showTextSend || showVoiceSend) ? 0.0 : 1.0,
                    duration: _kTrailingSendFadeDuration,
                    curve: Curves.easeInOut,
                    child: RecordingController(
                      key: _recordingKey,
                      onVoiceSent: _handleVoiceSent,
                      onRecordingStateChanged: _onRecordingStateChanged,
                      onRecordingLockChanged: _onRecordingLockChanged,
                      onRecordingBarChanged: _onRecordingBarVisualChanged,
                      isSendingVoice: _isSendingVoice,
                    ),
                  ),
                ),
                Positioned.fill(
                  key: const ValueKey('composer_text_send_layer'),
                  child: ExcludeSemantics(
                    excluding: !showTextSend,
                    child: IgnorePointer(
                      ignoring: !showTextSend,
                      child: AnimatedOpacity(
                        opacity: showTextSend ? 1 : 0,
                        duration: _kTrailingSendFadeDuration,
                        curve: Curves.easeInOut,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Centered send icon, paint only — no hit test (the mic
                            // GestureDetector below handles hold-to-record).
                            IgnorePointer(
                              child: Icon(
                                Icons.send_rounded,
                                size: 26,
                                color: RpgTheme.primaryColor(context),
                              ),
                            ),
                            // Full 48×48 opaque tap target (was a left-nudged 22×22,
                            // easy to miss + leaked outer-ring taps to the mic).
                            Positioned.fill(
                              child: _ComposerTapSendOverlay(
                                enabled: showTextSend,
                                onTap: _send,
                                tooltip: l10n.chatComposerSendTooltip,
                                semanticsLabel: l10n.chatComposerSendSemantics,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  key: const ValueKey('composer_voice_send_layer'),
                  child: ExcludeSemantics(
                    excluding: !showVoiceSend,
                    child: IgnorePointer(
                      ignoring: !showVoiceSend,
                      child: AnimatedOpacity(
                        opacity: showVoiceSend ? 1 : 0,
                        duration: _kTrailingSendFadeDuration,
                        curve: Curves.easeInOut,
                        child: Transform.translate(
                          offset: const Offset(
                            RecordingControllerState.kMicTrailingRestingOffsetX,
                            0,
                          ),
                          child: Tooltip(
                            message: l10n.voiceRecordingSendVoiceTooltip,
                            child: Semantics(
                              button: true,
                              label: l10n.voiceRecordingSendVoiceSemantics,
                              excludeSemantics: true,
                              child: IconButton(
                                onPressed: showVoiceSend
                                    ? () => _recordingKey.currentState
                                        ?.sendLockedRecording()
                                    : null,
                                padding: const EdgeInsets.all(12),
                                constraints: const BoxConstraints(
                                  minWidth: 48,
                                  minHeight: 48,
                                ),
                                icon: Icon(
                                  Icons.send_rounded,
                                  size: 22,
                                  color: RpgTheme.primaryColor(context),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
  // Rebuild only for composer-relevant provider slices so message list / decrypt
  // updates do not dismiss the Android soft keyboard while typing.
    final replyingTo = context.select<MessagingProvider, MessageModel?>(
      (m) => m.replyingToMessage,
    );

    final activeTimer = context.select<ConversationsProvider, int?>(
      (c) => c.conversationDisappearingTimer,
    );
    final l10n = AppLocalizations.of(context);
    final isDark = RpgTheme.isDark(context);
    final colorScheme = Theme.of(context).colorScheme;
    final fc = FireplaceColors.of(context);
    final themePref = context.select<SettingsProvider, String>(
      (s) => s.themePreference,
    );
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
            Selector<MessagingProvider, MessageModel>(
              selector: (_, messaging) {
                return findMessageById(replyingTo.id, messaging.messages) ??
                    replyingTo;
              },
              builder: (context, resolvedReply, _) {
                return ReplyPreviewBar(
                  message: resolvedReply,
                  onDismiss: () =>
                      context.read<MessagingProvider>().clearReplyingTo(),
                );
              },
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
                  FocusGuardArea(
                    id: 'composer_action_toggle',
                    child: Focus(
                      canRequestFocus: false,
                      child: IconButton(
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
                    ),
                  ),

                // Text field or recording bar
                Expanded(
                  child: _isRecording
                      ? ValueListenableBuilder<int>(
                          valueListenable: _recordingBarVisualTick,
                          builder: (context, tick, child) {
                            final recordingState = _recordingKey.currentState;
                            if (recordingState == null) {
                              return const SizedBox.shrink();
                            }
                            final bar = _isRecordingLocked
                                ? recordingState.buildRecordingBarLocked(
                                    context,
                                  )
                                : recordingState.buildRecordingBar(context);
                            return KeyedSubtree(
                              key: ValueKey<int>(tick),
                              child: bar,
                            );
                          },
                        )
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

                // Trailing 48×48 stack: mic always mounted; text send fades on top (Phase 0).
                // CLAUDE.md: never swap mic/send as Row siblings — unmount dismisses keyboard.
                FocusGuardArea(
                  id: 'composer_trailing',
                  child: _buildTrailingSlot(context),
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

/// Tap-only trailing send so [RecordingController]'s long-press reaches the mic below.
/// [IconButton] would win the gesture arena and block hold-to-record when draft text is visible.
class _ComposerTapSendOverlay extends StatefulWidget {
  const _ComposerTapSendOverlay({
    required this.enabled,
    required this.onTap,
    required this.tooltip,
    required this.semanticsLabel,
  });

  final bool enabled;
  final VoidCallback onTap;
  final String tooltip;
  final String semanticsLabel;

  @override
  State<_ComposerTapSendOverlay> createState() => _ComposerTapSendOverlayState();
}

class _ComposerTapSendOverlayState extends State<_ComposerTapSendOverlay> {
  static const Duration _kTapMaxDuration = Duration(milliseconds: 300);
  static const double _kTapMaxMovement = 18.0;

  DateTime? _downTime;
  Offset? _downPosition;

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled) return;
    _downTime = DateTime.now();
    _downPosition = event.position;
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!widget.enabled || _downTime == null || _downPosition == null) return;
    final duration = DateTime.now().difference(_downTime!);
    final moved = (event.position - _downPosition!).distance;
    _downTime = null;
    _downPosition = null;
    if (duration <= _kTapMaxDuration && moved <= _kTapMaxMovement) {
      widget.onTap();
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _downTime = null;
    _downPosition = null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: Tooltip(
        message: widget.tooltip,
        child: Semantics(
          button: true,
          label: widget.semanticsLabel,
          excludeSemantics: true,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
