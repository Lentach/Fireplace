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
import 'voice_recording_overlay.dart';
import 'top_snackbar.dart';

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
  bool _showActionPanel = false;
  late final AnimationController _actionPanelController;
  late final Animation<double> _actionPanelAnimation;

  // Voice recording state
  bool _isRecording = false;
  bool _isSendingVoice = false;
  AudioRecorder? _audioRecorder;
  String? _recordingPath;
  Timer? _recordingTimer;
  int _recordingDuration = 0; // seconds
  OverlayEntry? _recordingOverlay;

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
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _actionPanelController.dispose();
    _recordingTimer?.cancel();
    _audioRecorder?.dispose();
    _recordingOverlay?.remove();
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

      setState(() {
        _isRecording = true;
        _recordingDuration = 0;
      });

      // Show overlay
      _showRecordingOverlay();

      // Start timer (increment every second)
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            _recordingDuration++;
            if (_recordingDuration >= 120) {
              // Auto-stop at 2 minutes
              _stopRecording();
            } else {
              // Update overlay with new duration
              _updateRecordingOverlay();
            }
          });
        }
      });
    } catch (e) {
      if (!mounted) return;
      showTopSnackBar(context, 'Failed to start recording');
      print('Recording error: $e');
    }
  }

  Future<void> _stopRecording() async {
    if (_audioRecorder == null || !_isRecording) return;

    _recordingTimer?.cancel();
    _recordingTimer = null;

    final path = await _audioRecorder!.stop();
    await _audioRecorder!.dispose();
    _audioRecorder = null;

    _hideRecordingOverlay();

    setState(() {
      _isRecording = false;
    });

    // Check duration
    if (_recordingDuration < 1) {
      if (!kIsWeb && path != null) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      if (!mounted) return;
      showTopSnackBar(context, 'Hold longer to record voice message');
      setState(() {
        _recordingDuration = 0;
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
            await _sendVoiceMessage(duration: _recordingDuration, audioBytes: response.bodyBytes);
          } else {
            if (!mounted) return;
            showTopSnackBar(context, 'Failed to read recording');
          }
        } catch (e) {
          if (!mounted) return;
          showTopSnackBar(context, 'Failed to send voice message');
        }
      } else {
        final file = File(path);
        if (await file.exists()) {
          await _sendVoiceMessage(duration: _recordingDuration, localAudioPath: path);
        }
      }
    }

    setState(() {
      _recordingDuration = 0;
      _recordingPath = null;
    });
  }

  Future<void> _cancelRecording() async {
    if (_audioRecorder == null || !_isRecording) return;

    _recordingTimer?.cancel();
    _recordingTimer = null;

    await _audioRecorder!.stop();
    await _audioRecorder!.dispose();
    _audioRecorder = null;

    _hideRecordingOverlay();

    // Delete temp file (native only; web uses blob)
    if (!kIsWeb && _recordingPath != null) {
      try {
        final file = File(_recordingPath!);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }

    setState(() {
      _isRecording = false;
      _recordingDuration = 0;
      _recordingPath = null;
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
      print('Send voice error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSendingVoice = false;
        });
      }
    }
  }

  void _showRecordingOverlay() {
    _recordingOverlay = OverlayEntry(
      builder: (context) => VoiceRecordingOverlay(
        onSendVoice: (path, duration) {
          // Not used, we handle send in _stopRecording
        },
        onCancel: _cancelRecording,
        recordingDuration: _recordingDuration,
      ),
    );
    Overlay.of(context).insert(_recordingOverlay!);
  }

  void _updateRecordingOverlay() {
    _hideRecordingOverlay();
    _showRecordingOverlay();
  }

  void _hideRecordingOverlay() {
    _recordingOverlay?.remove();
    _recordingOverlay = null;
  }

  String _formatTimer(int seconds) {
    if (seconds >= 86400) return '${seconds ~/ 86400}d';
    if (seconds >= 3600) return '${seconds ~/ 3600}h';
    if (seconds >= 60) return '${seconds ~/ 60}m';
    return '${seconds}s';
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
                // Action panel toggle (arrow down/up)
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

                // Text field
                Expanded(
                  child: TextField(
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

                // Mic / Send toggle (send icon must contrast with primary-colored circle)
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _hasText
                        ? RpgTheme.primaryColor(context)
                        : Colors.transparent,
                  ),
                  child: _isSendingVoice
                      ? const Padding(
                          padding: EdgeInsets.all(12.0),
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : _hasText
                          ? IconButton(
                              icon: const Icon(Icons.send_rounded, size: 22),
                              color: Colors.white,
                              onPressed: _send,
                            )
                          : GestureDetector(
                              onLongPressStart: (_) => _startRecording(),
                              onLongPressEnd: (_) => _stopRecording(),
                              child: IconButton(
                                icon: Icon(
                                  _isRecording ? Icons.mic : Icons.mic_none,
                                  size: 22,
                                ),
                                color: _isRecording
                                    ? Colors.red
                                    : (isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight),
                                onPressed: null, // Disabled, use long-press
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
