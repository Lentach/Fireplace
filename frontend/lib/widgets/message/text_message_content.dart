import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/app_constants.dart';
import '../../l10n/app_localizations.dart';
import '../../models/message_model.dart';
import '../../providers/messaging_provider.dart' show kRetiredMessageLabel;
import '../../services/link_preview_service.dart';
import '../../utils/linkify.dart';
import '../../theme/rpg_theme.dart';
import '../../utils/anti_quantum_note_link.dart';
import '../../utils/jumbo_emoji.dart';
import 'anti_quantum_note_card.dart';

/// Content widget for TEXT message type, including link detection, link preview
/// card, and Telegram-parity "Read more" collapse for long messages so one
/// long message cannot fill the whole screen.
class TextMessageContent extends StatefulWidget {
  final MessageModel message;
  final bool isMine;
  final Color textColor;
  final bool isDark;
  final double maxWidth;

  /// True while a history decrypt pass is running. Turns the raw
  /// "[encrypted]" sentinel into an honest "Decrypting…" for rows the pass has
  /// not reached yet.
  final bool decryptInProgress;
  const TextMessageContent({
    super.key,
    required this.message,
    required this.isMine,
    required this.textColor,
    required this.isDark,
    required this.maxWidth,
    this.decryptInProgress = false,
  });

  @override
  State<TextMessageContent> createState() => _TextMessageContentState();
}

