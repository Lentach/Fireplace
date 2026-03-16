import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rpg_theme.dart';
import '../../utils/download_utils_web.dart'
    if (dart.library.io) '../../utils/download_utils_io.dart' as download_utils;
import '../top_snackbar.dart';

/// Content widget for FILE/document message type.
class FileMessageContent extends StatelessWidget {
  final String? mediaUrl;
  final String content;
  final Color textColor;

  const FileMessageContent({
    super.key,
    required this.mediaUrl,
    required this.content,
    required this.textColor,
  });

  Future<void> _downloadDocument(BuildContext context, String url, String filename) async {
    final l10n = AppLocalizations.of(context);
    try {
      await download_utils.downloadFile(url, filename);
      if (context.mounted) {
        showTopSnackBar(context, l10n.documentDownloaded);
      }
    } catch (_) {
      if (context.mounted) {
        showTopSnackBar(context, l10n.documentDownloadFailed, backgroundColor: Colors.red);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (mediaUrl == null) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: () {
        final l10n = AppLocalizations.of(context);
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.documentDownloadConfirmTitle),
            content: Text(l10n.documentDownloadConfirmMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _downloadDocument(
                    context,
                    mediaUrl!,
                    content.isNotEmpty ? content : 'document',
                  );
                },
                child: Text(l10n.download),
              ),
            ],
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description, color: textColor, size: 24),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                content.isNotEmpty ? content : 'Document',
                style: RpgTheme.bodyFont(fontSize: 14, color: textColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
