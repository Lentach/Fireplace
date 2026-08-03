# Session 2026-08-03 — recent-change audit, Signal-grade gap review, FLAG_SECURE + incognito keyboard

Owner asked: (1) verify the recent e2e/ledger and Android changes aren't sloppy regressions,
especially for the PWA; (2) audit what "Signal-grade" requires; (3) start on the practical hardening.
He also supplied the **E2ePersistentDiag dump** (first field evidence since 0.1.1 went live).

## Verdict on the recent changes — PWA is SAFE

Independent reviewer (Anthropic-class, read-only) traced `ac880f6..ded8e1a` on the web path,
verdict **correct / no regressions, confidence 0.9**:

- All three ledger fail-open rules hold with file:line evidence: record only after confirmed
  `setString` commit with the failed-label filtered (`encryption_service.dart:1000-1002, 1651-1660`);
  tri-state `recordExists` on `_authoritativeSnapshot()`; edits drop entries via
  `invalidateDecryptionCache` → `forgetDecrypted` (`encryption_provider.dart:240-244`).
- The ONLY permanent-destruction path requires `exists == false && replayable == false`
  (`messaging_provider.decrypt.dart:1002-1024`); undetermined answers change nothing. Verified
  independently by the main agent from the raw diff.
- All 4 earlier review defects (2 CRITICAL) confirmed fixed with falsified regression tests.
- Ledger bounded (`_ledgerCap` 3000, ~27KB); backfill seeds only ids that HAVE records, from the
  authoritative snapshot; empty seed writes no marker (8415b31). LOW note: a *partial* non-empty
  snapshot still writes the marker — fails safe (un-seeded ids revert to old behaviour, self-heal).
- Two Codex-backed subagents died (`usage_limit_reached`) and one security-reviewer was blocked by
  a policy misfire; **owner directive: use Anthropic models only for subagents in this repo.**
  Their scopes (Android audit, gap analysis) were done inline by the main agent instead.

## Diag dump analysis (owner's live PWA, 08-03)

1. **`CANARY_OK {ageDays: 5}`, zero `CONTENT_KEY_CANARY_LOST` durable entries → B2 web sealing is
   UNBLOCKED.** This is positive survival evidence (5 days across restarts), not mere absence.
2. **`LEDGER_RECORD_LOST` × 5 fired on the ledger's FIRST DAY live** (08-02 23:55:12; msgIds
   19139/19186/19187/19189/19190, all senderId 60). This is exactly the watch-item from the 0.1.1
   handoff. Analysis narrowed it to two candidates:
   - The retired check (`decrypt.dart:950`) runs BEFORE the ledger gate, so retention/LRU noise is
     ruled out. LRU also ruled out empirically: `PLAINTEXT_RECONCILED {stored: 138}` — far under
     the 2000 cap.
   - **Candidate A (benign): expiry-sweep race.** `sweepDestroyablePlaintext` marks only the
     `retired` class; the `expired` class is purged WITHOUT `markRetired` and WITHOUT dropping the
     ledger entry (`encryption_provider.dart:362-366`; `_runPurge:630-641` never touches
     `_decryptedLedger`; the only ledger-removal path is the edit invalidation at `:241-244`).
     An expired-TTL message the server still served at that moment fires the gate. Cosmetically
     correct (the message was supposed to die) but it pollutes the durable diag.
   - **Candidate B (serious): genuine record loss** — the exact class the ledger was built to
     catch, on the very peer (60) from the July incident.
   - **Discriminator, owner-only:** does the peer-60 chat use disappearing messages, and are there
     5 "no longer stored on this device" rows he expected to be readable? Ask before anything else.
3. Peer-60 chat remains troubled: msgIds 19102/19105/19106 fail `duplicate` on EVERY boot since
   08-02 (last seen 08-03 01:10) — permanent `[Decryption failed]` rows, pre-ledger damage class.
   Peers 92/93 badMac clusters are 07-31, pre-0.1.1 — historical.
