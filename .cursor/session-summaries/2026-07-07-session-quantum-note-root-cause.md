# Quantum Note — root cause (SQL 42703) + Option A fix shipped on fix/quantum-note-reveal

**Date:** 2026-07-07

## What was done

Two-part session: root-cause investigation (no code), then user approved "do recommended" → Option A implemented, tested, pushed to `fix/quantum-note-reveal` (0.0.89). **NOT merged — awaiting owner PR review/OK.**

### Root cause (confirmed by live repro)

- **ROOT CAUSE (confirmed by live repro on current code, desktop Chromium):** `SecretNotesService.revealAndDelete` raw SQL uses `expires_at`, but the TypeORM-generated column is camelCase `"expiresAt"` → Postgres 42703 `errorMissingColumn` → `POST /note/:token/reveal` **500s on every click, in every environment, since the feature shipped**. Postgres hint literally names the fix. Reproduced by minting a real note locally (register → login → POST /notes with client-identical AES-256-GCM ciphertext) and clicking the real button.
- **Secondary bug (confirmed):** the landing page's `#error` is hidden by a **stylesheet** rule, but the catch handler does `style.display = ''` (clears only inline style) → error message can never appear → user sees literally nothing on click.
- **History:** `482ce73` (06-21) fixed a *first* dead-button cause (inline `onclick` + un-nonce'd script vs helmet CSP) — that fix IS live in prod (verified via live `/note/*` CSP header). The SQL bug sat underneath.
- **Crypto chain proven sound:** corrected SQL (`"expiresAt"`) returned the ciphertext; the page-context WebCrypto decrypt with the URL-fragment key produced the exact plaintext (incl. emoji). Only the one SQL line blocks the feature.
- **Test gap named:** `secret-notes.service.spec.ts` mocks `repo.query` and asserts only `stringContaining('DELETE FROM secret_notes')` — raw SQL never meets a real schema.
- **Security review of the "server-blind" claim:** holds at rest (server stores ciphertext only, key in URL fragment). **Hole found:** on web, `sendMessage` POSTs the full note URL **including `#key`** to `/messages/link-preview` (proxy path), and `link-preview.service.ts` `logger.debug` can log URL-with-key on fetch failure. GET does not burn notes (preview bots safe); reveal DELETE is atomic (race-safe); no in-app handler for `/note/` links exists → trapped-tab problem is structural (page has zero exit affordance; `noopener` + PWA standalone context).
- **Prod reality:** `https://fireplace.ignorelist.com/version` still `0.0.2/dev` — backend metadata stale/dev-mode; fix will need a real `./deploy-backend.sh`.
- Design options A (minimal page repair) / B (in-app reveal, recommended) / C (in-bubble reveal) written up with trade-offs.

### Fix shipped (Option A, branch `fix/quantum-note-reveal`, 0.0.89)

- `secret-notes.service.ts`: quoted `"expiresAt"` in the raw DELETE **and** destructured the TypeORM postgres DELETE result shape `[rows, rowCount]` (second latent bug the 42703 masked — would have burned notes while returning `{ciphertext: undefined}`; verified in installed `PostgresQueryRunner.js`).
- `secret-notes.controller.ts`: error display `'block'` (was uncloseable `''` vs stylesheet `display:none`), `Cache-Control: no-store` on both note pages (`setNoteCsp` → `setNoteHeaders`), `← Open Fireplace` applink on landing/revealed/destroyed cards (trapped-tab exit).
- `link_preview_service.dart`: new `extractFirstUrl()` + `stripFragment()` statics.
- `messaging_provider.send.dart` web branch: sends ONLY the fragment-stripped first URL to `/messages/link-preview` (was: full plaintext message incl. note `#key`); skips the call when no URL; restores the fragment-included URL into `linkPreview['url']` so the preview-card tap keeps the note key.
- Tests (Tester agents): backend +7 (service spec now mocks real driver shape + asserts quoted `"expiresAt"`/no `expires_at`; controller spec asserts no-store both paths, `'block'`, applinks) → **388 tests / 42 suites**; frontend +8 in `link_preview_service_test.dart` (fragment survives extraction, gone after strip).
- Docs: CLAUDE.md/AGENTS.md counts 381→388; backend/CLAUDE.md gained the per-entity column-casing trap + `[rows, rowCount]` DELETE shape; pubspec 0.0.88→0.0.89; graphify updated.

## Key files

- `.planning/quantum-note/findings.md` — full evidence + design options + owner questions (read this first next session)
- `backend/src/secret-notes/secret-notes.service.ts:39-42` — the broken SQL
- `backend/src/secret-notes/secret-notes.controller.ts` — landing/reveal pages, CSP, invisible `#error`
- `frontend/lib/providers/messaging/messaging_provider.send.dart:473-504,828-841` — note send + link-preview key leak
- `frontend/lib/widgets/message/text_message_content.dart:66,102` — launchUrl paths (trapped tab)

## Verification

- Broken-state repro: `docker-compose up db backend` → real note via REST → Chromium click → `POST /note/.../reveal` = **500**; docker logs show 42703 with hint `"secret_notes.expiresAt"`; `\d secret_notes` confirms camelCase columns.
- Fixed-state E2E (same setup, post-fix code): click → reveal **201** → plaintext `Reveal works now 🔥 fixed-SQL note` rendered; refresh → "This note no longer exists" (real destruction); fragment-less open → click shows the red error, reveal POST does NOT fire (note not burned); `curl -I /note/*` shows nonce'd CSP + `Cache-Control: no-store`; 2 applinks on landing, 1 on destroyed.
- Suites: backend `npm test` **388/388, 42 suites**; count verifier OK; `flutter analyze` no issues; new frontend test file 16/16.
- Live prod check: `/note/*` carries nonce'd CSP (June CSP fix deployed); `/version` = `0.0.2/dev` (stale metadata — separate issue).
- Cleanup: all test notes/users removed from local DB, containers stopped.

### Round 3 (same session): review verdict, in-chat banner, review hardenings

- Independent review (default task agent — `code-reviewer` agent type has NO model configured and crashes; owner later set the subtask model manually): **MERGE-READY, zero blocking**, all 5 claims verified; shared-send-path regression analysis clean; docs secret-scan clean.
- Review findings APPLIED (not ticketed): NB-1 — reveal page now validates + imports the AES key BEFORE the destructive POST (`keyBytes.length !== 32` guard; corrupt fragment can no longer burn a note — E2E-verified: bad-fragment click fires NO reveal fetch and the row survives in the DB). NB-2 — `TOKEN_RE = /^[0-9a-f]{32}$/` gate on both `/note/:token` routes before any DB hit or HTML interpolation (invalid GET → destroyed page, invalid POST → 404, service never called).
- **In-chat banner (owner request):** note messages render `AntiQuantumNoteCard` (red lock badge, accent bar, title + "One-time read · Tap to reveal & destroy" subtitle, en/pl) instead of the raw URL; link-preview card suppressed; metadata stacks below via `messageBubbleUsesInlineTime` gate; send path skips preview fetch for note URLs entirely. New files: `utils/anti_quantum_note_link.dart` (own-origin `/note/<32hex>#key` detector), `widgets/message/anti_quantum_note_card.dart`, ARB key `antiQuantumNoteCardSubtitle`.
- Visual verification caught a real layout bug: `IntrinsicHeight` + wrapped 2-line subtitle overflowed 16px in all four theme/side variants (rendered via temp `dev_banner_preview.dart` harness + headless browser screenshot); fixed with Stack-pinned accent bar, re-rendered clean, harness deleted.
- Tests: +13 frontend (detector 8, inline-time gate 2, banner widget 3), +5 backend controller (token gate, burn-order HTML assertion; 3 pre-existing tests switched to a valid 32-hex fixture) → backend **393/42**, verifier OK, analyze clean.

### Round 4 (same session): deep link back, note-TTL countdown, TTL set, PL copy, privacy explainer

- **Fragment protocol extended** (server-blind by construction — fragments never travel in HTTP): note URLs are now `#<key>[&c=<convId>][&e=<expiryMs>]`. `sendAntiQuantumNote` appends both; detector regex + new `parseAntiQuantumNoteLink` in `utils/anti_quantum_note_link.dart`; legacy bare-`#key` links fully backward compatible (E2E-verified).
- **"← Open Fireplace" deep-links into the source chat:** landing/revealed applinks rewritten client-side to `/?notify_conv=<c>` (digits-only regex guard) — rides the EXISTING push-notification deep-link path (`consumeNotifyConvParam` → `PushService.coldStartConversationId`). E2E-verified: both applinks = `/?notify_conv=42`; destroyed page stays `/`.
- **Note timer decouples from the chat disappearing timer:** the carrying message is sent with `expiresIn = note TTL` (overrides conversation default; read-triggered vanish per existing machinery + max-unread sweep). The banner shows a live **"Self-destructs in Xh Ym"** countdown from `e=` (minute ticker, re-armed to land exactly on the death moment) and flips to a grey **"This note has self-destructed"** state at expiry — client-side only, exact sync with server-side note death.
- **TTL options now 1h/6h/12h/24h** (2h retired): dialog chips + backend whitelist `[3600, 21600, 43200, 86400]`, fallback 21600.
- **PL truncation fixed** by shortening subtitles (en "One-time read · Tap to open" / pl "Jednorazowy odczyt · Dotknij, aby otworzyć") — countdown line carries the urgency now. Visual pass on 6 variants (countdown/destroyed/legacy × dark/light) caught a low-contrast countdown on dark bubbles → lightened red variant.
- **Privacy & Safety explainer card** added (`privacyAntiQuantumNoteTitle/Description`, en/pl): device-side encryption, ciphertext-only server, fragment-only key, one read, timer self-destruct.
- Also typed the `@Req() req: any` wart in `createNote` to `{ user: { id: number } }` (ts-no-any rule).
- Tests: backend controller +12 (TTL whitelist matrix, key-split + deep-link HTML assertions; 7200 test fixed) → **405/42**, verifier OK; frontend +15 net (detector/parser 20 total, new banner-state widget file, dialog test updated to new TTL set) — 47 note-related tests green; analyze clean. E2E on live stack: new-format reveal ✓, deep-link rewrite ✓, legacy link ✓.

### Round 5 (same session): E2E send-race — root-caused, reproduced, fixed (`fix/e2e-send-race`, 0.0.90)

- Field report: burst of ~10 notes A→B, 2 arrived as `[Decryption failed]`. NOT a note bug and NOT data loss — the Signal message carrying the URL failed; the note ciphertext stayed on the server (sender can copy+resend the link).
- **Root cause CONFIRMED by deterministic repro** (new `encryption_send_race_probe_test.dart`, real libsignal both sides): `EncryptionService.encrypt` had no per-recipient serialization → concurrent encrypts interleaved at store awaits, loaded the same ratchet state, emitted duplicate chain counters → receiver `DuplicateMessageException ('old counter: 1, 0')` on **9 of 10** concurrent messages; sequential control 10/10. Field's 2/10 = the same bug softened by network stagger; note bursts are tightest since they skip the preview fetch.
- **Fix:** tail-chained per-recipient future queue in `EncryptionService.encrypt` (failed predecessor never poisons the queue). Post-fix: concurrent burst 10/10. Roundtrip + send-path + envelope suites green; analyze clean; invariant documented in frontend/CLAUDE.md §5. Branch `fix/e2e-send-race` pushed (`3ac0773`), PR + merge owed to owner.

### Round 6 (same session): note label in previews + durable diag + branch-mixup recovery

- **Durable diagnostics** (on the merged `fix/e2e-send-race`, PR #31): `E2ePersistentDiag` (capped-80 SharedPreferences store) mirrors failure-class events (`DECRYPT_DECISION`, `SEND_FAIL`, `SESSION_RESET`, `ENCRYPT_OVERLAP`) so they survive the 200-ring eviction AND app restart; `SEND_ENCRYPT_DONE` gained `ctype`; hacker-mode panel shows a red "Durable failures (survives restart)" section, Copy/Clear cover both. `init()` in `main.dart` before `runApp`. +7 tests. This is the "install more instruments" ask — next `[Decryption failed]` is captured no matter when the user looks.
- **Preview-label fix** (owner report: sent note showed the raw URL in the conversations-list preview): a note's plaintext IS its URL, so the banner only covered the in-chat bubble. Now `conversation_tile._lastMessagePreview`, `replyPreviewForMessageModel`, `replyDisplayContentForQuote`, and `enrichReplyToPreview` all map a note URL → `⚛️ <antiQuantumNoteTitle>` (render-time via `isAntiQuantumNoteUrl`, locale-correct; label threaded as optional param, English default, so provider/test callers unchanged). Push body is server-composed on `[encrypted]` → already generic, no leak. +15 tests, analyze clean.
- **Branch mixup + recovery:** the owner was switching branches in their terminal; the preview-label commit accidentally landed on `refactor/composer-keyboard-viewport` and was pushed. Recovered: cherry-picked to a clean **`fix/note-preview-label`** off master (`bd17a4e`, pushed — THIS is the one to PR); `refactor/composer-keyboard-viewport` reset to `a1b40b7` + `--force-with-lease` (owner's 2 composer commits intact, only the stray commit removed; owner warned to rebase local copies before next push). Lesson: check `git branch --show-current` before every commit — owner switches branches under the agent.

### Round 7 (same session): "[Decryption failed] across the board" incident — investigated, NOT a code regression

- Owner reported widespread `[Decryption failed]`, "fine for a month, broke after yesterday's work" — pushed hard for a regression. Investigated exhaustively; verdict: **not a fleet-wide code regression.**
- **Ruled out (evidence):** key-storage code (`signal_stores`, `loadFromStorage`) unchanged since 06-27; `shared_preferences`/`flutter_secure_storage`/`libsignal` deps unchanged in `pubspec.lock`; auth 401/logout path (`_clearLocalAuthState`) clears tokens only, NOT Signal keys (read confirmed); the 0.0.90 send-race fix is receiver-safe; the 0.0.91 privacy commit is push/log/backup only, frontend bundle unchanged.
- **Actual cause = identity regeneration on SPOKE accounts.** Topology: owner = hub (`bob208`/user 37, 19 sessions, stable), friends = spokes (1 contact each). `needsKeyUpload=true` (`hadIdentityReset`) is set only when a client can't load stored keys → generates a fresh identity → uploads it → every peer sees `identityReset` → `[Decryption failed]` bidirectionally with the hub. 3 broken spokes → looks fleet-wide via ripple.
- **Discriminator (backend OTP-upload logs = regeneration events; reconnect re-upload does NOT upload OTPs):** only **3 users** regenerated (43, 58, 81), dominated by **account 43 = 14× in 47 min** (3:02–3:49 PM, same-minute pairs) — the fingerprint of incognito / clear-data / repeated close-reopen (the testing churn from the runbook). `updatedAt` on key_bundles is NOISE (every reconnect upserts unconditionally).
- **"Rare, most messages fine" = a SEPARATE intermittent decrypt race**, distinct from the test-churn regenerations: resume churn fires overlapping `HISTORY_RESP` passes (3 in one second observed) → two passes `decrypt()` the same inbound msg before either caches → `DuplicateMessageException` → policy brands it `[Decryption failed]`. Matches the first field logs (13969/13970 `kind:duplicate, isHistory:true` on the hub).
- **Decrypt-race repro STARTED, not finished** (branch `fix/decrypt-duplicate-race`, uncommitted `test/services/decrypt_duplicate_race_probe_test.dart`): the naive "two concurrent decrypts of the same ciphertext" probe did NOT collide — both succeeded (concurrent decrypt appears to lost-update the ratchet rather than throw). Repro needs reworking to model sequential re-decrypt after a cache-miss / overlapping-pass timing. NOT root-caused to a fix yet.
- **Fixes designed but NOT built** (gated): (1) decrypt-race fix — single-flight/serialize history-decrypt passes + non-destructive `duplicate` policy (never brand `[Decryption failed]` on a duplicate; recover cached plaintext, read fresh). (2) regeneration guard — block silent identity regeneration when the server already has a bundle for that userId. Guard is gated on confirming keys persist on a NORMAL profile (persistence-regression fork unresolved: the 2-min close+reopen-non-incognito test was not run).
- **Operational guidance given:** STOP incognito / clear-data / reinstall testing and any such support advice — it manufactures the regeneration. PWA close+reopen is safe.

## Notes for next session

- **PR #30 MERGED to master (`c105983`)**; owner device-tested the branch on prod pre-merge and confirmed everything works. Local feature branch deleted; local master synced.
- **Deploy owed for permanence:** VM `cd ~/fireplace && git checkout master && ./deploy-backend.sh` — the `checkout master` matters if the VM is still on the feature branch from the pre-merge test (`deploy-backend.sh` pulls whatever branch is checked out). Verify `curl https://fireplace.ignorelist.com/version` shows the master short SHA (not `dev`). PC: `.\deploy-web.ps1` (0.0.89), verify Settings `gitCommit`.
- Option B (in-app reveal screen/sheet for `/note/` links — removes the served-JS trust gap and the new-tab hop entirely) approved as direction but NOT built; design in `.planning/quantum-note/findings.md`.
- Minor open item: error copy says "already read" even for a missing-key open — could differentiate messages someday.
