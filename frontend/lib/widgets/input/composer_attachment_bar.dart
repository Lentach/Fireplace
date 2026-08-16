import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/rpg_theme.dart';
import 'composer_attachment_controller.dart';

/// Staged-media chip (image or video) rendered above the composer input row
/// (Clipboard Phase 2; video added by the media-picker redesign). Sibling of
/// ReplyPreviewBar in ChatInputBar's column so the TextField never unmounts
/// when it appears (iOS-WebKit keyboard invariant).
class ComposerAttachmentBar extends StatelessWidget {
  const ComposerAttachmentBar({
    super.key,
    required this.attachment,
    required this.onRemove,
  });

  final StagedAttachment attachment;
  final VoidCallback onRemove;

  String _sizeLabel(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).ceil()} KB';
  }

  String _durationLabel(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final fc = FireplaceColors.of(context);
    final mutedColor = RpgTheme.isDark(context)
        ? RpgTheme.mutedDark
        : RpgTheme.textSecondaryLight;
    final isVideo = attachment.kind == StagedAttachmentKind.video;
    final duration = attachment.durationSeconds;
    final detailLabel = isVideo && duration != null
        ? '${_durationLabel(duration)} · ${_sizeLabel(attachment.bytes.length)}'
        : _sizeLabel(attachment.bytes.length);

    return Material(
      color: colorScheme.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: fc.convItemBorder)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Row(
          children: [
            if (isVideo)
              Container(
                key: const ValueKey('composer_attachment_video_thumb'),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: fc.inputBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.videocam_outlined,
                  size: 20,
                  color: mutedColor,
                ),
              )
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.memory(
                  attachment.bytes,
                  key: const ValueKey('composer_attachment_thumb'),
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  cacheWidth: 120,
                  errorBuilder: (_, _, _) => Container(
                    width: 40,
                    height: 40,
                    color: fc.inputBg,
                    child: Icon(
                      Icons.image_outlined,
                      size: 20,
                      color: mutedColor,
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    attachment.filename.isEmpty && isVideo
                        ? l10n.videoMessage
                        : attachment.filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RpgTheme.bodyFont(
                      fontSize: 13,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    detailLabel,
                    style: RpgTheme.bodyFont(fontSize: 11, color: mutedColor),
                  ),
                ],
              ),
            ),
            IconButton(
              key: const ValueKey('composer_attachment_remove'),
              tooltip: l10n.composerAttachmentRemoveTooltip,
              icon: const Icon(Icons.close, size: 20),
              color: mutedColor,
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}
