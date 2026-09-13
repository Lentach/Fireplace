# Unreadable rows say why, and a chat that cannot send says so BEFORE you type (0.2.43)

**Date:** 2026-09-13 · **Version:** 0.2.42 → **0.2.43** · **Tiers deployed:** none

## What was done
- **One sentinel mapping, two body surfaces.** `sentinelDisplayText`
  (`utils/message_display_text.dart`) now owns the whole sentinel→string decision and BOTH
  bodies delegate: the bubble (`TextMessageContent._displayBody`) and `messageDisplayContent`,
  used by `ChatMessageBubble` and the provider-free long-press replica. They used to decide
  separately, and the first cut of this change made them disagree in a user-visible way — the
  replica said "Odszyfrowanie nie powiodło się" over a bubble reading "Nie można odczytać…".
  Each keeps only its own tail (raw content vs `unsupportedMessageType`), so an empty decrypted
  row still renders empty.
- The raw `[encrypted]` / `[Decryption failed]` sentinels no longer render anywhere. Both map to
  `messageUnreadableOnThisDevice`; **display-only**, `MessageModel.content` is never rewritten
  (the failed label is persisted and the durable cache must keep seeing it). The helper also
  fixed a standing leak: `[Encryption not initialized]` reached the bubble raw, because only the
  replica's path had ever mapped it.
- Scoped the `[encrypted]` half deliberately: **OWN rows only, pass idle.** A peer `[encrypted]`
  row may just be waiting for the decrypt pass, so relabelling it would flash a false "can't be
  read" on every cold chat entry; unresolved peer rows become `[Decryption failed]` via the
  post-retry sweep and are caught there instead.
- Keyed on the LITERAL, not `displayAsEncryptedPlaceholder`: that predicate needs ciphertext, and
  a fan-out own-send row carries none for its own origin device (ix) — so the predicate misses the
  exact row the owner asked about (their own message after a reinstall).
- `kDecryptionFailedLabel` / `kEncryptedPlaceholderLabel` promoted from private to public
  (LSP rename, 20 call sites across the three `messaging_provider` part files).
- `chat_detail_screen`: `PeerIdentityChangedRow` is **no longer gated on
  `SettingsProvider.keyChangeWarnings`**. A peer in `peersWithChangedIdentity` means the account
  anchor never advanced, which means every send to them fails closed — so the door to the ceremony
  now appears when the change arrives, not after a message has bounced. The muted (lxxix) note is
  suppressed automatically (`peerKeyChangeNoteAt` is computed under `!peerIdentityChanged`).
- New ARB key + PL/EN strings; `flutter gen-l10n` added exactly 18 lines, no churn.
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
  `frontend/docs/e2e-invariants.md`, `docs/runbooks/e2e-decryption-failed.md`,
  `docs/runbooks/android-release.md`, `docs/agents/traps.md`, `LATEST.md`.
- Tests: `frontend/test/widgets/message/decrypting_label_test.dart` (+4),
  `frontend/test/utils/message_display_text_test.dart` (own vs peer `[encrypted]`),
  `frontend/test/screens/chat_detail_identity_row_test.dart` (F11 re-pointed).

## Verification
- `flutter test` **2117 passed / 14 skipped / 0 failed** (was 2112); `CLAUDE.md` §3 updated and
  `node scripts/verify-claude-frontend-test-counts.mjs` → `OK: CLAUDE.md matches flutter test`.
- `flutter analyze --no-fatal-infos`: **3174 issues, zero errors, zero warnings** — below the 3175
  ratchet floor.
- **Falsified the new behaviour:** `sed`-mutated both `messageUnreadableOnThisDevice` returns to
  `content` → 3 tests red (terminal-failure, own-row, and the leak assertion); restored → 9/9
  green; `git diff` confirmed no mutant and no backup left on disk.
- **The suite caught a regression I introduced TWICE**: hoisting `AppLocalizations.of(context)` to
  the top of the mapping made a plain-text bubble require a localizations ancestor it never
  needed, crashing `bubble_redesign_test.dart` on a null check — once in `_displayBody`, again
  after the mapping moved into `sentinelDisplayText`. Fixed at the cause both times (lazy
  per-branch lookup), never by adding delegates to the test.
- **NOT verified on a device.** Everything here is widget-level; no emulator run, no prod. The
  0.2.43 strings have never been seen on a phone.

## Notes for next session
- **REVIEW WANTED on the pill gate.** It re-points falsification `F11` of amendment (lxxix),
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
- Still owed: the failed bubble says only "Ponów"; `messaging_provider.send.dart` already has the
  right sentence ("compare their safety number") and it is not wired to the row.
- Traps: 2 E2E, 1 agent tooling (the `git status` CRLF trap — my own mistake this session).
