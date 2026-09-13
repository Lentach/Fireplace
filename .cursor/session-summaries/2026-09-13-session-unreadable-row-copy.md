# Unreadable rows say why, and a chat that cannot send says so BEFORE you type (0.2.43)

**Date:** 2026-09-13 · **Version:** 0.2.42 → **0.2.43** · **Tiers deployed:** none

## What was done
- **One sentinel mapping, two body surfaces.** `sentinelDisplayText`
  (`utils/message_display_text.dart`) owns the whole sentinel→string decision; the bubble
  (`TextMessageContent._displayBody`) and `messageDisplayContent` (`ChatMessageBubble` + the
  provider-free long-press replica) both delegate, each keeping only its own tail. The first cut
  left them deciding separately and they disagreed on screen — the replica said "Odszyfrowanie
  nie powiodło się" over a bubble reading "Nie można odczytać…".
- The raw `[encrypted]` / `[Decryption failed]` sentinels no longer render; both map to
  `messageUnreadableOnThisDevice`, display-only. Also fixed a standing leak:
  `[Encryption not initialized]` reached the bubble raw, because only the replica mapped it.
  Scoping (OWN rows only, pass idle, keyed on the LITERAL not `displayAsEncryptedPlaceholder`)
  and the reasons for each choice: `frontend/docs/e2e-invariants.md` bullets 27–29.
- Quote previews (`utils/reply_preview_helper.dart`) are a THIRD surface and stay separate by
  design — a quoted failed row still reads "Wiadomość zaszyfrowana". Documented, not unified.
- `kDecryptionFailedLabel` / `kEncryptedPlaceholderLabel` promoted from private to public
  (LSP rename, 20 call sites across the three `messaging_provider` part files).
- `chat_detail_screen`: `PeerIdentityChangedRow` is **no longer gated on
  `SettingsProvider.keyChangeWarnings`** — membership in `peersWithChangedIdentity` IS "every
  send to this peer fails closed", so the ceremony door must precede composing. The muted
  (lxxix) note is suppressed automatically. Full reasoning: `e2e-invariants.md` bullet 26.
- **A bounced row now names the refusal**: with the peer in `peersRefusedIdentity`,
  `messageSendBlockedKeysChanged` sits above the retry button, because while the anchor is stale
  every retry fails identically. An ordinary failure still shows "Ponów" ALONE (`e2e-invariants.md`
  bullet 27).
- **Root cause of the bare "Ponów", found and documented, NOT wired:** `_markMessageFailed`
  discards its `errorMsg` argument at all ~15 call sites, so every reason the send path computes
  reaches nobody — and those strings are unlocalized English (`traps.md` § E2E).
- Two new ARB keys (+ the `decryptionFailed` retirement below). The blocked-send sentence is
  deliberately DIRECTION-FREE ("the red warning in this chat", not "above"): the pill is item 0
  of a `reverse: true` list, so it renders BELOW the newest bubble — the first draft said
  "above" and pointed the wrong way.
