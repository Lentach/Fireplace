# Emote button removal + red-heart-renders-white root-cause fix

**Date:** 2026-07-14 (branch `fix/emote-button-and-red-heart`, off `feat/glass-theme-migration` = live prod 0.0.114; version bumped to 0.0.115; UNMERGED)

## What was done
Two surgical Flutter fixes to chat emote handling.

**Task 1 — removed the composer emoji button.** Traced it: the button only opened `FireplaceEmojiPicker`, a pure keyboard-duplicate (standard `emoji_picker_flutter` grid + a curated suggested row) — no stickers/GIFs/quantum-note/attachments (those live in the separate action panel). Safe to remove. Deleted the button + all provably-unreachable wiring in `chat_input_bar.dart` (`_showEmojiPicker`, `_toggleEmojiPicker`, `_insertEmoji`/`_deletePreviousEmoji`, `_closeEmojiPickerOnFocusGain`, `_setEmojiPickerVisible`, the `keepEmojiPanel` send/sendImage branches, the emoji-only PopScope, the panel mount). `FireplaceEmojiPicker` itself STAYS (still used by the message context-menu reaction picker). Deleted the now-orphaned `composer_emoji_text_editing.dart` + its test, and the two unused l10n keys (`chatComposerEmojiTooltip`/`Semantics`, regen'd). Removed the now-dead `composerBottomPanelPinned` bottom-pin mechanism entirely (nothing set it true once the panel was gone): dropped it from `composer_keyboard_signals.dart`, simplified `chat_composer_viewport.dart` to always use `_keyboardInset`, deleted `chat_composer_viewport_pin_test.dart`. Behavior-preserving (the pin branch never activated after removal).

**Task 2 — red heart rendered white: ROOT CAUSE = font, NOT data.** Proved with a codepoint hexdump that the two curated hearts (`kFireplaceSuggestedEmoji`, `_kReactionEmojis`) already carry the correct `U+2764 U+FE0F`, and there is NO `U+1F90D` White Heart anywhere — so the prompt's hypotheses (a) missing VS16 and (b) wrong codepoint are BOTH FALSE. Reproduced case (c) visually via `tool/heart_preview.dart`: under the app's ambient `GoogleFonts.inter` text font, ❤️ renders WHITE on Flutter-web CanvasKit because Inter ships a monochrome U+2764 glyph and CanvasKit uses the primary font's glyph, ignoring the VS16 emoji request; a `fontFamilyFallback` alone does NOT fix it (Inter primary wins) — the emoji family must be PRIMARY. Fix: added `kEmojiFontFamily`/`kEmojiFontFamilyFallback`/`withEmojiFont` to `utils/jumbo_emoji.dart` and applied an emoji-primary font to every emoji render site — picker suggested row + `emoji_picker_flutter` grid, reaction quick row + reaction chips, jumbo message bubble + `buildInlineEmojiSpans` (mixed text) + the long-press replica, and the conversation-list preview. Data unchanged, so old messages with the bare/legacy heart still display (bare U+2764 also renders red once the emoji font is primary — proven in the harness). Scanned the whole curated lists: ❤️ was the only VS16-base emoji; no other siblings.

## Key files
- `frontend/lib/utils/jumbo_emoji.dart` (new `kEmojiFontFamily`/`kEmojiFontFamilyFallback`/`withEmojiFont`; emoji spans)
- `frontend/lib/widgets/emoji/fireplace_emoji_picker.dart`, `widgets/message/{reaction_chips_row,message_context_menu_overlay,message_context_menu_bubble_highlight,text_message_content}.dart`, `widgets/conversation_tile.dart`
- `frontend/lib/widgets/input/{chat_input_bar,chat_composer_viewport,composer_keyboard_signals}.dart` (button + pin removal)
- Deleted: `composer_emoji_text_editing.dart` (+test), `chat_composer_viewport_pin_test.dart`
- `frontend/test/utils/emoji_font_test.dart` (new regression: codepoint integrity + emoji-font application)
- `frontend/tool/heart_preview.dart` (proof harness, kept), `frontend/CLAUDE.md` §6/§7 updated
- `frontend/pubspec.yaml` 0.0.114 → 0.0.115

## Verification
- `flutter analyze --no-fatal-infos`: clean of NEW issues (2 pre-existing infos only: `privacy_safety_screen.dart:429`, and the untouched `jumbo_emoji.dart:24` `valid_regexps` false-positive on `\p{...}`).
- `flutter test`: **679 passed**, exit 0 (removed ~10 obsolete emoji-panel tests + `composer_emoji_text_editing`/pin tests; added `emoji_font_test`).
- Visual proof, web (CanvasKit, RpgTheme/Inter, `tool/heart_preview.dart`): RED heart in jumbo bubble, inline/preview ("love it ❤️ and 🔥"), and picker suggested row. Composer after-removal screenshot: `[⌄] Type a message… [🎤]`, no emoji button, clean layout.
- Visual proof, mobile (Pixel 7 Android emulator, real installed app): same harness renders RED hearts across all three surfaces (owner also confirmed via device screenshot).
- `graphify update .` run.

## Notes for next session
- **Branch `fix/emote-button-and-red-heart` is UNMERGED** and based on `feat/glass-theme-migration` (the live-but-unmerged prod 0.0.114). PR base should be that glass branch so the diff is only this fix. Not deployed. Master deploy still overwrites branch prod builds.
- The red-heart bug is Flutter-web CanvasKit-specific (ambient Inter monochrome heart); mobile always rendered it red, and the cross-platform fallback (`Apple Color Emoji`/`Segoe UI Emoji`) keeps mobile correct.
- If any NEW emoji render site is added, route it through `withEmojiFont`/`buildInlineEmojiSpans` (CLAUDE §6) or it will show white hearts on web.
