import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:typed_data';

import '../../models/message_model.dart';
import '../../providers/conversations_provider.dart';
import '../../providers/messaging_provider.dart';
import '../../theme/rpg_theme.dart';
import '../chat_action_tiles.dart';
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
  bool _hasText = false;
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
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) {
        setState(() => _hasText = has);
      }
      if (has) {
        _typingDebounceTimer?.cancel();
        _typingDebounceTimer = Timer(const Duration(milliseconds: 300), () {
          if (mounted) context.read<MessagingProvider>().emitTyping();
        });
      }
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
    if (mounted && _focusNode.canRequestFocus) {
      _focusNode.requestFocus();
    }
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
    setState(() => _isSendingVoice = true);
    try {
      final messaging =
          Provider.of<MessagingProvider>(context, listen: false);
      final convs = Provider.of<ConversationsProvider>(context, listen: false);
      final conversationId = convs.activeConversationId;

      if (conversationId == null) {
        if (!mounted) return;
        showTopSnackBar(context, 'No active conversation');
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
      showTopSnackBar(context, 'Failed to send voice message');
      debugPrint('Send voice error: $e');
    } finally {
      if (mounted) {
        setState(() => _isSendingVoice = false);
      }
    }
  }

  String _formatTimer(int seconds) {
    if (seconds >= 86400) return '${seconds ~/ 86400}d';
    if (seconds >= 3600) return '${seconds ~/ 3600}h';
    if (seconds >= 60) return '${seconds ~/ 60}m';
    return '${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final messaging = context.watch<MessagingProvider>();
    final convs = context.read<ConversationsProvider>();
    final replyingTo = messaging.replyingToMessage;

    if (replyingTo != null && _lastReplyingTo != replyingTo) {
      _lastReplyingTo = replyingTo;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _focusNode.canRequestFocus) {
          _focusNode.requestFocus();
        }
      });
    } else if (replyingTo == null) {
      _lastReplyingTo = null;
    }

    final activeTimer = convs.conversationDisappearingTimer;
    final isDark = RpgTheme.isDark(context);
    final colorScheme = Theme.of(context).colorScheme;
    final fc = FireplaceColors.of(context);

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Reply preview
          if (replyingTo != null)
            ReplyPreviewBar(
              message: replyingTo,
              onDismiss: () => messaging.clearReplyingTo(),
            ),

          // Active timer indicator
          if (activeTimer != null)
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              color: isDark
                  ? Colors.orange.withValues(alpha: 0.15)
                  : Colors.orange.withValues(alpha: 0.1),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.timer_outlined,
                    size: 14,
                    color: isDark
                        ? Colors.orange.shade300
                        : Colors.orange.shade700,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Disappearing messages: ${_formatTimer(activeTimer)}',
                    style: RpgTheme.bodyFont(
                      fontSize: 11,
                      color: isDark
                          ? Colors.orange.shade300
                          : Colors.orange.shade700,
                    ),
                  ),
                ],
              ),
            ),

          // Input row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                      : TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          style: RpgTheme.bodyFont(
                            fontSize: 14,
                            color: colorScheme.onSurface,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Type a message...',
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
                          maxLines: null,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                        ),
                ),

                const SizedBox(width: 4),

                // RecordingController is ALWAYS in the widget tree here.
                // CLAUDE.md: "mic must stay in widget tree — GestureDetector unmounts -> no events."
                // It renders: spinner | send button | mic button — based on its props.
                RecordingController(
                  key: _recordingKey,
                  onVoiceSent: _handleVoiceSent,
                  onRecordingStateChanged: _onRecordingStateChanged,
                  hasText: _hasText,
                  isSendingVoice: _isSendingVoice,
                  onSend: _send,
                ),
              ],
            ),
          ),

          // Action tiles with slide animation
          SizeTransition(
            sizeFactor: _actionPanelAnimation,
            axisAlignment: -1.0,
            child: const ChatActionTiles(),
          ),
        ],
      ),
    );
  }
}
