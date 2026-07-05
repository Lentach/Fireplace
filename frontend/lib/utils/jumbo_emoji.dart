import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/painting.dart' show InlineSpan, TextSpan, TextStyle;

/// Telegram-style "jumbo" sizing for emoji-only messages.
///
/// Emoji-only chat messages are rendered outside the normal message bubble,
/// Telegram-style. A single emoji should read like a lightweight sticker, not
/// body text in a colored rectangle. Multi-emoji messages step down so rows do
/// not explode horizontally.
///
/// Detection is purely client-side rendering: content is plaintext after E2E
/// decrypt; nothing about it goes on the wire.

/// One grapheme cluster that reads as an emoji.
///
/// - `\p{Extended_Pictographic}` covers real pictographs (😀 ❤ 👍) while
///   excluding `\p{Emoji}`'s traps: digits, `#`, `*`.
/// - Optional VS16 (`\uFE0F`) and skin tone (`\p{Emoji_Modifier}`).
/// - ZWJ sequences (👨‍👩‍👧‍👦) — the `characters` package already clusters them
///   into one grapheme; the regex walks the joined parts.
/// - Flags (🇵🇱) as regional-indicator pairs; keycaps (1️⃣) as digit+VS16+U+20E3.
final RegExp _emojiGrapheme = RegExp(
  r'^(?:'
  r'\p{Regional_Indicator}{2}'
  r'|[0-9#*]\uFE0F?\u20E3'
  r'|\p{Extended_Pictographic}\uFE0F?\p{Emoji_Modifier}?'
  r'(?:\u200D\p{Extended_Pictographic}\uFE0F?\p{Emoji_Modifier}?)*'
  r')$',
  unicode: true,
);

final RegExp _whitespaceOnly = RegExp(r'^\s+$');

/// Number of emoji graphemes when [text] consists solely of emoji (whitespace
/// between them allowed), otherwise `null`. Empty/whitespace-only → `null`.
int? emojiOnlyCount(String text) {
  var count = 0;
  for (final grapheme in text.trim().characters) {
    if (_whitespaceOnly.hasMatch(grapheme)) continue;
    if (!_emojiGrapheme.hasMatch(grapheme)) return null;
    count++;
  }
  return count == 0 ? null : count;
}

/// Telegram-style font size for an emoji-only message, or `null` when [text]
/// is not emoji-only (render at normal body size).
double? jumboEmojiFontSize(String text) {
  final count = emojiOnlyCount(text);
  if (count == null) return null;
  return jumboEmojiFontSizeForCount(count);
}

@visibleForTesting
double jumboEmojiFontSizeForCount(int count) {
  if (count == 1) return 82;
  if (count == 2) return 78;
  if (count == 3) return 64;
  if (count == 4) return 52;
  return 44;
}

/// Inline (in-bubble) emoji size for mixed text+emoji messages. Telegram renders
/// inline emoji slightly larger than surrounding text for legibility; body text
/// stays at 14. Kept modest so wrapped lines do not balloon in height.
const double kInlineEmojiFontSize = 18;

/// True when [grapheme] is a single emoji cluster (same matcher as [emojiOnlyCount]).
bool isEmojiGrapheme(String grapheme) => _emojiGrapheme.hasMatch(grapheme);

/// Splits [text] into inline spans so emoji clusters render at [emojiFontSize]
/// while the rest keeps [textStyle]. Emoji stay inline in the text run (never
/// jumbo — that path is emoji-only). Consecutive same-kind graphemes coalesce
/// into one span so line breaking stays natural.
List<InlineSpan> buildInlineEmojiSpans(
  String text, {
  required TextStyle textStyle,
  double emojiFontSize = kInlineEmojiFontSize,
}) {
  final spans = <InlineSpan>[];
  final buffer = StringBuffer();
  var bufferIsEmoji = false;

  void flush() {
    if (buffer.isEmpty) return;
    spans.add(
      TextSpan(
        text: buffer.toString(),
        style: bufferIsEmoji
            ? textStyle.copyWith(fontSize: emojiFontSize)
            : textStyle,
      ),
    );
    buffer.clear();
  }

  for (final grapheme in text.characters) {
    final graphemeIsEmoji = isEmojiGrapheme(grapheme);
    if (buffer.isNotEmpty && graphemeIsEmoji != bufferIsEmoji) flush();
    bufferIsEmoji = graphemeIsEmoji;
    buffer.write(grapheme);
  }
  flush();
  return spans;
}
