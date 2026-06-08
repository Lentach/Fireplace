import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../models/message_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/media_crypto_service.dart';
import '../../services/voice_audio_coordinator.dart';
import '../../utils/e2e_diag_log.dart';
import '../../utils/audio_blob_url_stub.dart'
    if (dart.library.html) '../../utils/audio_blob_url_web.dart' as audio_blob;
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
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  bool _isLoading = false;
  bool _loadCancelled = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _playbackSpeed = 1.0;
  String? _cachedFilePath;
  String? _webAudioObjectUrl;

  @override
  void pauseForCoordinator() => _audioPlayer.pause().ignore();

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
        if (state.playing && !completed) {
          VoiceAudioCoordinator.instance.onStartedPlaying(this);
        }
        if (completed) {
          VoiceAudioCoordinator.instance.onStoppedPlaying(this);
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
    VoiceAudioCoordinator.instance.onStoppedPlaying(this);
    if (kIsWeb && _webAudioObjectUrl != null) {
      audio_blob.revokeAudioObjectUrl(_webAudioObjectUrl);
    }
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

    // ── TEMP DIAGNOSTICS (voice history) — view in Privacy & Safety → long-press shield ──
    final mk0 = widget.message.mediaKey;
    final mi0 = widget.message.mediaIv;
    E2eDiagLog.add('voice.start', {
      'id': widget.message.id,
      'mine': widget.message.senderId,
      'kIsWeb': kIsWeb,
      'mediaUrl': mediaUrl,
      'resolved': rewriteLoopbackMediaUrl(mediaUrl, AppConfig.baseUrl),
      'baseUrl': AppConfig.baseUrl,
      'hasKey': mk0 != null,
      'hasIv': mi0 != null,
      'durMeta': widget.message.mediaDuration,
      'tokenLen': token.length,
    });
    // ─────────────────────────────────────────────────────────────────────────────────

    _loadCancelled = false;
    setState(() {
      _isLoading = true;
    });

    try {
      if (kIsWeb) {
        final mk = widget.message.mediaKey;
        final mi = widget.message.mediaIv;
        if (mk != null && mi != null) {
          E2eDiagLog.add('voice.web.fetch', {});
          final raw = await ApiService(
            baseUrl: AppConfig.baseUrl,
          ).fetchMediaBytes(mediaUrl, token);
          E2eDiagLog.add('voice.web.fetched', {'bytes': raw.length});
          if (raw.length > MediaCryptoService.maxBytes) {
            throw Exception('Audio too large');
          }
          final plain = await MediaCryptoService().decrypt(
            Uint8List.fromList(raw),
            mk,
            mi,
          );
          E2eDiagLog.add('voice.web.decrypted', {
            'bytes': plain.length,
            'head': plain.take(12).toList(),
          });
          if (_webAudioObjectUrl != null) {
            audio_blob.revokeAudioObjectUrl(_webAudioObjectUrl);
          }
          _webAudioObjectUrl = audio_blob.createAudioObjectUrl(plain);
          final blobUrl = _webAudioObjectUrl;
          E2eDiagLog.add('voice.web.blob', {'url': blobUrl});
          if (blobUrl == null || blobUrl.isEmpty) {
            throw Exception('Could not create audio URL');
          }
          await _audioPlayer.setUrl(blobUrl);
          E2eDiagLog.add('voice.web.setUrl.ok', {
            'durationMs': _audioPlayer.duration?.inMilliseconds,
          });
        } else {
          E2eDiagLog.add('voice.web.noKeys.setUrlDirect', {'mediaUrl': mediaUrl});
          await _audioPlayer.setUrl(mediaUrl);
        }
      } else {
        _cachedFilePath = await _getCachedFilePath();

        if (_cachedFilePath != null && File(_cachedFilePath!).existsSync()) {
          await _audioPlayer.setFilePath(_cachedFilePath!);
        } else {
          final path = await _downloadAndCache(mediaUrl, token);
          _cachedFilePath = path;
          await _audioPlayer.setFilePath(path);
        }
      }

      if (mounted) setState(() => _isLoading = false);
      if (_loadCancelled || !mounted) return;
      await _audioPlayer.play();
      E2eDiagLog.add('voice.play.ok', {});
    } catch (e) {
      E2eDiagLog.add('voice.ERROR', {'error': e.toString()});
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
