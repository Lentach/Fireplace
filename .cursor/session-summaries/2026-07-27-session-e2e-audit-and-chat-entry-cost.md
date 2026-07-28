# E2E safety audit + chat-entry flicker/lag fix

**Date:** 2026-07-27 — full pre-production E2E audit (7 parallel read-only slices)
plus the fix for the reported "history flashes `[encrypted]` and janks on chat
entry". Branch `audit/e2e-safety` in a separate worktree
(`C:/Users/Lentach/Desktop/fireplace-e2e-audit`), cut from `master` @ `d2f8aca`.
Live at audit time: **0.0.132 / `05fc423`**, both surfaces. Nothing deployed.

## What was done

### The reported symptom — root-caused and MEASURED, not guessed
Two independent defects, neither a decryption failure:

1. **Paint before hydrate.** The server ships `content: "[encrypted]"` for every
   E2E row (`chat-message.service.ts:80`). `onMessageHistory` merged and
   notified at `history.dart:402` BEFORE any local plaintext was applied, so the
   first painted frame of a cold entry was all placeholders; the list flipped
   only at the terminal notify of the async decrypt pass.
2. **One full `SharedPreferences.reload()` PER ROW.** `getDecryptedContent`
   (`encryption_service.dart:641`) reloads before every read — added by
   `fd89e7e` (0.0.126) for cross-engine coherence — and `_decryptMessageHistory`
   called it once per history row. On web `reload()` is the plugin's `getAll()`:
   enumerate EVERY localStorage key, then `getItem` + `jsonDecode` each
   `flutter.`-prefixed one, against a plaintext cache capped at **2000** records.

Measured in headless Chrome against real localStorage
(`frontend/tool/prefs_reload_cost_probe.dart`, 3 runs, virtual + real clock
agree), desktop i7-7700, cache at its 2000-row cap:

| | current | one reload per pass |
|---|---|---|
| 50 rows (one page) | **65-77 ms** | 1.4 ms |
| 200 rows | **290-316 ms** | 1.4 ms |
| 400 rows | **562-597 ms** | 1.6 ms |

One reload = 1.6-2.0 ms at the cap (0.10 ms empty — it scales with cache size).
Phones run this 4-6x slower, which is exactly "a flick of a second".

Bonus finding, same probe: `SharedPreferencesAsyncWeb.getString` filters its
allowList only AFTER materialising every localStorage key, so **every Signal
session/identity/prekey read is O(total keys)** — a single Signal key read goes
0.034 ms → 0.236 ms purely because the plaintext cache filled up.

### The fix (4 changes, none touches the lock or the replay cache)
- `EncryptionService.getDecryptedContentMany` — one coherence reload for a
  bounded id set. Carries the safety argument in its doc comment: the plaintext
  cache IS a coherence surface, so the reload is **hoisted, never deleted**;
  writes landing mid-pass are still caught by the raw replay cache (own reload,
  written before the session lock releases, capped at 40).
- `_hydrateSnapshotFromCaches` fills the parsed snapshot while it is still a
  caller-local list, before the merge + notify. Upgrade-only.
- `_decryptMessageHistory` prefetches once per pass; `_persistedPlaintextFor`
  falls through to the single read on a miss.
- `_pruneDecryptedContentCache` no longer calls `_storage.readAll()` on web
  (matched zero keys while decoding the whole origin store — 2.46 ms wasted per
  persisted message), and the legacy secure-storage fallback is gated to mobile
  where such entries can actually exist.

### The audit — verdict SAFE WITH CAVEATS, no CRITICAL
Verified sound: both lock layers on all four session mutations, leaf-level (no
deadlock), account+peer lock naming, fail-closed Web Locks, monotonic plaintext,
exact-ciphertext replay, server structurally incapable of holding private keys,
content-free push on both channels, blind server-side `editMessage`, membership
on every endpoint, ciphertext genuinely deleted.

Open caveats, highest first — **none fixed in this branch**:
- **MED `identity_key_pair` and `registration_id` are two independent keys.**
  Losing exactly one makes `loadFromStorage()` return false → `_generateKeys()`
  mints a NEW identity → all history with every peer becomes permanently
  undecryptable, silently. A *throwing* read is correctly fail-safe; only
  partial loss bites. This is the one that can destroy user data.
- **MED the Web Lock layer is not actually tested.**
  `session_cross_context_lock_web_test.dart:11` opens `if (!kIsWeb) return;` —
  under `flutter test` it is a no-op that **reports as passing**. The race probes
  inject a fake lock. Only the manual browser probe exercises real
  `navigator.locks`, and CI never runs it.
