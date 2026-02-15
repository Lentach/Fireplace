import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../models/message_model.dart';
import '../theme/rpg_theme.dart';

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
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _playbackSpeed = 1.0;
  String? _cachedFilePath;

  @override
  void initState() {
    super.initState();
    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
        });
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Audio no longer available')),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Check if cached
      _cachedFilePath = await _getCachedFilePath();

      if (_cachedFilePath != null && File(_cachedFilePath!).existsSync()) {
        // Use cached file
        await _audioPlayer.setFilePath(_cachedFilePath!);
      } else {
        // Download and cache
        if (widget.message.mediaUrl == null) {
          throw Exception('No media URL');
        }

        _cachedFilePath = await _downloadAndCache(widget.message.mediaUrl!);
        await _audioPlayer.setFilePath(_cachedFilePath!);
      }

      await _audioPlayer.play();
    } catch (e) {
      print('Audio load error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load audio')),
        );
      }
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
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: EdgeInsets.only(
          left: widget.isMine ? 48 : 0,
          right: widget.isMine ? 0 : 48,
          bottom: 4,
        ),
        padding: const EdgeInsets.all(12),
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
                // Play/Pause button
                _isLoading
                    ? const SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                        onPressed: _isExpired() ? null : _togglePlayPause,
                        iconSize: 32,
                        color: _isExpired() ? Colors.grey : null,
                      ),

                const SizedBox(width: 8),

                // Waveform with progress
                Expanded(
                  child: _duration.inMilliseconds > 0
                      ? CustomPaint(
                          painter: _WaveformPainter(
                            progress: _position.inMilliseconds / _duration.inMilliseconds,
                            color: borderColor,
                          ),
                          size: const Size(double.infinity, 40),
                        )
                      : Container(
                          height: 40,
                          color: Colors.grey.withOpacity(0.1),
                        ),
                ),

                const SizedBox(width: 8),

                // Speed toggle
                InkWell(
                  onTap: _toggleSpeed,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: borderColor),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_playbackSpeed}x',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Duration slider
            Row(
              children: [
                Text(
                  _formatDuration(_position),
                  style: const TextStyle(fontSize: 12),
                ),
                Expanded(
                  child: Slider(
                    value: _duration.inMilliseconds > 0
                        ? _position.inMilliseconds / _duration.inMilliseconds
                        : 0.0,
                    onChanged: (value) {
                      final newPosition = Duration(
                        milliseconds: (_duration.inMilliseconds * value).round(),
                      );
                      _audioPlayer.seek(newPosition);
                    },
                  ),
                ),
                Text(
                  _formatDuration(_duration),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
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

  _WaveformPainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.3)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final paintFilled = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    // Generate random-looking waveform (in real impl, use actual audio data)
    final barCount = 50;
    final barWidth = size.width / barCount;

    for (int i = 0; i < barCount; i++) {
      // Pseudo-random height based on index (deterministic for same message)
      final heightFactor = ((i * 7) % 10) / 10.0;
      final barHeight = size.height * 0.2 + (size.height * 0.6 * heightFactor);

      final x = i * barWidth + barWidth / 2;
      final y1 = (size.height - barHeight) / 2;
      final y2 = y1 + barHeight;

      // Use filled paint if before progress, else unfilled
      final currentPaint = (i / barCount) <= progress ? paintFilled : paint;

      canvas.drawLine(Offset(x, y1), Offset(x, y2), currentPaint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
