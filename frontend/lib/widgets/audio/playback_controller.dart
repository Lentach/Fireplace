import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../models/message_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/media_crypto_service.dart';
import '../../services/voice_audio_coordinator.dart';
import '../top_snackbar.dart';
import 'voice_player.dart';

/// Manages voice playback lifecycle: loading, caching, play/pause, seek, speed.
///
/// Playback runs through the [VoicePlayer] abstraction: just_audio on native,
/// the Web Audio API on web (no MediaSession ⇒ no iOS media-control card).
/// Exposes state via callbacks and boolean fields so the parent widget can
/// drive the UI without caring about the player internals.
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

  /// Test seam: inject a fake [VoicePlayer]. Defaults to the platform player.
  final VoicePlayer Function()? playerFactory;

  const PlaybackController({
    super.key,
    required this.message,
    required this.builder,
    this.playerFactory,
  });

  static Future<int> clearAudioCache() async {
    if (kIsWeb) return 0;
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/audio_cache');
    if (!cacheDir.existsSync()) return 0;

    var deleted = 0;
    await for (final entity in cacheDir.list(recursive: true)) {
      if (entity is File) deleted++;
    }
    await cacheDir.delete(recursive: true);
    return deleted;
  }

  @override
  State<PlaybackController> createState() => _PlaybackControllerState();
}

class _PlaybackControllerState extends State<PlaybackController>
    implements ManagedAudioPlayback {
  late final VoicePlayer _player =
      widget.playerFactory?.call() ?? createVoicePlayer();
  bool _isPlaying = false;
  bool _isLoading = false;
  bool _loadCancelled = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _playbackSpeed = 1.0;
  String? _cachedFilePath;

  @override
  void pauseForCoordinator() => _player.pause().ignore();

  /// Duration from message metadata (for display before audio loads).
  Duration get _messageDuration =>
      Duration(seconds: widget.message.mediaDuration ?? 0);

  /// Effective duration: from player when loaded, else from message metadata.
  Duration get _displayDuration =>
      _duration.inMilliseconds > 0 ? _duration : _messageDuration;

  @override
  void initState() {
    super.initState();

    _player.stateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state.completed ? false : state.playing;
      });
      if (state.playing && !state.completed) {
        VoiceAudioCoordinator.instance.onStartedPlaying(this);
      }
      if (state.completed) {
        VoiceAudioCoordinator.instance.onStoppedPlaying(this);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _player.stop();
            _player.seek(Duration.zero);
          }
        });
      }
    });

    _player.positionStream.listen((position) {
      if (mounted) {
        setState(() {
          _position = position;
        });
      }
    });

    _player.durationStream.listen((duration) {
      if (mounted && duration != null) {
        setState(() {
          _duration = duration;
        });
      }
    });
  }

  @override
  void dispose() {
    VoiceAudioCoordinator.instance.onStoppedPlaying(this);
    _player.dispose();
    super.dispose();
  }

  bool _isExpired() {
    if (widget.message.expiresAt == null) return false;
    return widget.message.expiresAt!.isBefore(DateTime.now());
  }

  Future<void> _togglePlayPause() async {
    if (_isLoading) {
      _loadCancelled = true;
      _player.stop();
      setState(() => _isLoading = false);
      return;
    }
    if (_isPlaying) {
      await _player.pause();
    } else {
      if (_player.duration == null) {
        await _loadAndPlayAudio();
      } else {
        await _player.play();
      }
    }
  }

  Future<void> _loadAndPlayAudio() async {
    if (_isExpired()) {
      if (mounted) {
        showTopSnackBar(
            context, AppLocalizations.of(context).snackbarAudioNoLongerAvailable);
      }
      return;
    }

    final mediaUrl = widget.message.mediaUrl;
    if (mediaUrl == null || mediaUrl.isEmpty) {
      throw Exception('No media URL');
    }
    final token = context.read<AuthProvider>().token ?? '';

    _loadCancelled = false;
    setState(() {
      _isLoading = true;
    });

    try {
      if (kIsWeb) {
        // Web Audio decodes raw bytes (no HTML <audio> element ⇒ no
        // MediaSession). Fetch the bytes ourselves (encrypted media already
        // does), decrypt when keyed, and hand the plaintext to the player.
        // The legacy unencrypted (Cloudinary) case fetches the same way, which
        // also avoids the CORS wall a bare fetch+decode would hit.
        final raw = await ApiService(
          baseUrl: AppConfig.baseUrl,
        ).fetchMediaBytes(mediaUrl, token);
        if (raw.length > MediaCryptoService.maxBytes) {
          throw Exception('Audio too large');
        }
        final mk = widget.message.mediaKey;
        final mi = widget.message.mediaIv;
        final Uint8List plain = (mk != null && mi != null)
            ? await MediaCryptoService().decrypt(Uint8List.fromList(raw), mk, mi)
            : Uint8List.fromList(raw);
        await _player.setAudioBytes(plain);
      } else {
        _cachedFilePath = await _getCachedFilePath();

        if (_cachedFilePath != null && File(_cachedFilePath!).existsSync()) {
          await _player.setFilePath(_cachedFilePath!);
        } else {
          final path = await _downloadAndCache(mediaUrl, token);
          _cachedFilePath = path;
          await _player.setFilePath(path);
        }
      }

      if (mounted) setState(() => _isLoading = false);
      if (_loadCancelled || !mounted) return;
      await _player.play();
    } catch (e) {
      debugPrint('Audio load error: $e');
      if (mounted) {
        showTopSnackBar(
            context, AppLocalizations.of(context).snackbarFailedToLoadAudio);
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
    final audioFile = File('$cachePath/${widget.message.id}.audio');
    if (audioFile.existsSync()) return audioFile.path;
    final legacy = File('$cachePath/${widget.message.id}.m4a');
    if (legacy.existsSync()) return legacy.path;
    return null;
  }

  Future<String> _downloadAndCache(String url, String token) async {
    final dir = await getApplicationDocumentsDirectory();
    final cachePath = '${dir.path}/audio_cache';
    await Directory(cachePath).create(recursive: true);

    final file = File('$cachePath/${widget.message.id}.audio');

    final raw = await ApiService(baseUrl: AppConfig.baseUrl).fetchMediaBytes(
      url,
      token,
    );
    if (raw.length > MediaCryptoService.maxBytes) {
      throw Exception('Audio too large');
    }

    List<int> bytes = raw;
    final mk = widget.message.mediaKey;
    final mi = widget.message.mediaIv;
    if (mk != null && mi != null) {
      bytes = await MediaCryptoService().decrypt(
        Uint8List.fromList(bytes),
        mk,
        mi,
      );
    }

    await file.writeAsBytes(bytes);
    return file.path;
  }

  void _seekFromWaveformPosition(double localX, double width) {
    if (width <= 0 || _displayDuration.inMilliseconds <= 0) return;
    final progress = (localX / width).clamp(0.0, 1.0);
    final newPosition = Duration(
      milliseconds: (progress * _displayDuration.inMilliseconds).round(),
    );
    _player.seek(newPosition);
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
      _player.setSpeed(_playbackSpeed);
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
