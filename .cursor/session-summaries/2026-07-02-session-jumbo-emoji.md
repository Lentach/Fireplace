# Jumbo emoji Phase 1 — Telegram-parity static sizing for emoji-only messages (feat/emoji-reactions)

**Date:** 2026-07-02

## What was done

Implemented Phase 1 as approved: emoji-only TEXT messages render at Telegram's sizes **inside the normal bubble**. **Static glyphs only** — animated emoji explicitly discarded by user (copyright + E2E metadata leak; a CDN fetch per emoji would reveal message content to the network). Tiers verified against Telegram Android source (`MessageObject.checkEmojiOnly`, `Theme.java` `emojiSizePercents`): regular-emoji column 40.8/33.6/26.4/22.8dp → ours **1–2 → 40, 3 → 34, 4 → 26, 5+ → 22**; body text stays 14.

Meanwhile another (external) agent executed the reaction-picker expansion plan + review fixes (branch advanced to `972976a`: live MediaQuery in overlay, min picker height, bubble-retention test). My redundant reviewer subagent was cancelled per user. Jumbo emoji built on top → commit `6858ae5`, pushed.

## Key files

- `frontend/lib/utils/jumbo_emoji.dart` — NEW: `emojiOnlyCount` (grapheme-safe via `characters`; regex `\p{Extended_Pictographic}` + VS16/skin/ZWJ chains, regional-indicator flag pairs, keycaps; `\p{Emoji}` deliberately avoided — it matches digits/#/*), `jumboEmojiFontSize`, `jumboEmojiFontSizeForCount`.
- `frontend/lib/widgets/message/text_message_content.dart` — jumbo early-return before the URL span pipeline.
- `frontend/lib/widgets/message/message_context_menu_bubble_highlight.dart` — replica default TEXT case `jumboEmojiFontSize(displayContent) ?? 15`; hoisted duplicate `_displayContent` calls.
- `frontend/test/utils/jumbo_emoji_test.dart` — 27 unit tests (positives incl. bare ❤ without VS16, 👨‍👩‍👧‍👦=1, 🇵🇱, 1️⃣; negatives incl. '123', '#', 'hi 😀', ':)', '[Decryption failed]').
- `frontend/test/widgets/message/text_message_content_jumbo_test.dart` — 6 widget tests (40/22 tiers, 14px pipeline preserved for text and URL+emoji, replica 40/15).
- `frontend/CLAUDE.md` §6 — memory line incl. "no animated emoji, ever".

## Verification

- `flutter test` on jumbo unit + jumbo widget + full overlay suite: **80 tests green** (includes the other agent's expansion tests — no interference).
- Full `flutter analyze --no-fatal-infos`: clean. `dart format --set-exit-if-changed` on all touched files: 0 changed.
- `graphify update .` run.

## Notes for next session

- Branch `feat/emoji-reactions` at `6858ae5`, pushed. Contains: emoji picker panel + behavioral fixes, in-place reaction picker expansion (executed by external agent), jumbo emoji. NOT merged to master.
- Device QA checklist for the branch deploy: single 😀 renders ~3× bigger in bubble; 'hi 😀' stays 14; long-press replica matches bubble size; reaction picker in-place expansion with keyboard open (iOS PWA).
- Phase 2a (bubble-less emoji messages) and animated emoji: rejected/deferred — do not resurrect animated (user + E2E rationale recorded in frontend/CLAUDE.md).
- Version stays 0.0.77 (unreleased branch bump).
