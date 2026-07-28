# Five-bug batch: composer emoji restore, mobile newline, note previews, self-gallery clobber, ping replay

**Date:** 2026-07-28

## What was done
Two PRs opened from dedicated worktrees (owner request), NOT merged, NOT deployed:

- **PR #103 `fix/composer-and-preview-quickwins`** (2 commits, `cf2a637` + `42e9cac`):
  1. **Bug 2** — composer emoji button RESTORED. Archaeology first: removed in `6131b15` (0.0.115, PR #69) for pure redundancy ("every soft keyboard has one"); the premise was wrong (owner report: some keyboards lack an emoji key), owner ruled restore. Re-added button, panel, `composerBottomPanelPinned`, viewport pin branch, `composer_emoji_text_editing.dart`, 2 l10n keys, and the 3 deleted test files. `frontend/CLAUDE.md` §7 "do not reintroduce" line superseded in the same commit. iOS-style emotes: **declined — Apple Color Emoji is not redistributable**; iOS already shows Apple glyphs via fallback (`jumbo_emoji.dart:86-91`).
  2. **Bug 4** — mobile action key inserts newline. `_isMobilePlatform` (defaultTargetPlatform android/iOS — catches phone PWA; kIsWeb would misclassify) → `TextInputAction.newline` + no `onSubmitted`; desktop byte-identical (send + Ctrl/Cmd+Enter). Platform-matrix regression test.
  3. **Bug 5** — Anti-Quantum Note previews show `antiQuantumNoteTitle` label instead of the raw URL: conversation tile + reply bar + pinned banner + in-bubble quote (all via `reply_preview_helper`). Non-surfaces verified: push (server blind), search (users only), forward (absent). **Link-preview consumption CLEARED** (client excludes note URLs `send.dart:955` + strips fragment; backend skips encrypted `chat-link-preview.service.ts:43`; GET `/note/:token` is a plain SELECT — burn is POST reveal only). No wire-contract change.
- **PR #104 `fix/avatar-count-and-ping`** (6 commits, `991a6b2`..`2dc652b`):
  4. **Bug 1** — self card "1/3": `_restoreUserFromAccessJwt` rebuilt currentUser from JWT claims on every silent refresh, dropping `profilePhotos`/`about` (only `profilePictureUrl` survived). Same-account restores now `copyWith` the hydrated user. Clobber even fired during boot hydrate — regression tests fail pre-fix at the seed assertion. Swipe-dead gallery = separate design fact (tap-zone nav gated on photos>1), self-heals with the fix.
  5. **Bug 3** — ping replay: ping plaintext '' → persisted content='' → restore kept `[encrypted]` → forced live re-decrypt each entry → effect re-flip → sound. Fix: persisted PING restores as genuinely decrypted (content '', type ping) — consume-once by construction; plus transient per-provider id dedup for redelivered `newMessage` (kept on reconnect, cleared on fresh connect). Persisted "played-ids cache" band-aid explicitly rejected. **Bug 3e** (separate perf commit): overlay now RepaintBoundary + Fade/ScaleTransition over a static child — no per-frame subtree rebuild/saveLayer/painter. **Residual closed in `ec13e22`:** leaving the chat inside the 800ms animation unmounted the overlay before `onComplete` → `showPingEffect` stayed latched → one same-session replay on re-entry; `dispose()` now defers `onComplete` via `scheduleMicrotask` when the animation didn't finish (regression test fails pre-fix).

## Key files
Branch A: `chat_input_bar.dart`, `chat_composer_viewport.dart`, `composer_keyboard_signals.dart`, `composer_emoji_text_editing.dart`, l10n ×6, `reply_preview_helper.dart`, `conversation_tile.dart`, 6 test files, both CLAUDE.md. Branch B: `auth_provider.dart`, `messaging_provider.decrypt.dart`, `messaging_provider.dart`, `ping_effect_overlay.dart`, 2 test files, root CLAUDE.md.

## Verification
- Branch A: analyze **No issues**, `flutter test` **925 passed + 4 skipped** (903→925, counts updated per commit). Fail-before proven by stashing lib: bug-4 mobile tests fail, bug-5 tile test fails; bug-2 tests were deleted with the feature.
- Branch B: analyze **No issues**, **911 passed + 4 skipped** (903→911). Fail-before: both bug-1 tests and the bug-3 restore test fail on stashed lib.
- CI green on both PR branches (runs 30320479036, 30320914644). `impact.mjs` run per cluster.

## Notes for next session
- **PRs #103 and #104 await owner approval. Do NOT merge or deploy without it.** Both update the CLAUDE.md §3 frontend test count (925 vs 911) — the SECOND merge will conflict/mis-state the count; after both merge, set it to 903+22+8=**933** and rerun the verifier.
- Codex-backed default `task` subagents hit a usage wall (`usage_limit_reached`); `sonic`/`scout` (Anthropic) worked. Route accordingly.
- NOT fixed, by design: actual swipe gesture on card galleries (never existed; tap-zone nav is the design), Apple emoji on non-Apple platforms (licensing; Twemoji/OpenMoji possible if owner wants), desktop Enter-to-send (owner ruled keep Enter=newline + Ctrl/Cmd+Enter=send).
- Worktrees `fireplace-wt-quickwins` / `fireplace-wt-avatar-ping` still exist; remove with `git worktree remove` after merges.
