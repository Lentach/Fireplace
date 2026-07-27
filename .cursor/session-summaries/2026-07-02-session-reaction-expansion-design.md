# Reaction picker in-place expansion — brainstorm → approved design → implementation plan (NO code)

**Date:** 2026-07-02

## What was done

Brainstormed (per skill, one question at a time) the user's ask: the context-menu reaction row should end with an **arrow** that expands into more reaction emojis, Telegram-style. User's screenshot was the old master build; the branch's current "+"→bottom-sheet approach is being replaced.

**User-approved decisions:**
1. In-place expansion (Telegram) — bottom sheet deleted.
2. Full `FireplaceEmojiPicker` in the expanded panel (search + categories + all emojis).
3. While expanded: quick row + action panel unmount, bubble highlight stays, panel never covers bubble.
4. Outside tap AND system back close the whole overlay (no collapse-first).

**Key findings during design:**
- **`emoji_picker_flutter` grid renders NOTHING under the widget-test binding** (probe-verified: `find.text('😀')` = 0, no icons, no texts; async init never completes). Consequence: expanded panel keeps `showSuggestedRow: true` (amended from chat-approved `false` — no duplication since the quick pill unmounts; it's also the only tappable test path). Documented in spec + plan + planned CLAUDE.md update.
- **`WidgetsBindingObserver.didPopRoute` cannot intercept back for an `OverlayEntry`** — `WidgetsAppState`'s observer is registered first and pops the route. Correct mechanism: `PopEntry` registered on the chat's `ModalRoute` (what `PopScope` uses). Pre-existing bug: today Android back pops the chat under an open context menu.

## Key files

- `docs/plans/2026-07-02-reaction-picker-expansion-design.md` — approved spec (with amendment note)
- `docs/plans/2026-07-02-reaction-picker-expansion-plan.md` — 5-task TDD plan, complete code: (1) pure `computeExpandedReactionPickerLayout` + 7 unit tests, (2) chevron affordance (`context-menu-expand-reactions`, reuses `messageReactionMoreEmoji` ARB), (3) in-place panel replaces bottom sheet + widget tests, (4) `PopEntry` back handling + tests, (5) CLAUDE.md/docs/verify/push.
- Both committed as `070269f`, pushed to `origin/feat/emoji-reactions`.

## Verification

- No production code written (user: "approve do not implement").
- Layout math in planned tests hand-checked (below/above selection, 420 cap, keyboard shrink, alignment clamps).
- Probe test created, run, and deleted (`test/widgets/emoji/probe_grid_test.dart` — not committed).

## Notes for next session

- **Implementation not started.** Execute `docs/plans/2026-07-02-reaction-picker-expansion-plan.md` task-by-task in the worktree `.worktrees/feat-emoji-reactions` (branch `feat/emoji-reactions`, at `070269f`).
- Earlier same day: composer emoji-panel behavioral fixes shipped on this branch (`ce0ee58`) — see 2026-07-02-session-emoji-panel-rework.md.
- No version bump needed (branch carries unreleased 0.0.77).
- After implementation: on-device VM branch test before any master merge; never merge without explicit user OK.

## Addendum: emoji-size research (Telegram source, for future "jumbo emoji" feature — NOT implemented)

Fireplace renders emoji-only messages at body `fontSize: 14` (`text_message_content.dart`). Telegram (`MessageObject.checkEmojiOnly` + `Theme.java`): emoji-only messages get scaled spans — `emojiSizePercents = [.68,.46,.34,.28,.22,.19] × 120dp` → static-emoji column (large=false, indexes 2..5): **1–2 emoji → 40.8dp, 3 → 33.6dp, 4 → 26.4dp, 5+ → 22.8dp**, each +4dp box; "large" column (all-animated/premium): 81.6/55.2/40.8/33.6/26.4/22.8. Inline emoji mixed with text render at textSize+4dp. Gated by `SharedConfig.allowBigEmoji` ("Large Emoji" toggle, default ON). Emoji-only messages are `TYPE_EMOJIS` → `shouldDrawWithoutBackground()` → **no bubble**, sticker-style floating time pill. Proposal sketched in chat: grapheme-based `isEmojiOnly` (characters pkg + `\p{Emoji_Presentation}`-class regex per grapheme; digits/#/* excluded), tier table 1–2→40/3→34/4→26/5+→22, Phase 1 keep bubble, optional Phase 2 bubble-less, context-menu replica must mirror size.
