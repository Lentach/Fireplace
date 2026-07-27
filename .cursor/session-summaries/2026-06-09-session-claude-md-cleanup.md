# CLAUDE.md condense + accuracy audit + DB/feature additions

**Date:** 2026-06-09

## What was done
Condensing/cleanup pass on `CLAUDE.md` — the first since the 2026-06-01 cleanup (`823588e`, "reduce size ~35%"). Since then ~8 days of voice/media/decrypt work re-bloated **Section 1 (Critical Rules & Gotchas)** with long "this was the real bug / before fix / symptom" narrative wrapped around each invariant. Trimmed the 8 most verbose bullets, removing redundant retelling while preserving **every** invariant, file path, and regression-test name:
- iOS WebKit keyboard inset (visualViewport)
- Tap-to-toggle (voice)
- Web voice playback blob MIME
- iOS WebKit composer focus guard
- Authenticated media / `rewriteLoopbackMediaUrl`
- Media keys are one-shot (two-part fix)
- Decrypt ordering (longest bullet; per-exception narrative compressed to a summary now that `decideDecryptionFailure` + its pinned test are the source of truth)

Also fixed one genuine drift: `ChatGateway` LOC `~459 → ~489` (Architecture Overview).

**Verified-accurate, left unchanged:** backend test count (285 tests / 39 suites — `scripts/verify-claude-backend-test-counts.mjs` passes); `send.dart` ~1052; temp diagnostic code (`page_load_nonce.dart`, `mic_permission_state_*.dart`, `composer_diagnostics_overlay.dart`) still present, so those notes stay.

Net: ~976 chars trimmed (~2%). Line count barely moved (296→295) because these bullets are each a single physical line — the gain is character density / readability, not line removal.

## Key files
- `CLAUDE.md` — Section 1 bullets + Architecture Overview (gateway LOC)

## Verification
- `node scripts/verify-claude-backend-test-counts.mjs` → `OK: CLAUDE.md matches Jest (285 tests, 39 suites)`
- `git diff --stat CLAUDE.md` → 8 insertions / 8 deletions (8 single-line bullets replaced in place; no structural change)
- Manual diff review: every invariant, file path, and regression-test reference retained.

## Notes for next session
- Docs-only change; no code touched, no version bump, not deployed.
- If a deeper trim is wanted later: the "aggressive whole-file pass" option would also collapse code-derivable detail across Sections 2–9 (~30% target), at higher risk of dropping a useful fact.
- Other moderately-long Section 1 bullets (disappearing-messages, reconnect-same-user, `_conversationCache`) were left as-is — already fact-dense, low narrative.

## Follow-up (same session): accuracy audit + DB/feature additions
Three follow-on requests, all docs-only on `CLAUDE.md`:

1. **Code-accuracy audit** — verified ~45 of the most falsifiable claims (magic numbers, symbol names, structural counts, DB schema) against source across 5 grep/read waves. **All matched** (e.g. `kMessageMediaBubbleHeight=220`, `_kMinKeyboardInset=80`, `MAX_REDIRECTS=5`, pre-key `750`/`10min`/`10000`, OTP `20`/`<10`/`25`, JWT `24h` + `REFRESH_TOKEN_TTL_DAYS=365`, throttle `300`/15min + `searchUsers` `30`/60s, decrypt `800`/`900`ms timers, 7 providers, 5 part-files, 4 Signal stores, 4 mappers, enums exact). Only nuance: 10 `chat-*.service.ts` files vs "9 chat services."
2. **Service wording** (commit `c4284df`) — "→ 9 domain chat services (+ shared `ChatValidationService`; 10 `chat-*.service.ts` files total)."
3. **DB schema facts** (commit `c4284df`) — audited all 11 entities; added non-obvious facts to §4: `friend_requests.status` stored **lowercase** (raw-SQL trap, unlike UPPERCASE messageType/deliveryStatus); `messages.replyTo` self-relation (`replyToMessageId`); **no FK to `users`** on `key_bundles`/`one_time_pre_keys`/`fcm_tokens`/`web_push_subscription`/`secret_notes` (explains manual account-delete cascade); flat `linkPreview*` columns; `reactions` JSON shape `{emoji:[userId]}`; `friend_requests` unique `(sender,receiver)`; `refresh_tokens` UUID PK.
4. **Two thin spots documented** (commit `282ddc2`, read from source) — **Reactions** WS flow (`addReaction`/`removeReaction {messageId,emoji}` → `reactionUpdated {messageId,conversationId,reactions}` to caller+peer; FE `MessagingActions` + `ConnectionProvider.on('reactionUpdated')`) and **Secret Notes** ("Anti-Quantum Note": `POST /notes`→token; public `GET /note/:token` HTML + read-once `POST .../reveal` atomic `DELETE…RETURNING`; AES-GCM key in URL fragment, server stores only ciphertext; TTLs 2h/6h/12h; daily 3 AM cron). Both as new §1-Backend bullets.

Net for the day: 4 commits (`6e47353`, `c4284df`, `282ddc2` + the original condense). CLAUDE.md is verified-accurate and the schema/feature coverage gaps are closed.
