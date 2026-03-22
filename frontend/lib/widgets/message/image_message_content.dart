import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../l10n/app_localizations.dart';
import '../../models/message_model.dart';
import '../../services/media_crypto_service.dart';
import '../../theme/rpg_theme.dart';

/// IMAGE message: fetch URL, optional AES-GCM decrypt, display with fullscreen viewer.
class ImageMessageContent extends StatefulWidget {
  final MessageModel message;

  const ImageMessageContent({
    super.key,
    required this.message,
  });

  @override
  State<ImageMessageContent> createState() => _ImageMessageContentState();
}

class _ImageMessageContentState extends State<ImageMessageContent> {
  late Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadDecryptedBytes();
  }

  @override
  void didUpdateWidget(ImageMessageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id ||
        oldWidget.message.mediaUrl != widget.message.mediaUrl ||
        oldWidget.message.mediaKey != widget.message.mediaKey ||
        oldWidget.message.mediaIv != widget.message.mediaIv) {
      _future = _loadDecryptedBytes();
    }
  }

  Future<Uint8List?> _loadDecryptedBytes() async {
    final url = widget.message.mediaUrl;
    if (url == null || url.isEmpty) return null;

    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch media');
    }
    final raw = response.bodyBytes;
    if (raw.length > MediaCryptoService.maxBytes) {
      throw Exception('Media too large');
    }

    final key = widget.message.mediaKey;
    final iv = widget.message.mediaIv;
    if (key != null && iv != null) {
      final service = MediaCryptoService();
      return service.decrypt(Uint8List.fromList(raw), key, iv);
    }
    return Uint8List.fromList(raw);
  }

  void _showFullscreen(BuildContext context, Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(
            width: 200,
            height: 150,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (snap.hasError || snap.data == null) {
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              AppLocalizations.of(context).imageFailedToLoad,
              style: RpgTheme.bodyFont(fontSize: 12, color: Colors.red),
            ),
          );
        }
        final bytes = snap.data!;
        return GestureDetector(
          onTap: () => _showFullscreen(context, bytes),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
              ),
            ),
          ),
        );
      },
    );
  }
}
