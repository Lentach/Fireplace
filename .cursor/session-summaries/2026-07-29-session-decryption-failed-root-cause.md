# P0 root cause: received messages flip to "[Decryption failed]" after reopen

**Date:** 2026-07-29 — incident diagnosed and fixed on `fix/plaintext-read-cache-race` (`c50af12`). **NOT deployed, NOT merged** — awaiting owner decision. Prod frontend is currently rolled back to `0.0.134 / a00ab0f`; backend untouched at `0.0.136 / 6fb36bf`.

## What was done

**The mechanism (proven by execution).** `SharedPreferences.reload()` reads the backing store, AWAITS that read, then clears its in-memory cache and refills it from the snapshot it took. A write landing inside that await window survives in the store but is **dropped from the cache**, so `getString` answers null for a record that is physically present. Raw-plugin proof: `READ CACHE: null / REAL STORE: PLAINTEXT`; at volume, 3/89 lost from the cache, **0/89 lost from the store**.

For a plaintext record that false miss is not "no plaintext": the row re-decrypts a ciphertext whose Signal ratchet key was consumed at first decrypt → `DuplicateMessage` → permanently `[Decryption failed]`, while the only readable copy sits on disk. That is exactly the owner's log (`kind: duplicate`, `persist: false` on all 42).

**Scope of the claim.** Mechanism proven; **causation for the 42 is circumstantial, not proven** — the harness forces the cache drop, whereas the device needs a real reload racing a real write. It is the only surviving mechanism after the eliminations below, and the deploy is itself the decisive test (see Notes).

**What made a pre-existing hazard start firing.** The window is web-only (`_reloadPrefsForCrossContext` is `kIsWeb`-gated) and already existed at 0.0.134 (10 reload sites). 0.0.136 took `encryption_service.dart` to **18** reload sites and added `sweepDestroyablePlaintext`, `drainPurgeBacklog`, `reconcileStoredPlaintext`, `_startPlaintextSweepTimer` — **all four absent at `a00ab0f`** — so a 60s timer plus a launch drain/sweep/reconcile chain now reload while inbound decrypts persist and the history pass reads.

**Fix.** Record readers no longer depend on that cache: `getDecryptedContent`, `getDecryptedContentMany`, `storedMessageIds`, `_messageIdsMatching`, `stampRecordExpiry`, and `saveDecryptedContent`'s read-modify-write read the backing store **on web only**. A lock could not work — `signal_stores.dart` reloads the same singleton throughout decrypt. Web-gated because `reload()` already paid for that `getAll()`; off web nothing reloads, so the cache is correct and free, and an unconditional `getAll()` would serialise the whole preference map across the method channel once per decrypted message.

**Second, independent data-loss bug found while proving this.** `saveDecryptedContent` built `{...data}` unconditionally, so the terminal-failure write (`{'content': '[Decryption failed]'}`) replaced real plaintext, and hydration (`decrypt.dart:411`) skips a labelled record forever — one transient bad decrypt was permanent loss. A placeholder may no longer overwrite real plaintext; the reverse still heals a row. **This one fails-before deterministically.** It does NOT explain the 42 (`persist: false`); it explains the 27 `badMac` rows from 07-28 (sender 60).

**Eliminated by measurement, not argument** — the previous handoff's four hypotheses are all dead:
- **Reconciliation (H2):** replicated `findServedMessageIds` SQL for user 37 over all 42 broken ids + 3 controls → `SERVED 45/45`. It only destroys ids the server omits; the server omits none. `storedMessageIds()` is metadata-blind, so a bad answer would have taken old records too.
- **Expiry (H1/H3):** 18628/18629 are broken and carry `expiresAt = 2026-08-11` (13 days out). Backend clock is `new Date().toISOString()`, container + Postgres verified UTC, extrapolation capped at 30 min. Unreachable.
- **Retention / LRU eviction:** both call `markRetired`, and retired ids are never decrypted. The broken ids *were* decrypted.
- **Quota / dropped write:** three fresh inbound records were written at 15:10:44 UTC with no `DECRYPT_PERSIST_FAILED` (recorded durably at `:624`, `:902-908`).
- **Key format / namespace / codec:** byte-identical across both commits; the record codec is dormant (`jsonEncode`/`jsonDecode` symmetric).
- **`_userId == null` silent drop:** only reachable before first init or after `clearAllKeys()`; log shows `E2E_INIT_DONE` before the history decrypt and no `AUTH_SESSION_END`.

**Deliberately NOT changed:** the LRU prune still counts via the cache. It undercounts, which *suppresses* eviction — the safe direction. Eviction calls `markRetired` and is permanent, so making it authoritative could retire an account's oldest history on the first launch after this change. Retention pressure is a separate problem.

**Corrected mid-session:** I earlier asserted "own records hydrated, inbound didn't" as proven. It is not — own rows never enter the decrypt pass regardless of whether their disk record was found, so `HISTORY_DECRYPT_START {count: 12}` (which equals the 12 inbound rows exactly) carries no information about own records.

## Key files

- `frontend/lib/services/encryption_service.dart` — `_authoritativeSnapshot()` (web-gated), `_rawRecord()`, `_recordKeys()`, `prefsStorePrefix`, `placeholderContents`, `debugForceAuthoritativeReads`; the placeholder guard in `saveDecryptedContent`.
- `frontend/test/services/encryption_service_reload_race_test.dart` — new, 8 tests, `_HoldableStore` parks `getAll()` inside the reload window to make the race deterministic.
- `frontend/test/services/encryption_service_content_cache_test.dart` — two tests decoupled from the `[Decryption failed]` payload; they were asserting the destructive behaviour.
- `frontend/pubspec.yaml` — `shared_preferences_platform_interface` promoted dev → runtime.
- `CLAUDE.md` §3 — Flutter count 1075 → 1083.

## Verification

- **Fail-before / pass-after**, deterministic, on a probe compiled against the pre-fix service: `getDecryptedContent` → `Expected 'hello', Actual null`; batched history read → `Expected 'world', Actual null`; `storedMessageIds` → `Expected contains 18611, Actual Set:[]`; label overwrite → `Expected 'real plaintext', Actual '[Decryption failed]'`. All four pass post-fix.
- Full frontend suite **1083 passed / 5 skipped / 0 failed**; `flutter analyze` clean; `verify-claude-frontend-test-counts.mjs` OK; `lint-ratchet.mjs` **PASS** at the 817 baseline.
- Prod evidence read-only: 45/45 rows `SERVED`; container/DB UTC; inbound volume for user 37 is **89/24h** vs 15 for the next heaviest account.

## Notes for next session

1. **The deploy is the decisive experiment, and it is falsifiable.** If the 42 render again after shipping this, the records were in the store all along and causation is confirmed. If they stay `[Decryption failed]`, this theory is wrong and the records were never written.
2. **Deploying master + this fix restores every piece of 0.0.136 machinery the rollback removed** (purge, sweep, reconcile, 60s timer). The rollback is what currently stops the bleeding; if the causal read is wrong, this re-exposes the owner. State that plainly before deploying.
3. The owner is on 0.0.134 and is **not** protected — the race primitive exists there too (10 reload sites). The rollback removed the concurrency, not the bug.
4. Still unanswered, cheap, and worth one question: do the owner's **own sent** messages from today still show their text? "No" would put quota and whole-store read failure back in play.
5. `E2ePersistentDiag` is capped at 80 and was exactly full — evidence from the destruction window had already rotated out. The expiry sweep still logs nothing on success; add success-side diagnostics.
6. Never tell the owner to uninstall or clear site data.
