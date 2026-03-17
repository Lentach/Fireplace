import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rpg_theme.dart';

/// Content widget for IMAGE message type with fullscreen viewer on tap.
class ImageMessageContent extends StatelessWidget {
  final String? mediaUrl;

  const ImageMessageContent({
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
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  AppLocalizations.of(context).imageFailedToLoad,
                  style: RpgTheme.bodyFont(fontSize: 12, color: Colors.red),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