- MED cross-engine OTP generation is unserialized (per-engine bool only).
- MED decrypted plaintext sits unencrypted at rest on **mobile** too
  (SharedPreferences, not secure storage) while keys are hardware-backed.
- MED silent TOFU: a peer identity change is auto-accepted with no warning.
- LOW `GET /media/msgs/:filename` is JWT-guarded but has no participant check
  (E2E-encrypted UUID blobs, so no plaintext).
- LOW invariants "no deadlock" and "unrelated peers stay parallel" have zero
  automated coverage; `buildSession`/`deleteSession` serialization is still
  probe-vacuous, exactly as the 2026-07-09 runbook edge recorded.

## Key files
- `frontend/lib/services/encryption_service.dart` — `getDecryptedContentMany`,
  `_legacyDecryptedContentFallback`, prune gate.
- `frontend/lib/providers/encryption_provider.dart` — batch passthrough.
- `frontend/lib/providers/messaging/messaging_provider.decrypt.dart` —
  `_restoreFromPersistedPayload`, `_hydrateSnapshotFromCaches`,
  `_hydrateSnapshotFromStorage`, `_prefetchPersistedPlaintext`,
  `_persistedPlaintextFor`.
- `frontend/lib/providers/messaging/messaging_provider.history.dart` —
  pre-paint hydration + supersede guard in `onMessageHistory`.
- `frontend/test/providers/messaging_provider_chat_entry_hydration_test.dart` (new, 6 tests).
- `frontend/tool/prefs_reload_cost_probe.dart` + `.html` (new, diagnostic).
- `docs/runbooks/e2e-decryption-failed.md` — new Step 3D.
- `frontend/CLAUDE.md` §5 — two new load-bearing bullets. `CLAUDE.md` §3 count 903 → 909.

## Verification
- `flutter analyze --no-fatal-infos` → **No issues found**.
- `flutter test` → **909 passed, 4 skipped**; `verify-claude-frontend-test-counts.mjs` → OK.
- **Both new behaviours falsified separately**: disabling the pre-paint
  hydration turns the placeholder-frame test red; ignoring the prefetched batch
  turns the pass-level test red at 30 reads instead of 0. (The first read-count
  test alone did NOT discriminate — pre-paint hydration satisfied it — which is
  why the pass-level test exists.)
- The lost-ack suite caught a real regression mid-work: hydrating OWN rows from
  the RAM cache skipped the reconcile branch and the durable persist never
  happened. Fixed in the hydration, not in the test.
- Cost probe re-run after the change is unnecessary: the "one reload per pass"
  column above IS the new access pattern (two such passes per entry, ~3-7 ms).

## Then: all four fixable MEDIUM findings closed (`98d26bb`)

- **M1 identity can no longer silently regenerate.** One atomic
  `identity_record_v1`; the legacy two-key pair is still READ (the whole
  installed base has only that) and mirrored on write. `loadFromStorage` →
  `loaded`/`absent`/`partial`; "no identity but sessions survive" is also
  partial. Throws `E2eIdentityIncompleteException`, touches nothing. The
  residue probe biases toward FRESH INSTALL when `readAll` itself fails —
  bricking a user with nothing to lose is not a safety property.
- **Escape hatch, because fail-closed without one is just a different brick.**
  Typed catch → `identityIncomplete` → `IdentityDamagedBanner` → confirm →
  `regenerateIdentityAfterConfirmedLoss`. In-flight guard set synchronously
  before the await (100 prekeys is not instant; two taps would race two
  identity writes). Consent copy states the real loss: undecrypted ciphertext
  is gone, the plaintext cache survives.
- **M5 peer re-key is surfaced.** Still TOFU, but `isTrustedIdentity` compares
  and reports via `PeerIdentityChangedBanner`. It runs per message, so the
  store memoises trusted keys and now SKIPS the write when unchanged —
  cheaper than the unconditional write it replaced.
- **M3 prekey generation is origin-locked** (`fireplace-e2e-prekeys-<uid>`,
  its own name — it touches no SessionRecord).
- **M2 the Web Lock is finally verified.** The old test opened
  `if (!kIsWeb) return;` and reported as PASSED while asserting nothing. Now an
  honest skip + `scripts/verify-session-lock-probe.mjs` driving real
  `navigator.locks` in headless Chrome as CI job `session-lock`.

### Verification of the MED work
- analyze 0 issues; **931 passed / 5 skipped**; count verifier OK.
- Prekey lock has a FALSIFICATION test asserting the unserialized version still
  collides — it fails if the two-engine test ever stops proving anything.
