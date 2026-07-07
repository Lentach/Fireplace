import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/message_model.dart';
import '../../services/link_preview_service.dart';
import '../../theme/rpg_theme.dart';
import '../../utils/anti_quantum_note_link.dart';
import '../../utils/jumbo_emoji.dart';
import 'anti_quantum_note_card.dart';

/// Content widget for TEXT message type, including link detection and link preview card.
class TextMessageContent extends StatelessWidget {
  final MessageModel message;
  final bool isMine;
  final Color textColor;
  final bool isDark;
  final double maxWidth;
  const TextMessageContent({
    super.key,
    required this.message,
    required this.isMine,
    required this.textColor,
    required this.isDark,
    required this.maxWidth,
  });
  Widget _buildTextWithLinks(BuildContext context) {
    final text = message.content;
    // Telegram-parity jumbo rendering for emoji-only messages. Size tiers live
    // in jumbo_emoji.dart so this comment does not fossilize another copy.
    // Emoji-only content cannot contain URLs, so the link pipeline below is safely skipped.
    final jumboSize = jumboEmojiFontSize(text);
    if (jumboSize != null) {
      return RichText(
        textAlign: TextAlign.left,
        textWidthBasis: TextWidthBasis.longestLine,
        text: TextSpan(
          style: RpgTheme.bodyFont(fontSize: jumboSize, color: textColor),
          children: [TextSpan(text: text)],
        ),
      );
    }
    final urlRegex = RegExp(r'https?://[^\s]+', caseSensitive: false);
    final spans = <InlineSpan>[];
    int last = 0;
    final linkColor = isMine
        ? textColor
        : Theme.of(context).colorScheme.primary;

    for (final match in urlRegex.allMatches(text)) {
      if (match.start > last) {
        spans.addAll(
          buildInlineEmojiSpans(
            text.substring(last, match.start),
            textStyle: RpgTheme.bodyFont(fontSize: 14, color: textColor),
          ),
        );
      }
      final url = match.group(0)!;
      spans.add(
        TextSpan(
          text: url,
          style: RpgTheme.bodyFont(
            fontSize: 14,
            color: linkColor,
          ).copyWith(decoration: TextDecoration.underline),
          recognizer: TapGestureRecognizer()
            ..onTap = () =>
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        ),
      );
      last = match.end;
    }
    if (last < text.length) {
      spans.addAll(
        buildInlineEmojiSpans(
          text.substring(last),
          textStyle: RpgTheme.bodyFont(fontSize: 14, color: textColor),
        ),
      );
    }

    return RichText(
      // Text always reads left-to-right inside the bubble, regardless of which
      // side the bubble sits on — matches WhatsApp/iMessage/Telegram/Signal.
      // The bubble itself is still right-aligned for sent messages (see the
      // Align in ChatMessageBubble); only the wrapped text lines align left.
      textAlign: TextAlign.left,
      textWidthBasis: TextWidthBasis.longestLine,
      text: TextSpan(children: spans),
    );
  }

  Widget _buildLinkPreviewCard(BuildContext context) {
    final cardBg = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);
    final urlColor = isMine
        ? textColor
        : (isDark ? RpgTheme.timeColorDark : RpgTheme.textSecondaryLight);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GestureDetector(
        onTap: () => launchUrl(
          Uri.parse(message.linkPreviewUrl!),
          mode: LaunchMode.externalApplication,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.linkPreviewImageUrl != null &&
                  LinkPreviewService.isSafeImageUrl(
                    message.linkPreviewImageUrl,
                    message.linkPreviewUrl,
                  ))
                Image.network(
                  message.linkPreviewImageUrl!,
                  width: double.infinity,
                  height: 120,
                  fit: BoxFit.cover,
                  errorBuilder: (_, err, st) => const SizedBox.shrink(),
                ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (message.linkPreviewTitle != null)
                      Text(
                        message.linkPreviewTitle!,
                        style: RpgTheme.bodyFont(
                          fontSize: 13,
                          color: textColor,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 2),
                    Text(
                      message.linkPreviewUrl!,
                      style: RpgTheme.bodyFont(fontSize: 11, color: urlColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // An Anti-Quantum Note link renders as a trusted banner card, not as a
    // raw URL + generic preview. Tap behavior matches the plain-link path.
    if (isAntiQuantumNoteUrl(message.content)) {
      return AntiQuantumNoteCard(
        noteUrl: message.content.trim(),
        isMine: isMine,
        textColor: textColor,
        isDark: isDark,
        maxWidth: maxWidth,
      );
    }

    final textWidget = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: _buildTextWithLinks(context),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: isMine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        textWidget,
        if (message.linkPreviewUrl != null)
          Align(
            alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
            child: _buildLinkPreviewCard(context),
          ),
      ],
    );
  }
}
