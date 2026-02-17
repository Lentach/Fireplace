import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../models/message_model.dart';
import '../theme/rpg_theme.dart';
import 'top_snackbar.dart';

class VoiceMessageBubble extends StatefulWidget {
  final MessageModel message;
  final bool isMine;

  const VoiceMessageBubble({
    super.key,
    required this.message,
    required this.isMine,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  bool _isLoading = false;
  bool _loadCancelled = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _playbackSpeed = 1.0;
  String? _cachedFilePath;

  /// Duration from message metadata (for display before audio loads)
  Duration get _messageDuration =>
      Duration(seconds: widget.message.mediaDuration ?? 0);

  /// Effective duration: from player when loaded, else from message
  Duration get _displayDuration =>
      _duration.inMilliseconds > 0 ? _duration : _messageDuration;

  @override
  void initState() {
    super.initState();
    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        final completed = state.processingState == ProcessingState.completed;
        setState(() {
          _isPlaying = completed ? false : state.playing;
        });
        if (completed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _audioPlayer.stop();
              _audioPlayer.seek(Duration.zero);
            }
          });
        }
      }
    });

    _audioPlayer.positionStream.listen((position) {
      if (mounted) {
        setState(() {
          _position = position;
        });
      }
    });

    _audioPlayer.durationStream.listen((duration) {
      if (mounted && duration != null) {
        setState(() {
          _duration = duration;
        });
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _togglePlayPause() async {
    if (_isLoading) {
      _loadCancelled = true;
      _audioPlayer.stop();
      setState(() => _isLoading = false);
      return;
    }
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      // Check if audio is loaded
      if (_audioPlayer.duration == null) {
        await _loadAndPlayAudio();
      } else {
        await _audioPlayer.play();
      }
    }
  }

  bool _isExpired() {
    if (widget.message.expiresAt == null) return false;
    return widget.message.expiresAt!.isBefore(DateTime.now());
  }

  Future<void> _loadAndPlayAudio() async {
    // Check if message expired
    if (_isExpired()) {
      if (mounted) showTopSnackBar(context, 'Audio no longer available');
      return;
    }

    final mediaUrl = widget.message.mediaUrl;
    if (mediaUrl == null || mediaUrl.isEmpty) {
      throw Exception('No media URL');
    }

    _loadCancelled = false;
    setState(() {
      _isLoading = true;
    });

    try {
      if (kIsWeb) {
        // Web: play directly from URL (no file cache)
        await _audioPlayer.setUrl(mediaUrl);
      } else {
        // Native: check cache, download if needed
        _cachedFilePath = await _getCachedFilePath();

        if (_cachedFilePath != null && File(_cachedFilePath!).existsSync()) {
          await _audioPlayer.setFilePath(_cachedFilePath!);
        } else {
          final path = await _downloadAndCache(mediaUrl);
          _cachedFilePath = path;
          await _audioPlayer.setFilePath(path);
        }
      }

      if (mounted) setState(() => _isLoading = false);
      if (_loadCancelled || !mounted) return;
      await _audioPlayer.play();
    } catch (e) {
      debugPrint('Audio load error: $e');
      if (mounted) showTopSnackBar(context, 'Failed to load audio');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<String?> _getCachedFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    final cachePath = '${dir.path}/audio_cache';
    final file = File('$cachePath/${widget.message.id}.m4a');
    return file.existsSync() ? file.path : null;
  }

  Future<String> _downloadAndCache(String url) async {
    final dir = await getApplicationDocumentsDirectory();
    final cachePath = '${dir.path}/audio_cache';
    await Directory(cachePath).create(recursive: true);

    final file = File('$cachePath/${widget.message.id}.m4a');

    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      await file.writeAsBytes(response.bodyBytes);
      return file.path;
    } else {
      throw Exception('Failed to download audio: ${response.statusCode}');
    }
  }

  void _seekFromWaveformPosition(double localX, double width) {
    if (width <= 0 || _displayDuration.inMilliseconds <= 0) return;
    final progress = (localX / width).clamp(0.0, 1.0);
    final newPosition = Duration(
      milliseconds: (progress * _displayDuration.inMilliseconds).round(),
    );
    _audioPlayer.seek(newPosition);
  }

  void _toggleSpeed() {
    setState(() {
      if (_playbackSpeed == 1.0) {
        _playbackSpeed = 1.5;
      } else if (_playbackSpeed == 1.5) {
        _playbackSpeed = 2.0;
      } else {
        _playbackSpeed = 1.0;
      }
      _audioPlayer.setSpeed(_playbackSpeed);
    });
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String? _getTimerText() {
    if (widget.message.expiresAt == null) return null;
    final now = DateTime.now();
    final remaining = widget.message.expiresAt!.difference(now);
    if (remaining.isNegative) return null;
    if (remaining.inHours > 0) return '${remaining.inHours}h';
    if (remaining.inMinutes > 0) return '${remaining.inMinutes}m';
    return '${remaining.inSeconds}s';
  }

  Widget _buildDeliveryIcon() {
    if (!widget.isMine) return const SizedBox.shrink();
    if (widget.message.deliveryStatus == MessageDeliveryStatus.failed) {
      return const Icon(Icons.error, size: 12, color: Colors.red);
    }
    IconData icon;
    switch (widget.message.deliveryStatus) {
      case MessageDeliveryStatus.sending:
        icon = Icons.access_time;
        break;
      case MessageDeliveryStatus.sent:
      case MessageDeliveryStatus.delivered:
        icon = Icons.check;
        break;
      case MessageDeliveryStatus.read:
        icon = Icons.done_all;
        break;
      default:
        icon = Icons.check;
    }
    const Color sendingSentColor = Color(0xFFE0E0E0);
    const Color readColor = Color(0xFF64B5F6);
    final color = widget.message.deliveryStatus == MessageDeliveryStatus.read
        ? readColor
        : sendingSentColor;
    return Icon(icon, size: 12, color: color);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = RpgTheme.isDark(context);
    final bubbleColor = widget.isMine
        ? (isDark ? RpgTheme.mineMsgBg : RpgTheme.mineMsgBgLight)
        : (isDark ? RpgTheme.theirsMsgBg : RpgTheme.theirsMsgBgLight);
    final borderColor = widget.isMine
        ? (isDark ? RpgTheme.accentDark : RpgTheme.primaryLight)
        : (isDark ? RpgTheme.borderDark : RpgTheme.primaryLight);

    return Align(
      alignment: widget.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.6,
        ),
        margin: EdgeInsets.only(
          left: widget.isMine ? 48 : 0,
          right: widget.isMine ? 0 : 48,
          bottom: 4,
        ),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(16),
          border: Border(
            left: BorderSide(color: borderColor, width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Playback controls row
            Row(
              children: [
                // Play/Pause (or loading with tap-to-cancel)
                _isLoading
                    ? GestureDetector(
                        onTap: _togglePlayPause,
                        child: const SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                        onPressed: _isExpired() ? null : _togglePlayPause,
                        iconSize: 32,
                        color: _isExpired() ? Colors.grey : null,
                      ),

                const SizedBox(width: 8),

                // Waveform: scrubbable (tap/drag to seek), Telegram-style
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      return GestureDetector(
                        onTapDown: _displayDuration.inMilliseconds > 0
                            ? (d) => _seekFromWaveformPosition(d.localPosition.dx, w)
                            : null,
                        onHorizontalDragUpdate: _displayDuration.inMilliseconds > 0
                            ? (d) => _seekFromWaveformPosition(d.localPosition.dx, w)
                            : null,
                        behavior: HitTestBehavior.opaque,
                        child: _displayDuration.inMilliseconds > 0
                            ? CustomPaint(
                                painter: _WaveformPainter(
                                  progress: _position.inMilliseconds /
                                      _displayDuration.inMilliseconds,
                                  color: borderColor,
                                  messageId: widget.message.id,
                                ),
                                size: Size(w, 28),
                              )
                            : Container(
                                height: 28,
                                color: Colors.grey.withValues(alpha: 0.1),
                              ),
                      );
                    },
                  ),
                ),

                const SizedBox(width: 4),

                // Time: position / duration (compact)
                Text(
                  '${_formatDuration(_position)}/${_formatDuration(_displayDuration)}',
                  style: const TextStyle(fontSize: 10),
                ),

                const SizedBox(width: 6),

                // Speed toggle
                InkWell(
                  onTap: _toggleSpeed,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(color: borderColor),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_playbackSpeed}x',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 4),
            Align(
              alignment: Alignment.bottomRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(widget.message.createdAt),
                    style: RpgTheme.bodyFont(
                      fontSize: 10,
                      color: isDark ? RpgTheme.timeColorDark : RpgTheme.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(width: 4),
                  _buildDeliveryIcon(),
                  if (_getTimerText() != null) ...[
                    const SizedBox(width: 6),
                    Icon(
                      Icons.timer_outlined,
                      size: 10,
                      color: isDark ? RpgTheme.timeColorDark : RpgTheme.textSecondaryLight,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      _getTimerText()!,
                      style: RpgTheme.bodyFont(
                        fontSize: 10,
                        color: isDark ? RpgTheme.timeColorDark : RpgTheme.textSecondaryLight,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double progress;
  final Color color;
  final int messageId; // seed for per-message waveform variation

  _WaveformPainter({
    required this.progress,
    required this.color,
    required this.messageId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final paintFilled = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final barCount = 50;
    final barWidth = size.width / barCount;
    final seed = messageId.abs() % 1000; // per-message variation (id can be negative for temp)

    for (int i = 0; i < barCount; i++) {
      // Wave-like pattern: multiple overlapping sine waves for natural variation
      final t = (i + seed * 0.1) * 0.35;
      final wave1 = math.sin(t) * 0.4;
      final wave2 = math.sin(t * 2.3 + 1.5) * 0.2;
      final wave3 = math.sin(t * 0.7 + 3) * 0.15;
      final heightFactor = (0.5 + wave1 + wave2 + wave3).clamp(0.15, 0.95);
      final barHeight = size.height * heightFactor;

      final x = i * barWidth + barWidth / 2;
      final y1 = (size.height - barHeight) / 2;
      final y2 = y1 + barHeight;

      final currentPaint = (i / barCount) <= progress ? paintFilled : paint;
      canvas.drawLine(Offset(x, y1), Offset(x, y2), currentPaint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.messageId != messageId;
  }
}