class _TextMessageContentState extends State<TextMessageContent> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant TextMessageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A recycled bubble (list virtualization) now shows a different message:
    // drop any expansion so it does not leak onto an unrelated message.
    if (oldWidget.message.id != widget.message.id) _expanded = false;
  }

  /// The string actually shown in the bubble.
  ///
  /// A cold chat entry has to Signal-decrypt every row before it can show
  /// anything, and that takes seconds on a full page. Rendering the raw
  /// "[encrypted]" sentinel for that whole window made a normal wait look like
  /// a failure — the user reads "encrypted" as "this message is broken", then
  /// watches it flip. Only rows the pass has genuinely not reached yet are
  /// relabelled:
  ///   * "[Decryption failed]" is TERMINAL and must never become a spinner
  ///     that resolves to nothing;
  ///   * once the pass ends, `decryptInProgress` is false again, so a row that
  ///     stayed unresolved falls back to the real sentinel instead of claiming
  ///     to still be working.
  String _displayBody(BuildContext context) {
    if (widget.message.content == kRetiredMessageLabel) {
      return AppLocalizations.of(context).messageNoLongerStoredOnThisDevice;
    }
    if (!widget.decryptInProgress) return widget.message.content;
    // displayAsEncryptedPlaceholder is the model's own predicate: ciphertext
    // present AND content still the "[encrypted]" sentinel. Reused rather than
    // re-derived, so "[Decryption failed]" (terminal) and already-decrypted
    // text are both excluded by construction.
    if (!widget.message.displayAsEncryptedPlaceholder) {
      return widget.message.content;
    }
    return AppLocalizations.of(context).decryptingMessage;
  }

  /// Builds the non-jumbo body spans: plain text + inline emoji + tappable URLs.
  List<InlineSpan> _buildBodySpans(BuildContext context) {
    final textStyle = RpgTheme.bodyFont(
      fontSize: 14,
      color: widget.textColor,
    );
    final linkColor = widget.isMine
        ? widget.textColor
        : Theme.of(context).colorScheme.primary;

    return buildLinkifiedSpans(
      _displayBody(context),
      style: textStyle,
      linkStyle: RpgTheme.bodyFont(
        fontSize: 14,
        color: linkColor,
      ).copyWith(decoration: TextDecoration.underline),
      runBuilder: (run, style) =>
          TextSpan(children: buildInlineEmojiSpans(run, textStyle: style)),
    );
  }

  /// Renders the body with a "Read more"/"Show less" toggle when it exceeds
  /// [AppConstants.maxCollapsedMessageLines] wrapped lines at the bubble width.
  Widget _buildCollapsibleText(BuildContext context) {
    final spans = _buildBodySpans(context);
    // Text always reads left-to-right inside the bubble, regardless of which
    // side the bubble sits on — matches WhatsApp/iMessage/Telegram/Signal.
    // The bubble itself is still right-aligned for sent messages (see the Align
    // in ChatMessageBubble); only the wrapped text lines align left.
    final rootSpan = TextSpan(children: spans);
    final direction = Directionality.of(context);

    // Measure with the SAME config the RichText below renders with, so the
    // toggle appears exactly when the collapsed view would clip.
    final painter = TextPainter(
      text: rootSpan,
      textDirection: direction,
      textAlign: TextAlign.left,
      textWidthBasis: TextWidthBasis.longestLine,
      maxLines: AppConstants.maxCollapsedMessageLines,
    )..layout(maxWidth: widget.maxWidth);
    final overflows = painter.didExceedMaxLines;
    painter.dispose();

    final collapsed = overflows && !_expanded;

    final textWidget = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.maxWidth),
      child: RichText(
        textAlign: TextAlign.left,
        textWidthBasis: TextWidthBasis.longestLine,
        maxLines: collapsed ? AppConstants.maxCollapsedMessageLines : null,
        overflow: collapsed ? TextOverflow.ellipsis : TextOverflow.clip,
        text: rootSpan,
      ),
    );

    if (!overflows) return textWidget;

    final l10n = AppLocalizations.of(context);
    // Accent color on both sides so the toggle never blends into the body text
    // (which is white on sent bubbles); mirrors the app's link/tab treatment.
    final toggleColor = Theme.of(context).colorScheme.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        textWidget,
        const SizedBox(height: 2),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _expanded = !_expanded),
          child: Text(
            _expanded ? l10n.messageShowLess : l10n.messageReadMore,
            style: RpgTheme.bodyFont(
              fontSize: 13,
              color: toggleColor,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildLinkPreviewCard(BuildContext context) {
    final message = widget.message;
    final cardBg = widget.isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);
    final urlColor = widget.isMine
        ? widget.textColor
        : (widget.isDark ? RpgTheme.timeColorDark : RpgTheme.textSecondaryLight);

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
                          color: widget.textColor,
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
    final message = widget.message;
    // An Anti-Quantum Note link renders as a trusted banner card, not as a
    // raw URL + generic preview. Own-origin covers both this build's BASE_URL
    // and the production origin (a prod link received in a dev build is still
    // OURS); genuinely foreign URLs stay plain links with external launch.
    if (isOwnOriginNoteUrl(message.content)) {
      return AntiQuantumNoteCard(
        noteUrl: message.content.trim(),
        isMine: widget.isMine,
        textColor: widget.textColor,
        isDark: widget.isDark,
        maxWidth: widget.maxWidth,
      );
    }

    // Telegram-parity jumbo rendering for emoji-only messages. Emoji-only
    // content is short by definition and never collapses. Size tiers live in
    // jumbo_emoji.dart. Emoji-only content cannot contain URLs, so the link
    // pipeline is safely skipped.
    final jumboSize = jumboEmojiFontSize(message.content);
    final Widget body;
    if (jumboSize != null) {
      body = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        child: RichText(
          textAlign: TextAlign.left,
          textWidthBasis: TextWidthBasis.longestLine,
          text: TextSpan(
            style: withEmojiFont(
              RpgTheme.bodyFont(fontSize: jumboSize, color: widget.textColor),
            ),
            children: [TextSpan(text: message.content)],
          ),
        ),
      );
    } else {
      body = _buildCollapsibleText(context);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: widget.isMine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        body,
        if (message.linkPreviewUrl != null)
          Align(
            alignment: widget.isMine
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: _buildLinkPreviewCard(context),
          ),
      ],
    );
  }
}