4. `PEER_IDENTITY_CHANGED {peerId: 90}` 07-31 — owner should fingerprint-verify peer 90.

**Recommended follow-up (NOT implemented — destructive-adjacent, needs owner OK + independent
review):** the expired class in `sweepDestroyablePlaintext` should `markRetired` like the retention
class (or at minimum drop its ledger entries — but bare `forgetDecrypted` would re-arm the
DuplicateMessage burn if the server re-serves, so retire is the right direction). Until then,
expect occasional benign `LEDGER_RECORD_LOST` noise in TTL chats.

## Android release audit (done inline)

Strong: `allowBackup=false` + full `data_extraction_rules.xml` exclusions; loopback-only netsec;
release-signing hard gate + null signingConfig fallback; minimal permissions; data-only FCM payload
(no plaintext, `push-notifications.service.ts:96-100`); targetSdk 36. Unchanged blockers:
`FIREBASE_SERVICE_ACCOUNT` absent (push dead), keystore single-copy, real-phone smoke not run.

## Changes shipped this session

1. **`MainActivity.kt` — FLAG_SECURE** (screenshots/recording/recents-thumbnail blocked), gated on
   `ApplicationInfo.FLAG_DEBUGGABLE` — NOT `BuildConfig` (buildConfig generation is off under
   AGP 8). Debug builds keep screenshots for emulator work; release AND profile are protected.
   Compile-proven: `flutter build apk --debug` green. **Add to the device smoke checklist: a
   screenshot attempt in the release APK must be refused/black.**
2. **Incognito keyboard** (`enableIMEPersonalizedLearning: false`): composer
   (`chat_input_bar.dart` — also covers message EDITING, which reuses this field) and secret-note
   input (`anti_quantum_note_dialog.dart`). Android-IME hint; no-op on web/iOS — PWA unaffected.
   **NOT app-wide** (Signal's setting is): GIF-search and contact-search fields still learn;
   password fields are implicitly exempt via `obscureText`. Extend if the owner wants parity.
3. **Hacker-mode "Storage sets" inspector** (`privacy_safety_screen.dart` + 
   `EncryptionProvider.diagStorageSets`): displays disk-truth count/min/max/last20 of the
   retired set, decrypt ledger, and stored-record ids, with full-list copy. Built because the
   owner's production device is an **iOS Safari PWA — no devtools exist**, and dating his last
   local-history wipe via the retired set's id range is the discriminator for the
   LEDGER_RECORD_LOST investigation. Ids only, never content. Server rows for the five ids
   confirmed intact (sent 08-01 by maoi, expire 08-05, not hidden) — **TTL race ruled out**;
   remaining split: wipe-on-08-02 (benign, in-memory staleness defect at
   `encryption_provider.dart:551-563` — wipe never syncs `_retiredIds`/`_decryptedLedger` RAM)
   vs genuine record loss. The panel's retired-set id range decides it.

Verification: `flutter analyze` clean; input-widget suite 90/90; screens suite 76/76; full suite
**1134 + 10 skipped** green twice (after hardening, after panel). No new tests (no new observable
contract). Test counts unchanged. **RELEASED as `0.1.3 / 7dc0a9e`, frontend only, CI green 4/4
pre-deploy, smoke 5/5** (health, version.json 0.1.3, backend 0.1.2 unchanged, bundle commit
verified, app boot). Owner deploy OK given in-session ("go").

## Signal-grade roadmap agreed with owner (scope: practical, not full metadata resistance)

Done now: FLAG_SECURE, incognito keyboard. Next in order: (1) owner: keystore backup +
`FIREBASE_SERVICE_ACCOUNT`; (2) resolve LEDGER_RECORD_LOST discriminator; (3) web B2 sealing (now
canary-unblocked); (4) delete-for-me hard-delete (backlog #3); (5) expiry-sweep success diag
(backlog #4); later/optional: app lock (`local_auth`), cert pinning. Explicitly out of scope by
owner choice: sealed sender, encrypted cloud backups.
