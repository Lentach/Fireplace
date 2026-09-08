# 2026-09-08 — multi-device v2 (D26): the phrase becomes a key backup, the QR works both ways, the alarms get quieter

**Commit** `54f68a1` on `feat/passcode-lock` (PR #165 → master). **Version 0.2.23.** Spec:
`docs/design/multi-device.md` §12, amendment block **"2026-09-08 (D26)"** — items **(lxxvi)–(lxxix)**,
written and owner-ratified BEFORE any code ("agree on everything, green light").

## Why this release exists

Four things were wrong at once, and prod data proved three of them were not hypothetical:

- **114 users, 2 enrolled accounts, 0 linked devices, 0 reset requests ever** — but
  `identity_change_audit` had **3 rows**, all `[identity-churn] … via=unlocked`. Three real people
  wiped their browser data and silently re-minted an identity. For an ENROLLED account that same
  accident means a 72 h lockdown, and the recovery phrase only shortened it to 1 h.
- Linking "by QR" only worked if the primary happened to be an installed PWA on a camera phone: the
  new device displayed a ~96-char code and the primary had to **type** it. There was no in-app
  scanner at all (`pubspec.yaml` had `qr_flutter` only), and the native app had no `/link`
  intent-filter.
- "Contact's security number changed" fired as a RED alarm on events that were not attacks —
  adding a device never changes the account identity.
- The passcode lock could auto-lock in the middle of a link ceremony, and its erase warning told an
  enrolled user "messages stored only here will be lost" without mentioning that the account itself
  would need a 72 h reset.

## What shipped

**(lxxvi) passcode × multi-device.** `linkCeremonyActive` (`composer_keyboard_signals.dart`) gives
the ceremony the same auto-lock exemption the attach picker already had, at all three gates.
`PasscodeWrapHook.run()` runs after every adopt so freshly minted keys are wrapped instead of
sitting raw on a "protected" device. The lock screen's erase copy is enrolment-aware through a
CLEARTEXT prefs hint (`account_enrolled_hint_<uid>`, uid from the stored JWT `sub`) — the wrapped
store is unreadable while locked, so the copy cannot key off it. Only EXPLICIT `linkingEnabled`
values are recorded; the fail-closed absent⇒true default guards minting, not copy.

**(lxxvii) the QR is real, both directions.** `openProvisioning { role?: 'new' | 'primary' }`
(default `'new'`, byte-compatible). With `'primary'` the opener is the primary; the stage tracks
`primarySocketId`/`newDeviceSocketId` explicitly, the hello relay carries the assigned `deviceId`,
and `provisionDevice` from a non-primary is refused `not_primary`. Code v2 is
`fp-link.v2.<id>.<b64url ephPub>.<platform>.<p|n>`; v1 still parses (as `n`). **The wire field stays
`ephPubP`** for v1 compatibility even though it now means "the hello party's ephemeral", and the SAS
transcript order stays fixed N-then-P — the role names which slot a key fills, and the server is not
a crypto input. Both screens show a QR and can scan one: `mobile_scanner` on Android/iOS, and on web
an in-repo `getUserMedia` + `BarcodeDetector` path with a **vendored** jsQR fallback
(`frontend/web/jsqr.js`, Apache-2.0). **The web scanner never fetches a decoder from a CDN** — that
is why `mobile_scanner`'s own web scanner is not used. Camera denied/unsupported falls back to the
typed field, which stays. Android gains an autoVerify VIEW intent-filter for `/link` plus a
`fireplace/link` MethodChannel (cold start + `onNewIntent`), replacing
`link_fragment_stub.dart`'s null.

**(lxxviii) the recovery phrase is a KEY BACKUP.** I1 is amended: the server may hold IK +
`registrationId` + DAK, but ONLY as AES-256-GCM sealed under PBKDF2-HMAC-SHA256(600 k) over the
NFKD-normalized phrase with a 16-byte salt (migration `0017_identity_backup.sql`, columns on
`recovery_keys`). **Signed/one-time prekeys are deliberately NOT sealed** — they rotate and burn, so
a stale copy would be worse than none. Wire: `setRecoveryKey { phrase, backup }` writes verifier and
blob in one transaction; `getIdentityBackup` serves it back; `ownKeyBundleStatus.hasIdentityBackup`;
`uploadKeyBundle { restoreSignature, nonce }` where the proof is XEdDSA by the CURRENT IK over
`identityPublicKey ‖ userId ‖ nonce`, accepted **only when the uploaded identity equals the stored
one**. A restore purges the device's one-time pre-keys, re-homes material onto a fresh device id,
reissues the session, revokes superseded devices as `reason:'restored'`, and writes **no audit row /
raises no §6.0 alarm** — nothing changed. The phrase is now **mandatory** when enabling linking,
with a random-word confirmation; `enableLinking` split into `mintDak()` + `enableLinking()` because
the blob carries the DAK and must be sealed first. A wiped install gets a "I have my phrase" door on
the lockdown gate.

**Restore order is load-bearing** (root `CLAUDE.md` §7 "§6.2 recovery REBIND"): fetch → unseal
(wrong phrase stops here, spending nothing server-side) → adopt → nonce → upload with proof → ride
the EXISTING rebind (adopt session + reconnect) → **only then** upload OTPs → re-sign the roster at
the server-named `nextListVersion` with the preserved DAK → `requestSessionRebuild` per peer.
Accepted consequences, stated to the owner: a fresh bundle under the same identity, one lost
in-flight message per peer (healed by the existing rebuild path), old history stays unreadable, and
phrase possession = takeover (Signal's PIN/SVR posture). The 72 h reset stays for accounts with no
phrase; **72 h was NOT shortened** and "QR as login without a password" stays out of scope (I3).

**(lxxix) the peer key-change surface is demoted.** `SettingsProvider.keyChangeWarnings` defaults
**false**: the auto-ackable detection paths (server `peerIdentityChanged`, local TOFU
`isTrustedIdentity`) become a muted, persisted line and are auto-acknowledged.
**Refusals stay fail-closed** — `_recordAccountIdentityRefusal` is NOT auto-acked, because
auto-adopting a mismatched served key would dissolve the (xxxix) anchor and put a *dismissible*
banner over a live MITM. An in-memory `peersRefusedIdentity` set makes the red pill render
unconditionally for refused peers; the OWN-account banner is never demoted.

## Verification

- **frontend 2027 / 14 skipped**, **backend 1096 / 62 suites**, **e2e wire 46 / 9 skipped** — all
  green; both count verifiers re-run against the captured logs. Lint ratchet real errors
  **906 → 894**, floor lowered.
- Falsifications F1–F12 each proven by a printed mutant (restored, substitution count stated) or a
  fails-without-the-change test. Two I ran personally after taking the client work over:
  hoisting the nonce request above the unseal → F10 fails at the "no nonce" assertion; dropping the
  `?? now` tombstone in the restored roster → the happy path fails on `byId[1]!.revokedAtMs`.
  E2eWire2's wire falsification: `key-bundles.service.ts:251` `if (!proofValid)` → `if (proofValid)`
  admitted a **stranger's** proof as `authorizedBy:'restore'` (3 of 4 restore tests failed) — line
  restored and re-verified.
- **Live drive on a real bundle** (the only proof the owner accepts), app-mode Chrome for
  `display-mode: standalone`: mandatory phrase + wrong-confirm-word refusal → sealed backup in
  Postgres (496-char blob, 600 k iterations, v1) → enrolled; **browser-data wipe → restore from
  phrase** → `[identity-restore] proof verified`, 20 OTPs purged, device 1 → 3, identity
  **byte-identical**, **no new audit row**, DAK preserved and roster re-signed to v2 (device 1
  revoked, 3 live); **flipped QR ceremony** with the primary displaying a `.p` code and the new
  device ingesting it — SAS **814 098** on both sides, device #4 linked; enrolment-aware passcode
  erase copy on the lock screen; the demoted key-change row present and **off** by default.

## Things found on the way that were NOT the assignment

- **`test_e2e/full_stack_e2e_test.dart` had 4 unfixed `LinkOobCode.ephPubN` callsites** from the
  `ephPub` rename — the default e2e run was RED and the CI `e2e-wire` job would have failed on the
  push. Batch-2 agents only ran `test/`, never `test_e2e/`. **Run the analyzer over `test_e2e` too
  after any lib rename.**
- **`e2eSql`'s default container was `fireplace-0a-db-1`** — the ABANDONED sibling worktree's stack.
  Every SQL-backed test failed locally with "container is not running" on a normal checkout (CI is
  fine: it resolves `docker compose ps -q db`). Default is now `fireplace-db-1`.
- **`git add -A` swept 51 files out of the owner's ignored-by-intent `local/` scratch dir** into a
  staged release — there was no `local/` rule in `.gitignore` at all, and my first `git check-ignore`
  read of it was WRONG (an advisory caught me). `local/` and `frontend/test-output.txt` are now
  ignored. **Read `git status --short` before every commit; never trust a single check-ignore line.**
- `mintDak()` failing left the user tapping "Włącz łączenie" with **nothing happening** (the
  pre-(lxxviii) order at least rendered the enroll error). It now sets `enrollError` and rethrows.
- The non-rebind branch of `keyBundleUploaded` lacked the `restored` guard its sibling had, so a
  restored ack without tokens would have minted a replacement enrollment and discarded the very DAK
  the backup preserved. Guard made symmetric.
- Stale copy: the enable-linking dialog still said the phrase would be *offered*
  ("zaproponujemy") after it became mandatory. Fixed in both ARBs.
- Three tests in `devices_screen_web_install_test.dart` pinned the pre-(lxxviii) enable order
  (confirm → immediate enroll, phrase as a post-ack *offer*). Rewritten to the new contract,
  including an F9 test that backing out of the phrase screen enrolls nothing.

## Traps paid for again

- **Agents on `claude-fable-5` hit a 429 with `retry-after` ≈ 4.8 h.** Owner's call: switch
  `modelRoles.task` in `~/.omp/agent/config.yml` to `anthropic/claude-opus-5:medium`. Two probes
  confirmed spawning before delegating real work again.
- **Two batch-2 subagents died at exit 1 on mega-edits** (~9 min and ~22 min in) with their work
  half-landed and never analyzed. The respawn instruction "edit in ≤60-line hunks, analyze every few
  edits" survived. **A dead agent's claims are worthless until the analyzer and the tests run.**
- `flutter test` needs `cmd /c`; `display-mode: standalone` **cannot** be emulated via CDP
  `Emulation.setEmulatedMedia` (only `prefers-color-scheme` takes) — launch Chrome with `--app=` and
  attach over `--remote-debugging-port`.
- The `/auth/register` 10/h/IP bucket was exhausted three times between the e2e agent and my drive;
  `docker compose restart backend` clears it, but the container needs **~2 min** to recompile and
  bootstrap before `/health` answers 200 (it reports `unhealthy` and refuses connections until then).
- `hub restart` reuses the RETAINED launch spec — restarting a dead static server resurrected an old
  Python server on a stale directory serving `0.2.17`. Start a fresh name instead.
