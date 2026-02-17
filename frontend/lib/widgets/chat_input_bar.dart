import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/chat_provider.dart';
import '../theme/rpg_theme.dart';
import 'chat_action_tiles.dart';
import 'top_snackbar.dart';

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({super.key});

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar>
    with TickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;
  bool _showActionPanel = false;
  late final AnimationController _actionPanelController;
  late final Animation<double> _actionPanelAnimation;

  // Voice recording state
  bool _isRecording = false;
  bool _isSendingVoice = false;
  AudioRecorder? _audioRecorder;
  String? _recordingPath;
  Timer? _recordingTimer;
  DateTime? _recordingStartTime;
  ValueNotifier<int>? _recordingSecondsNotifier; // tick-based timer for recording duration display

  // Slide-to-cancel: drag mic TO trash to cancel (release over trash zone)
  static const double _trashOpenThresholdPx = 60.0;  // trash "opens" (scales) when mic this close

  double _getCancelThreshold(BuildContext context) =>
      MediaQuery.of(context).size.width * 0.5; // mic travels half the screen to reach trash
  double _cancelDragOffset = 0.0;
  double _dragStartX = 0.0; // global X when drag started
  bool _showTrashIcon = false;
  bool _canceledBySlide = false; // true when user slid to cancel (do not send on release)

  // Pulsing red dot animation
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) {
        setState(() => _hasText = has);
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
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _actionPanelController.dispose();
    _pulseController.dispose();
    _recordingTimer?.cancel();
    _recordingSecondsNotifier?.dispose();
    _audioRecorder?.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final chat = context.read<ChatProvider>();
    final expiresIn = chat.conversationDisappearingTimer;
    chat.sendMessage(text, expiresIn: expiresIn);

    _controller.clear();
    // Keep focus immediately - prevents keyboard from closing on mobile
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

  Future<void> _checkMicPermission() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final status = await Permission.microphone.request();
      if (status.isDenied || status.isPermanentlyDenied) {
        if (!mounted) return;
        showTopSnackBar(context, 'Microphone permission required');
        throw Exception('Permission denied');
      }
    }
    // Web: permission handled by browser automatically
  }


  Future<void> _startRecording() async {
    try {
      await _checkMicPermission();

      _audioRecorder = AudioRecorder();
      if (kIsWeb) {
        _recordingPath = 'voice_${DateTime.now().millisecondsSinceEpoch}.wav';
      } else {
        final tempDir = await getTemporaryDirectory();
        _recordingPath = '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      }

      final hasPermission = await _audioRecorder!.hasPermission();
      if (!hasPermission) {
        if (!mounted) return;
        showTopSnackBar(context, 'Microphone permission denied');
        return;
      }

      await _audioRecorder!.start(
        RecordConfig(
          encoder: kIsWeb ? AudioEncoder.wav : AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: _recordingPath!,
      );

      _recordingStartTime = DateTime.now();
      _recordingSecondsNotifier = ValueNotifier(0);
      setState(() {
        _isRecording = true;
        _cancelDragOffset = 0.0;
        _showTrashIcon = false;
        _canceledBySlide = false;
      });

      // Timer: tick every second, update notifier + 120s auto-stop
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || _recordingStartTime == null) return;
        final elapsed = DateTime.now().difference(_recordingStartTime!).inSeconds;
        _recordingSecondsNotifier?.value = elapsed;
        if (elapsed >= 120) _stopRecording();
      });
    } catch (e) {
      if (!mounted) return;
      showTopSnackBar(context, 'Failed to start recording');
      debugPrint('Recording error: $e');
    }
  }

  Future<void> _stopRecording() async {
    if (_audioRecorder == null || !_isRecording) return;

    _recordingTimer?.cancel();
    _recordingTimer = null;
    _recordingSecondsNotifier?.dispose();
    _recordingSecondsNotifier = null;

    final path = await _audioRecorder!.stop();
    await _audioRecorder!.dispose();
    _audioRecorder = null;

    setState(() {
      _isRecording = false;
      _cancelDragOffset = 0.0;
      _showTrashIcon = false;
    });

    // Use actual elapsed duration for send (timer display may lag on last tick)
    final durationSeconds = _recordingStartTime != null
        ? DateTime.now().difference(_recordingStartTime!).inSeconds
        : 0;
    _recordingStartTime = null;

    // Check duration
    if (durationSeconds < 1) {
      if (!kIsWeb && path != null) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      if (!mounted) return;
      showTopSnackBar(context, 'Hold longer to record voice message');
      setState(() {
        _recordingPath = null;
      });
      return;
    }

    // Send voice message
    if (path != null) {
      if (kIsWeb) {
        // Web: path is blob URL, fetch bytes
        try {
          final response = await http.get(Uri.parse(path));
          if (response.statusCode == 200) {
            await _sendVoiceMessage(duration: durationSeconds, audioBytes: response.bodyBytes);
          } else {
            if (!mounted) return;
            showTopSnackBar(context, 'Failed to read recording');
          }
        } catch (e) {
          if (!mounted) return;
          showTopSnackBar(context, 'Failed to send voice message');
          debugPrint('Send voice error: $e');
        }
      } else {
        final file = File(path);
        if (await file.exists()) {
          await _sendVoiceMessage(duration: durationSeconds, localAudioPath: path);
        }
      }
    }

    setState(() {
      _recordingPath = null;
    });
  }

  Future<void> _cancelRecording() async {
    if (_audioRecorder == null || !_isRecording) return;

    _canceledBySlide = true;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _recordingSecondsNotifier?.dispose();
    _recordingSecondsNotifier = null;
    _recordingStartTime = null;

    await _audioRecorder!.stop();
    await _audioRecorder!.dispose();
    _audioRecorder = null;

    // Delete temp file (native only; web uses blob)
    if (!kIsWeb && _recordingPath != null) {
      try {
        final file = File(_recordingPath!);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }

    setState(() {
      _isRecording = false;
      _recordingPath = null;
      _cancelDragOffset = 0.0;
      _showTrashIcon = false;
    });
  }

  Future<void> _sendVoiceMessage({
    required int duration,
    String? localAudioPath,
    Uint8List? audioBytes,
  }) async {
    setState(() {
      _isSendingVoice = true;
    });

    try {
      final chat = Provider.of<ChatProvider>(context, listen: false);
      final conversationId = chat.activeConversationId;

      if (conversationId == null) {
        if (!mounted) return;
        showTopSnackBar(context, 'No active conversation');
        return;
      }

      // Get recipientId from conversation
      final conversation = chat.conversations.firstWhere(
        (c) => c.id == conversationId,
      );
      final recipientId = conversation.userOne.id == chat.currentUserId
          ? conversation.userTwo.id
          : conversation.userOne.id;

      await chat.sendVoiceMessage(
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
        setState(() {
          _isSendingVoice = false;
        });
      }
    }
  }

  void _onRecordingDragStart(double startX) {
    _dragStartX = startX;
    _cancelDragOffset = 0.0;
  }

  void _onRecordingDragUpdate(double currentX) {
    if (!_isRecording) return;

    setState(() {
      // Delta in screen pixels (negative = slid left)
      _cancelDragOffset = currentX - _dragStartX;

      // Show trash when sliding left (user sees drop target)
      if (_cancelDragOffset < -20) {
        _showTrashIcon = true;
      } else {
        _showTrashIcon = false;
      }
      // Do NOT cancel during drag – cancel only on release when mic is over trash
    });
  }

  bool _isOverTrash(BuildContext context) =>
      _cancelDragOffset < -_getCancelThreshold(context);

  String _formatTimer(int seconds) {
    if (seconds >= 86400) return '${seconds ~/ 86400}d';
    if (seconds >= 3600) return '${seconds ~/ 3600}h';
    if (seconds >= 60) return '${seconds ~/ 60}m';
    return '${seconds}s';
  }

  String _formatRecordingDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  Widget _buildRecordingBar(BuildContext context) {
    final isDark = RpgTheme.isDark(context);
    final tabBorderColor = isDark ? RpgTheme.tabBorderDark : RpgTheme.tabBorderLight;
    final inputBg = isDark ? RpgTheme.inputBg : RpgTheme.inputBgLight;
    final currentSeconds = _recordingSecondsNotifier?.value ?? 0;

    return Semantics(
      label: 'Recording voice message, ${_formatRecordingDuration(currentSeconds)}. Swipe left to cancel.',
      child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: tabBorderColor),
            color: inputBg,
          ),
      child: Row(
        children: [
          // Trash icon: always visible when dragging left; "opens" (scales) when mic gets close
          if (_showTrashIcon)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: AnimatedScale(
                scale: _cancelDragOffset < -_trashOpenThresholdPx ? 1.25 : 1.0,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                child: Icon(
                  Icons.delete_outline,
                  color: Colors.red,
                  size: 24,
                ),
              ),
            ),

          // Pulsing red dot
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red.withValues(alpha: 0.7 + (_pulseController.value * 0.3)),
                ),
              );
            },
          ),

          const SizedBox(width: 12),

          // Timer (guard: notifier can be null briefly on stop/cancel before setState)
          _recordingSecondsNotifier != null
              ? ValueListenableBuilder<int>(
                  valueListenable: _recordingSecondsNotifier!,
                  builder: (context, seconds, _) => Text(
                    _formatRecordingDuration(seconds),
                    style: RpgTheme.bodyFont(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                )
              : Text(
                  _formatRecordingDuration(0),
                  style: RpgTheme.bodyFont(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),

          const SizedBox(width: 16),

          // "Slide to cancel" text (fades out when dragging)
          Expanded(
            child: Opacity(
              opacity: _showTrashIcon ? 0.0 : 1.0,
              child: Text(
                '⬅ Slide to cancel',
                style: RpgTheme.bodyFont(
                  fontSize: 14,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final activeTimer = chat.conversationDisappearingTimer;
    final isDark = RpgTheme.isDark(context);
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor =
        isDark ? RpgTheme.convItemBorderDark : RpgTheme.convItemBorderLight;
    final inputBg = isDark ? RpgTheme.inputBg : RpgTheme.inputBgLight;
    final tabBorderColor =
        isDark ? RpgTheme.tabBorderDark : RpgTheme.tabBorderLight;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Active timer indicator
          if (activeTimer != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              color: isDark
                  ? Colors.orange.withValues(alpha: 0.15)
                  : Colors.orange.withValues(alpha: 0.1),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.timer_outlined, size: 14,
                    color: isDark ? Colors.orange.shade300 : Colors.orange.shade700),
                  const SizedBox(width: 4),
                  Text(
                    'Disappearing messages: ${_formatTimer(activeTimer)}',
                    style: RpgTheme.bodyFont(
                      fontSize: 11,
                      color: isDark ? Colors.orange.shade300 : Colors.orange.shade700,
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
              border: Border(top: BorderSide(color: borderColor)),
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
                    color: isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight,
                    onPressed: _toggleActionPanel,
                  ),

                // Text field or recording bar
                Expanded(
                  child: _isRecording
                      ? _buildRecordingBar(context)
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
                              borderSide: BorderSide(color: tabBorderColor),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide(color: tabBorderColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide(
                                color: RpgTheme.primaryColor(context),
                                width: 1.5,
                              ),
                            ),
                            filled: true,
                            fillColor: inputBg,
                          ),
                          maxLines: null,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                        ),
                ),

                const SizedBox(width: 4),

                // Mic / Send: keep mic visible during recording so gesture (release, drag) is still received
                if (_isSendingVoice)
                  const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (_hasText && !_isRecording)
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: RpgTheme.primaryColor(context),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded, size: 22),
                      color: Colors.white,
                      onPressed: _send,
                    ),
                  )
                else
                  Transform.translate(
                    offset: Offset(
                      _isRecording
                          ? _cancelDragOffset.clamp(-_getCancelThreshold(context), 0)
                          : 0,
                      0,
                    ),
                    child: GestureDetector(
                      onLongPressStart: (details) {
                        _onRecordingDragStart(details.globalPosition.dx);
                        _startRecording();
                      },
                      onLongPressMoveUpdate: (details) => _onRecordingDragUpdate(details.globalPosition.dx),
                      onLongPressEnd: (_) {
                        if (_isRecording && !_canceledBySlide) {
                          if (_isOverTrash(context)) {
                            _cancelRecording();
                          } else {
                            _stopRecording();
                          }
                        }
                      },
                      onLongPressCancel: () {
                        if (_isRecording && !_canceledBySlide) {
                          if (_isOverTrash(context)) {
                            _cancelRecording();
                          } else {
                            _stopRecording();
                          }
                        }
                      },
                      child: AnimatedScale(
                        scale: _isRecording ? 1.15 : 1.0,
                        duration: const Duration(milliseconds: 150),
                        curve: Curves.easeOut,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Icon(
                            _isRecording ? Icons.mic : Icons.mic_none,
                            size: 22,
                            color: _isRecording
                                ? Colors.red
                                : (isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight),
                          ),
                        ),
                      ),
                    ),
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