- Retired the now-unreferenced `decryptionFailed` ARB key ("Decryption failed" / "Odszyfrowanie
  nie powiodło się") — the replica's mapping was its only caller. `flutter gen-l10n` removed
  exactly 14 lines, zero churn.

## Key files
- Edited: `frontend/lib/utils/message_display_text.dart`,
  `frontend/lib/widgets/message/text_message_content.dart`,
  `frontend/lib/widgets/message/chat_message_bubble.dart`,
  `frontend/lib/widgets/message/message_context_menu_bubble_highlight.dart`,
  `frontend/lib/screens/chat_detail_screen.dart`,
  `frontend/lib/providers/messaging_provider.dart` (+ `.decrypt`, `.history`, `.events` parts —
  rename only), `frontend/lib/l10n/app_{en,pl}.arb` (+ generated),
  `frontend/lib/services/encryption_service.dart` (comment only),
  `frontend/pubspec.yaml` (0.2.43), `CLAUDE.md` (test count),
  `scripts/dart-lint-baseline.json` (floor 3174 → 3173),
  `frontend/docs/e2e-invariants.md`, `docs/runbooks/e2e-decryption-failed.md`,
  `docs/runbooks/android-release.md`, `docs/agents/traps.md`, `LATEST.md`.
- Tests: `frontend/test/widgets/message/decrypting_label_test.dart` (+4),
  `frontend/test/utils/message_display_text_test.dart` (own vs peer `[encrypted]`),
  `frontend/test/screens/chat_detail_identity_row_test.dart` (+2 for the bounced-row reason and
  its falsification; the alarmed-peer case at :244 re-pointed and retitled "supersedes F11", and
  one rename at :408 — the F11 case at :391 itself is UNTOUCHED, so do not go hunting for a
  modified F11).

## Verification
- `flutter test` **2119 passed / 14 skipped / 0 failed** (was 2112); `CLAUDE.md` §3 updated and
  `node scripts/verify-claude-frontend-test-counts.mjs` → `OK: CLAUDE.md matches flutter test`.
- `flutter analyze --no-fatal-infos`: **3173 issues, zero errors, zero warnings**. The ratchet
  CAUGHT a +1 I introduced (a misplaced import → `directives_ordering`); sorting that block
  properly cleared a pre-existing finding too, so the floor went 3174 → **3173**
  (`scripts/dart-lint-baseline.json` updated in the same commit).
- **Falsified the new behaviour:** `sed`-mutated both `messageUnreadableOnThisDevice` returns to
  `content` → 3 tests red (terminal-failure, own-row, and the leak assertion); and flipped the
  bounced-row gate to `if (!refused)` → both new cases red in OPPOSITE directions (the refused
  row lost its sentence, the ordinary one gained it). Restored green each time; `git diff`
  confirmed no mutant and no backup left on disk.
- **The suite caught a regression I introduced TWICE**: hoisting `AppLocalizations.of(context)` to
  the top of the mapping made a plain-text bubble require a localizations ancestor it never
  needed, crashing `bubble_redesign_test.dart` on a null check — once in `_displayBody`, again
  after the mapping moved into `sentinelDisplayText`. Fixed at the cause both times (lazy
  per-branch lookup), never by adding delegates to the test.
- **NOT verified on a device.** Everything here is widget-level; no emulator run, no prod. The
  0.2.43 strings have never been seen on a phone.

## Notes for next session
- **REVIEW WANTED on the pill gate.** It re-points the alarmed-peer falsification of amendment
  (lxxix) (`chat_detail_identity_row_test.dart:244`, now "supersedes F11"),
  which deliberately honoured the setting for an alarmed peer. Justification: that assumed a
  demoted change was absorbed, which is false when the anchor did not advance (field-observed
  2026-09-13). The absorbed shape still has its own case (`alarmed: false` → note, no pill). If
  the owner disagrees, revert `chat_detail_screen.dart` only — nothing else depends on it.
- **Deliberately NOT done:** rewriting `_demoteKeyChangeIfMuted` to skip the note when the anchor
  did not advance. It broke 5 service tests including falsifications F47/F48, i.e. it rewrites
  spec (lxxix) itself. Unnecessary — the screen already suppresses the note when the pill shows.
- **WITHDRAWN proposal:** parking a blocked message and auto-sending after confirmation. The
  durable pending-send record is written at `SEND_EMIT` keyed by the emitted ciphertext, and
  `AccountIdentityMismatch` fails BEFORE encryption — so this would need a NEW store holding
  unencrypted message text at rest. Owner call, not plumbing.
- **Owner copy decision left open:** `_markMessageFailed` throws away the reason at ~15 call
  sites. The identity refusal is now rendered from live state, but the other ~14 (media too
  large, upload failed, connection reset…) still show a bare "Ponów", and their existing strings
  are English-only. Localizing them is a copy task, not plumbing.
- Traps: 4 E2E (the discarded `errorMsg` and the quote-preview surface among them), 1 agent
  tooling (the `git status` CRLF trap — my own mistake this session).
