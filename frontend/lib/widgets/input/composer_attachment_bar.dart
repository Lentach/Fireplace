import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/rpg_theme.dart';
import 'composer_attachment_controller.dart';

/// Staged-image chip rendered above the composer input row (Clipboard
/// Phase 2). Sibling of ReplyPreviewBar in ChatInputBar's column so the
/// TextField never unmounts when it appears (iOS-WebKit keyboard invariant).
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final fc = FireplaceColors.of(context);
    final mutedColor = RpgTheme.isDark(context)
        ? RpgTheme.mutedDark
        : RpgTheme.textSecondaryLight;

    return Material(
      color: colorScheme.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: fc.convItemBorder)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.memory(
                attachment.bytes,
                key: const ValueKey('composer_attachment_thumb'),
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                cacheWidth: 120,
                errorBuilder: (_, __, ___) => Container(
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
                    attachment.filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RpgTheme.bodyFont(
                      fontSize: 13,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    _sizeLabel(attachment.bytes.length),
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
