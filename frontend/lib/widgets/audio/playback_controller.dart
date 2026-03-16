import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../../models/message_model.dart';
import '../top_snackbar.dart';

/// Manages AudioPlayer lifecycle: loading, caching, play/pause, seek, speed.
///
/// Exposes state via callbacks and boolean fields so the parent widget can
/// drive the UI without caring about AudioPlayer internals.
class PlaybackController extends StatefulWidget {
  final MessageModel message;

  /// Called whenever playback state changes (isPlaying, isLoading, position, duration, speed).
  final Widget Function(
    BuildContext context,
    bool isPlaying,
    bool isLoading,
    Duration position,
    Duration duration,
    double speed,
    VoidCallback togglePlayPause,
    void Function(double localX, double width) seekFromWaveform,
    VoidCallback toggleSpeed,
  ) builder;

  const PlaybackController({
    super.key,
    required this.message,
    required this.builder,
  });

  @override
  State<PlaybackController> createState() => _PlaybackControllerState();
}

class _PlaybackControllerState extends State<PlaybackController> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  bool _isLoading = false;
  bool _loadCancelled = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _playbackSpeed = 1.0;
  String? _cachedFilePath;

  /// Duration from message metadata (for display before audio loads).
  Duration get _messageDuration =>
      Duration(seconds: widget.message.mediaDuration ?? 0);

  /// Effective duration: from player when loaded, else from message metadata.
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

  bool _isExpired() {
    if (widget.message.expiresAt == null) return false;
    return widget.message.expiresAt!.isBefore(DateTime.now());
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
      if (_audioPlayer.duration == null) {
        await _loadAndPlayAudio();
      } else {
        await _audioPlayer.play();
      }
    }
  }

  Future<void> _loadAndPlayAudio() async {
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
        // Web: play directly from URL (no file cache).
        await _audioPlayer.setUrl(mediaUrl);
      } else {
        // Native: check cache, download if needed.
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

  @override
  Widget build(BuildContext context) {
    return widget.builder(
      context,
      _isPlaying,
      _isLoading,
      _position,
      _displayDuration,
      _playbackSpeed,
      _togglePlayPause,
      _seekFromWaveformPosition,
      _toggleSpeed,
    );
  }
}
