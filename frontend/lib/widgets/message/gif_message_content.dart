import 'package:flutter/material.dart';

/// Content widget for GIF message type with fullscreen viewer on tap.
class GifMessageContent extends StatelessWidget {
  final String? mediaUrl;

  const GifMessageContent({
    super.key,
    required this.mediaUrl,
  });

  void _showFullscreen(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Image.network(url, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (mediaUrl == null) {
      return const SizedBox(
        width: 150,
        height: 150,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return GestureDetector(
      onTap: () => _showFullscreen(context, mediaUrl!),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            mediaUrl!,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const SizedBox(
                width: 150,
                height: 150,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            },
            errorBuilder: (context, error, stackTrace) => Container(
              width: 150,
              height: 150,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.broken_image, size: 48),
            ),
          ),
        ),
      ),
    );
  }
}
