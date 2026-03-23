import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../models/message_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/media_crypto_service.dart';
import '../../theme/rpg_theme.dart';
import '../../utils/download_utils_web.dart'
    if (dart.library.io) '../../utils/download_utils_io.dart' as download_utils;
import '../top_snackbar.dart';

/// FILE/document message: legacy direct URL download or fetch+decrypt+save.
class FileMessageContent extends StatefulWidget {
  final MessageModel message;
  final Color textColor;

  const FileMessageContent({
    super.key,
    required this.message,
    required this.textColor,
  });

  @override
  State<FileMessageContent> createState() => _FileMessageContentState();
}

class _FileMessageContentState extends State<FileMessageContent> {
  String get _filename =>
      widget.message.content.isNotEmpty ? widget.message.content : 'document';

  Future<void> _downloadDocument(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final token = context.read<AuthProvider>().token ?? '';
    final url = widget.message.mediaUrl;
    if (url == null || url.isEmpty) return;

    try {
      final key = widget.message.mediaKey;
      final iv = widget.message.mediaIv;
      if (key != null && iv != null) {
        final raw = await ApiService(
          baseUrl: AppConfig.baseUrl,
        ).fetchMediaBytes(url, token);
        if (raw.length > MediaCryptoService.maxBytes) {
          throw Exception('File too large');
        }
        final plain = await MediaCryptoService().decrypt(
          Uint8List.fromList(raw),
          key,
          iv,
        );
        await download_utils.saveBytesAsDownload(plain, _filename);
      } else {
        await download_utils.downloadFile(url, _filename);
      }
      if (context.mounted) {
        showTopSnackBar(context, l10n.documentDownloaded);
      }
    } catch (_) {
      if (context.mounted) {
        showTopSnackBar(
          context,
          l10n.documentDownloadFailed,
          backgroundColor: Colors.red,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.message.mediaUrl == null) {
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
                  _downloadDocument(context);
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
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description, color: widget.textColor, size: 24),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _filename,
                style: RpgTheme.bodyFont(fontSize: 14, color: widget.textColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
