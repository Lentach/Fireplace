import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Telegram-style "jumbo" sizing for emoji-only messages.
///
/// Telegram Android (`MessageObject.checkEmojiOnly` + `Theme.java`,
/// `emojiSizePercents = [.68,.46,.34,.28,.22,.19] × 120dp`) renders regular
/// (non-premium) emoji-only messages at 40.8/33.6/26.4/22.8dp for
/// 1–2/3/4/5+ emoji. Fireplace body text is 14 — these tiers mirror
/// Telegram's, rounded.
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

/// Telegram-parity font size for an emoji-only message, or `null` when [text]
/// is not emoji-only (render at normal body size).
double? jumboEmojiFontSize(String text) {
  final count = emojiOnlyCount(text);
  if (count == null) return null;
  return jumboEmojiFontSizeForCount(count);
}

@visibleForTesting
double jumboEmojiFontSizeForCount(int count) {
  if (count <= 2) return 40;
  if (count == 3) return 34;
  if (count == 4) return 26;
  return 22;
}
