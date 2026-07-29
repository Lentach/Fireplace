> **IMPLEMENTED 2026-07-29 — this plan is history, not instructions.** Phase 2 shipped on
> `feature/android-encrypted-store` (commits `93cc6e0` → `7f0a212` → `33a906f` → `71b3980` →
> `6f656cc`): unit suite 1098 + 10 skipped, `flutter analyze` clean, on-device acceptance
> `flutter test integration_test -d <device>` 7/7 on a Pixel_7 emulator (android-34), and a real
> two-account emulator run whose storage dump showed no JWT and no `e2e_*` record in the prefs XML.
> The living contract is `frontend/CLAUDE.md` §5 + `docs/runbooks/android-release.md`; read those
> first and treat anything below as the reasoning that produced them.
> Still open from this plan: the owner's real-phone smoke (voice play/seek/cached replay, push,
> upgrade from a pre-Phase-2 install) and Phase 3 (GitHub Release distribution).

# Handoff: Phase 2 — encrypted local message store (native Android)

**Status when written (2026-07-29):** Phase 1 (release plumbing) is DONE, merged to master, CI green.
A signed release APK builds end-to-end via `.\build-android.ps1` (0.0.137, versionCode 137, all gates
green). The release keystore exists on the owner's PC and is backed up. **Phase 2 is the DISTRIBUTION
GATE: no APK goes to real users until it ships**, because only a first install with sealing active
has a fully clean shredding story.

## Required reading, in order (subagents do not inherit context)

1. Root `CLAUDE.md` + `frontend/CLAUDE.md` (project source of truth; §5 of each is load-bearing here).
2. `.cursor/session-summaries/2026-07-29-session-android-phase1.md` — investigation corrections + decisions.
3. `docs/runbooks/android-release.md` — what Phase 1 enforces; "Known-not-done" names this work.
4. `frontend/lib/services/plaintext_record_codec.dart` — the B2 design rationale in its doc comments
   (sealed envelope, incremental/resumable migration, armed-key rule, honest-claim limit).
5. GitHub issue #105 — the parent issue; its "Still open" list = at-rest encryption + key rotation (M4).

## The problem being fixed

On native Android today, Signal KEYS are Keystore-backed (DualStorage, `signal_stores.dart`), but ALL
of the following go through RAW `SharedPreferences.getInstance()` (`encryption_service.dart:79`) =
**plaintext XML** in `/data/data/com.fireplace.app/shared_prefs/`:

| # | Data | Key pattern |
|---|---|---|
| 1 | Decrypted message plaintext + mediaKey/mediaIv + linkPreview | `e2e_<uid>_decrypted_<msgId>` |
| 2 | Raw ciphertext↔plaintext pairs (lost-ack), LRU cap 40 | `e2e_<uid>_decrypt_raw_v1_<msgId>` |
| 3 | Pending-send plaintext, one key per emitted ciphertext | `e2e_<uid>_pendsend_v1_<ct>` |
| 4 | Durable purge backlog (ids+ciphertexts) | `e2e_<uid>_purge_pending_v1` |
| 5 | Retention epoch / retired-id set / reconcile stamp | `e2e_<uid>_retention_epoch_v1`, `_retired_v1`, `_reconcile_last_v1` |
| 6 | Durable E2E diagnostics (peerIds, failure classes) | `e2e_diag_persist_v1` |
| 7 | JWT + refresh token (`auth_provider.dart:114-116,217,271`) | `jwt_token`, `refresh_token` |
| 8 | Decrypted voice notes as FILES (`audio_cache_store.dart`) | `<documents>/audio_cache/<msgId>.audio` |

`allowBackup=false` (Phase 1) stops cloud exfiltration; Phase 2 makes the bytes at rest ciphertext.

## Agreed design (owner decisions + advisory-hardened, do not relitigate)

- **Store:** Drift + SQLCipher (decision "3B"), NATIVE ONLY. Web keeps its current path unchanged
  (web sealing is a separate, canary-gated effort — `content_key_canary.dart`, needs zero
  `CONTENT_KEY_CANARY_LOST` field diags before it may proceed).
- **Content key:** minted into `flutter_secure_storage` with the SAME instance/options as the Signal
  keys (failure modes must stay correlated — key dies only when the Signal identity dies too).
  **NO auth binding** (no `setUserAuthenticationRequired`/biometric — re-enrollment would invalidate it).
- **Armed-gate:** persist the key → read it back from a FRESH read → only then seal anything.
  Until armed, keep writing the legacy way. (Ported from the codec's web design; cheap insurance
  against secure-storage write failures.)
- **Shredding = rotate-and-destroy the content key on purge, NEVER SQLite deletes.** Freed pages go
  to the freelist intact and WAL frames keep old copies. `PRAGMA secure_delete=ON` + WAL
  checkpoint/truncate discipline are defense-in-depth only; say so in comments, never claim
  delete=shred. Best-effort against flash wear-leveling — same honest caveat as web.