- Session-lock runner falsified BOTH ways before being trusted: breaking the
  lock gave `SESSION_LOCK_FAIL: same-name lock did not queue` + exit 1; a page
  that never reports gave the hang message + exit 1. The probe now sets
  `SESSION_LOCK_FAIL` on a thrown assertion, so a real regression can never be
  misread as a harness glitch.
- Banner off-states are tested first: an always-on "keys damaged" bar with a
  destructive button would be worse than not shipping it.

### M4 NOT done, deliberately
Decrypted plaintext sits in SharedPreferences on mobile too, while keys are
hardware-backed. "Fixing" it means migrating up to 2000 records per account
into Keychain/Keystore — slow, and a data-loss hazard of exactly the class this
branch exists to remove. Not worth doing blind. If it matters, the proportionate
design is a cache encrypted with a key held in secure storage, scoped and
measured on its own.

## Then: verified in a REAL browser, and found the fix was incomplete (`be4ef31`)

Owner pushed back on deferring verification — docker, an emulator and a browser
were all available. Everything below ran against a real backend + Postgres, a
real Chrome profile, and real libsignal.

- **M1 web path — the biggest unverified risk — now proven.** On real
  localStorage: legacy-only install LOADS and migrates (`pairUnchanged: true`,
  `v1MatchesLegacyPair: true`) — that is the whole installed base's upgrade
  path; partial loss REFUSES (`identityPairUntouched: true`,
  `noNewRecordMinted: true`, `IDENTITY_INCOMPLETE` in the durable diag);
  consented recovery mints a new identity, republishes, and the server shows
  the matching `identityPublicKey`, 20 fresh OTPs and `[identity-churn]`.
- **A peer can X3DH against the regenerated identity**
  (`recovered_identity_probe_test.dart`, PreKey `3:` wire). That closed the
  "banner went away but is the account reachable" gap.
- **The banner's action button was invisible** — default TextButton colour is
  the theme PRIMARY, unreadable on the red error container. Caught only by
  looking at a render. Pinned to `onErrorContainer`.
- **THE OWNER'S ACTUAL BUG WAS STILL THERE.** Entering a chat with 300 fresh
  messages showed every row as `[encrypted]` for 3-5 s. My earlier fix targeted
  the CACHED re-entry path; a genuinely first entry has no plaintext to show, so
  it fell straight through. Instrumented: first row 4.7 s, pass 6.3 s for 50
  rows (DEBUG web build — absolute numbers are not production).
  - Fixed by relabelling to "Decrypting…" while a pass is in flight. Verified in
    the browser: rows read "Odszyfrowywanie…" mid-pass, then real text.
  - Narrow on purpose: keyed off `displayAsEncryptedPlaceholder`, so terminal
    `[Decryption failed]` stays terminal and keyed media never reaches the path.
  - `retryDecryptActiveConversation` now try/finally — a throw there stranded
    `_decryptingHistory` true for the session, previously invisible, and would
    have become a permanent "Decrypting…".
- **Tried and REVERTED: progressive reveal.** The pass runs oldest-first
  (ratchet) while the list is `reverse: true` and shows newest — mid-pass
  notifies resolve off-screen rows first. Churn, no gain.
- **Prune rewritten**: was a full key scan plus a redundant reload on EVERY
  save. Now gated on a size estimate seeded by one scan per instance —
  deliberately NOT a per-session counter, which resets each launch and would let
  the cache grow to the localStorage quota, where the first casualty is
  `WebSignalKvStore` persisting session/identity records, not the cache.

### Incidental
- The disaster-recovery migration path ran for real: the stack came up on an
  EMPTY database and reached `{"status":"ok","db":"ok"}`.
- Two throwaway probes added, both skipped unless given dart-defines:
  `seed_long_history_probe_test.dart`, `recovered_identity_probe_test.dart`.

## Notes for next session
- **NOT deployed and NOT version-bumped.** `pubspec.yaml` stays 0.0.132; the
  bump belongs to the release commit (the 0.0.131 run recorded a procedure
  exception for bumping too early). Branch does not auto-deploy.
- Do **not** claim a synchronous warm-entry fast path: own rows always route to
  the disk read (the server always sends them as `[encrypted]`), so any chat
  containing your own messages takes the batched read. The honest claim is
  "one batched read instead of N reloads".
- The identity-regeneration hole (MED, first in the list above) is the highest
  value follow-up: make the identity pair + registration id one atomic record
  and refuse to regenerate while session records still exist.
- The vacuous Web-Lock test is the second: it reports green while pinning
  nothing. Either run it under `--platform chrome` in CI or wire the browser
  probe into a job.