- **Rotation cadence — decide it, don't let it emerge.** Rotation re-seals every surviving record
  under the new key (codec doc, `plaintext_record_codec.dart:201-203`), so naive rotate-per-purge is
  O(all records) per deleted message — delete-for-everyone and expiry fire per-message in normal use.
  Binding rules:
  - Purge completion keeps TODAY's meaning: record removed from the store, commit-gated, instantly
    (all 0.0.135 semantics). Shredding is a SECOND, batched phase — the honest user-facing claim is
    "removed instantly, shredded within minutes", never "shredded before the purge returns" (that
    invariant would reintroduce the O(N) cost per message; rejected).
  - The shred obligation is DURABLE: the purge write also stamps rotation-pending (piggyback on the
    existing purge-backlog pattern), so a kill between purge and rotation cannot lose the obligation.
  - Debounced/batched: one rotation in flight at most; purges arriving mid-rotation fold into the
    NEXT one (never a queue of overlapping rotations / unbounded live kids). Trigger on idle window,
    N pending purges, or a bounded deadline (minutes, not "eventually") — whichever fires first, and
    also before the DB is considered clean at app background.
  - Alternative worth evaluating during implementation: key-per-conversation sharding — purge of a
    conversation destroys just its key with ZERO re-sealing, and per-message deletes re-seal only
    that conversation's survivors. More kids to manage, dramatically cheaper rotations. Implementer's
    choice; the cadence rules above apply either way.
- **Content-key loss = whole local history unreadable. Budget, don't deny.** The cache is NOT
  re-derivable: the Double Ratchet consumed the message keys (root CLAUDE.md §7), and for media the
  record holds the ONLY copy of `mediaKey`/`mediaIv` (frontend/CLAUDE.md §5). On loss: degrade to the
  existing retired-id "no longer stored" rendering, NEVER `[Decryption failed]`; emit a
  `CONTENT_KEY_LOST` diag via `E2ePersistentDiag` so the field rate is visible.
- **Migration:** incremental, resumable, commit-gated batches (never one atomic rewrite, never lazy-
  on-read — rationale in `plaintext_record_codec.dart`). After sealing a batch, DELETE the old
  SharedPreferences keys. File-level residue in the old XML is best-effort; document the honest-claim
  limit, don't promise it away.
- **JWT/refresh** move to `flutter_secure_storage` on native (small, independent; keep web on prefs).
- **Voice cache**: encrypt `audio_cache` files under the same content key (or store in the DB) so
  rotate-and-destroy covers them.
- All 0.0.135 purge machinery semantics MUST survive unchanged: commit-gated removals
  (`removeDecryptedContent` result objects), durable purge backlog, two-phase expiry on `ServerClock`,
  `getServedMessageIds` reconcile, 30-day retention, retired-id set, LRU. The storage seam is
  `EncryptionService._sharedPrefs` usage — replace the backend under it, not the semantics above it.

## Gotchas that will bite (paid for already, do not rediscover)

- **SQLCipher ships a native `.so`** — the `verify-apk-16k.mjs` gate in `build-android.ps1` will
  hard-fail the build if it isn't 16KB-aligned. Check the chosen package (e.g. `sqlcipher_flutter_libs`)
  BEFORE building the feature on it; if misaligned, the same linker-flag approach as
  `patch_webcrypto_16k.ps1` applies, but prefer a package that's compliant out of the box.
- `webcrypto` is PINNED to 0.6.0 (0.6.1 needs an MSVC toolchain on Windows) — don't let a new dep
  bump it transitively.
- `EncryptionService` serializes ALL per-peer session mutations on `_sessionTails`; the decrypted-
  content cache has its own coherence rules (`getDecryptedContentMany`, one reload per pass) —
  frontend/CLAUDE.md §5 lists every trap. Read it before touching the service.
- Full `flutter test` before any commit (project policy; ~1069+5 currently green). Never a file list
  (§1 cost curve). `flutter analyze --no-fatal-infos` clean.
- Tests: this is a permanent feature — regression tests are IN scope (armed-gate, key-loss degrade
  path, migration resume-after-interrupt, purge→rotation). Match existing test conventions.
- Windows builds: `build-android.ps1` stops gradle daemons before clean (locked `frontend\build`
  half-deletes otherwise); release lintVital is disabled repo-effectively via `:app`
  `checkReleaseBuilds=false` (verified: 0 lintVital tasks in the assembleRelease graph).
- Commit + push at checkpoints; feature branch + PR for this (it's big); never merge to master
  without explicit owner OK; check `gh run list` after pushes (CI is detection, not a gate).
- Session end: write `.cursor/session-summaries/YYYY-MM-DD-session.md` + update `LATEST.md` (size
  caps enforced by pre-commit).

## Acceptance (Phase 2 done means)

1. On a fresh native install, NO message plaintext, media key, pending-send record, or JWT is ever
   written outside the encrypted DB / secure storage (verify by dumping shared_prefs XML + app dirs
   on an emulator after real use).
2. Purge paths (delete-for-everyone, clear-history, unfriend/block, expiry, retention) stamp a
   DURABLE rotation-pending obligation with the purge; the batched rotation destroys the old key
   within its bounded deadline (survives kill-between-purge-and-rotation); afterwards old DB pages
   are ciphertext under a destroyed key. A burst of N per-message deletes triggers O(1) rotations,
   not N.
3. Simulated content-key loss (wipe secure storage entry on a test build) → app boots, history rows
   render "no longer stored", `CONTENT_KEY_LOST` in diags, NO crash, NO `[Decryption failed]`.
4. Migration from a pre-Phase-2 install: seals all existing records in resumable batches, deletes old
   prefs keys, survives kill-mid-migration.
5. `flutter analyze` clean, full suite green, `.\build-android.ps1` green incl. 16KB gate with the
   SQLCipher lib in the APK.
6. Web behavior byte-identical (all changes behind `!kIsWeb` or in native-only files).

## Out of scope

Web B2 sealing (canary-gated), sealed sender, `fetchPreKeyBundle` friendship gate (separate backend
quick win), Play Store, iOS, R8.
