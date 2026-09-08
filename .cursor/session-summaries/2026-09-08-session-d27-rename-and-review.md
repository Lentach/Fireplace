# 2026-09-08 (part 2) — D27: rename linked devices, four defects D26 shipped, and a two-axis review that caught a fifth

**Deployed both tiers as 0.2.24** — frontend `0.2.24 / 8908814`, backend `0.2.24 / 89088143`, smoke 5/5.
Commits `25fdc25` (D27) + `b21e278` (review fix, (lxxx) clause 6) + `8908814` (prettier).
Spec: `docs/design/multi-device.md` §12, amendment **"2026-09-08b (D27)"** = item **(lxxx)**, clauses
1–6. Written and shown BEFORE the code, as always.

## What the owner asked for

One line: **"let user rename linked devices."** That is clause 1. The other five clauses are defects
the earlier D26 release (0.2.23, shipped the same day) either introduced, exposed, or left behind —
folded into this release because they live in the same screen and the same backend deploy.

## Clause 1 — device rename

**It needed no wire and no server change**, which is the whole reason it was cheap:
`DeviceListEntry.name` has been in the canonical encoding since §3 (sorted key, 64-char cap,
control chars rejected), and `updateDeviceList` already accepts any DAK-signed list at a higher
version — `applySignedListUpdate` constrains only `userId`, the signature and version monotonicity.
So a rename is exactly the `revokeDevice` shape with `name` set instead of `revokedAt`, on the
existing event, answered by `deviceListUpdated`, with the server's own `deviceListChanged` broadcast
refreshing the other installs.

Rules that are not obvious and are pinned by tests: the engine is armed from the Keystore FIRST (the
lesson `revokeDevice` learned from a live app-proof — signing without it throws and nothing leaves
the device); a REVOKED row cannot be renamed (a tombstone must not spend a list version); an empty
field CLEARS the name and must reach **byte-identical canonical output to a list that was never
named**, not `""`.

**NFC was the one real design decision.** The storage gate refuses a name that is not
NFC-normalized, and the encoder's own header has promised since §3 that "when the rename UI lands,
the client-side NFC normalization lands with it". It landed as a **refusal, not a normalization**:
Dart core ships no Unicode normalizer, and the alternative was hundreds of KB of Unicode tables in a
PWA bundle to tidy a device label. `isSignableDeviceName` rejects the combining-diacritic blocks
that decompose Latin/Greek/Cyrillic — the only way these users produce non-NFC text, i.e. a paste
from macOS/iOS — and deliberately leaves alone marks that are NORMAL in NFC for other scripts
(Arabic, Hebrew, Indic vowel signs are in different blocks). It refuses BEFORE signing, so no
version is spent, and it says "type it instead of pasting" — "try again" would be a dead end because
retyping the same paste fails identically. Accepted false positive: a Latin base + mark with no
precomposed form (`z` + U+0308) is refused despite being valid NFC.

**This is the one rename defect a live drive cannot reveal** — CDP types precomposed text — so it
came from reading the server's validator, not from clicking.

## Clauses 2–5 — what D26 got wrong

- **Clause 2, the "primary" badge was keyed on `deviceId == 1`.** Every §6.2 reset and every
  (lxxviii) restore re-homes the surviving install onto a FRESH id and revokes the old one, so the
  live primary lost the badge and the REVOKED device 1 kept it. I saw it live on the 0.2.23 drive
  (`web · #3` with no badge) and mis-filed it as cosmetic; an advisory pushed back, correctly. The
  signed list carries no `isPrimary` field and must not grow one, so the badge is derived: **the
  lowest non-revoked deviceId**, the same row login resolves.
- **Clause 3, the flipped ceremony recorded `platform: 'unknown'`.** (lxxvii) let the primary open
  the ceremony, and in that direction the new device's label reaches the primary only through
  `provisioningHello` — which carried nothing but the id and the ephemeral. Optional `platform` on
  the DTO, relayed beside `deviceId`. Absent ⇒ `unknown`, so older clients are unaffected.
- **Clause 4, copy that understated the feature.** Two LIVE strings still promised the
  pre-(lxxviii) terms: the enable-linking dialog said recovery needs "a reset: 72 hours, or 1 hour
  with a recovery key" **in the very dialog about to demand a phrase that restores instantly**, and
  the gate's reset hint repeated it directly above the instant restore door. Both now call the reset
  the last resort and point at the phrase. Three (lxxiii)-era keys carrying the same stale promise
  were DELETED, not reworded (`identityDamagedBody`, `identityUploadLockedBody`,
  `recoveryKeyExplainer` — no reader since the gate replaced the banners).
  `recoveryPhrasePromptBody` KEEPS its "72 → 1": it belongs to the reset ceremony, where a phrase
  genuinely only shortens the wait.
- **Clause 5, the restored install alarmed itself.** Seconds after the 0.2.23 restore drive
  succeeded, the shell raised the RED own-account banner. The row it reported predated the restore,
  but the wipe destroyed the install's dismissal watermark, so connect-time hydration re-raised a
  change the user had already lived through — in the one flow whose promise is that nothing happened
  to their account. Fix is **content-based, never a suppression flag**:
  `latestIdentityChangeAt` → `latestIdentityChange` returning `{at, to}`, `ownKeyBundleStatus`
  carries additive `identityReplacedTo`, and a row whose new key equals this device's own published
  identity is ignored while a row ending anywhere else still alarms.
  **I first reached for the existing one-shot `markOwnIdentityPublished` flag and an advisory caught
  it**: a restore reports `identityChanged: false`, and an account with no audit row sends no
  instant at all, so `normalizeServerInstant` bails BEFORE the flag is consumed — the flag would sit
  armed in prefs and silently eat the first genuine replacement that ever arrived. Reverted before
  it ran; the content rule can only ever suppress a row already ending at our own key.

## Clause 6 — what the review caught, and it was the worst of the day

The user asked for a review at the end. Two `reviewer` agents ran in parallel on
`git diff 4608c2e...HEAD` (D26 + D27), one on **Standards** + the Fowler smell baseline, one on
**Spec**. Spec came back clean on all six load-bearing claims after I made it itemize them
(its first answer was a bare "correct, 0.82 confidence", which is not actionable), and I verified
its two self-declared doubts myself rather than take them: the three dead ARB keys really are gone
from both locales and the generated files, and the `identity_restored` push really is awaited before
`dropAccountPushRows`.

**Standards found a genuine stuck-state bug, live in 0.2.23:** `restoreFromPhrase` cleared
`_identityIncomplete` the moment `adoptRestoredIdentity` returned — four stages before done. That
flag feeds `needsDeviceLink`, which mounts the gate that **hosts this machine's own progress and
error surface**. So the shell appeared as soon as the identity landed, and a failure in any
remaining stage (20 s nonce wait, 45 s upload ack, roster re-sign) reported itself to an unmounted
widget. Invisible — and permanent: on re-entry `adoptRestoredIdentity` saw a held identity, and a
keyless install has neither `deviceMaterialMismatch` nor `identityUploadLocked`, so
`disposeStaleMaterial` was false and it threw `already holds an identity` on **every** retry. The
install kept a locally adopted identity whose fresh signed prekey and OTPs were never published —
peers kept fetching the stale server bundle, so first-message decryption broke — with no route back.

Two narrow changes: the flag is cleared only at `done` (release recorded as
`RESTORE_GATE_RELEASED`, the one restore step a field report could not otherwise place), and a
re-adopt of the IDENTICAL identity is idempotent instead of fatal — a DIFFERENT held identity is
still refused, because disposing that one needs the (lxv)/(lxvii) authorization the caller passes.

**The lesson worth keeping is about the test, not the bug.** My first regression asserted on the
diag marker, and the early-clear mutant **SURVIVED** it — the test pinned the marker's position, not
the behaviour the marker stands for. An advisory called it out. The rewrite starts from the REAL
gated state (no local identity + a server that says a bundle exists, driven through
`checkOwnKeyBundle`) and asserts on `needsDeviceLink` itself; both mutants then fail.

## Clause 6 needed a THIRD change, and an advisory caught it

Clearing the flag late only covers failures BEFORE the rebind. The rebind’s own reconnect re-runs
E2E init, and the init success path clears `identityIncomplete` itself
(`encryption_provider.dart:1384`) — so a failure at `listing` or in the
session-rebuild sweep, both AFTER the rebind, dismissed the gate again with the same consequence.
`needsDeviceLink` now carries `restoreUnfinished` (`_restoreStage` neither
`idle` nor `done`) as an INDEPENDENT reason to hold the gate, which also covers a
`failed` restore — precisely the state the user must be able to see and retry. Shipped as
**0.2.25** (web only: zero backend files differ from 0.2.24, verified with
`git diff --name-only 89088143..HEAD -- backend/`).

**Two failed attempts at the test, both instructive.** Modelling the rebind inside the
`uploadKeyBundle` branch DEADLOCKED the harness — the machine awaits the upload ack, which
awaited an init that awaited its own `checkOwnKeyBundle` answer scheduled from the same
callback; the run hit a 900 s timeout. An earlier variant passed VACUOUSLY because the harness
never re-ran init at all, so the mutant survived. The kept test drives the predicate directly: a
provider whose init SUCCEEDED (so `identityIncomplete` is false), then a restore failed
at `fetching`, must still be gated. Fast, non-vacuous, and it dies on the mutant.
**A hanging test is worse than no test.**

## Verification

- frontend **2055 / 14 skipped**, backend **1102 / 62 suites**, analyzer clean on lib + test +
  test_e2e; both count verifiers re-run. CI green on all 5 jobs (run `34240058258`).
- Falsifications, each printed and restored, 1 substitution apiece: F13 (DAK arming), F14 (cleared
  name byte-identical), F15 (badge on 3 not revoked 1), F16 (hello without `platform`, asserted on
  key ABSENCE), F17 (foreign key still alarms), F19 (NFC check), F20/F21 (clause 6, both legs), plus
  the no-rebind `restored` guard whose mutant minted a replacement enrollment and discarded the DAK
  the phrase backup preserved.
- **Live drive on a rebuilt bundle:** rename stored in the signed list at v2 (`"name":"Laptop
  Zósi"`), clearing it dropped the `name` key entirely at v3, a DECOMPOSED paste refused before
  signing with its own copy while the precomposed spelling of the same name went through, both fixed
  copy strings read correctly in place, and after wipe→restore the roster showed
  `web · #3 · główne` with the revoked `web · #1` struck through and unbadged.
  **Clause 5 was NOT exercised live** — the drive account had zero audit rows, so there was nothing
  to suppress; it rests on three unit tests, the F17 mutant and the backend spec.

## Traps paid for this half

- **`String.replace` treats `$` in the REPLACEMENT as special.** My doc patch contained
  `` {1,32}$` `` — that is `` $` ``, "insert everything before the match" — so it spliced a second
  copy of `CLAUDE.md` into itself, twice, and I blamed a phantom file watcher and an earlier shell
  mangle before finding it. **Use a replacer function (`() => to`) for any replacement containing
  `$`.** A no-op read/write round-trip is the cheap way to prove the write path is innocent.
- **`git add -A` swept 51 files out of the ignored-by-intent `local/` scratch dir** into a staged
  release — there was no `local/` rule at all, and my first `git check-ignore` read was WRONG.
  `local/` and `frontend/test-output.txt` are ignored now. Read `git status --short` before committing.
- **The `edit` tool needs a tag from a `read`, not from `grep`.** Two hunks landed in the wrong
  function on stale tags — one corrupted `_confirmRevoke`'s dialog. Re-`read` after any agent
  touches a file you are about to edit.
- **CI's lint ratchet is a release gate.** Hand-formatted backend edits pushed prettier deviations
  157 → 171, past its ±5 tolerance, and failed the run AFTER the tests passed. Fixed by prettier-ing
  only the 15 files the release already touched (a whole-tree run would bury the diff); count landed
  at 153 and the floor was lowered.
- **Master moves under you.** Dependabot landed 5 commits mid-session (including a firebase major),
  so I rebased twice and re-ran both suites and the analyzer after the dep bump. `master` is held by
  the dead `fireplace-0a` worktree, so landing a commit on it needs
  `git checkout --detach origin/master` + cherry-pick, or a rebase + `push HEAD:master`.
- Docker Desktop's host mount wedged with `mkdir /run/desktop/mnt/host/c: file exists`; only a full
  Docker Desktop restart + `wsl --shutdown` cleared it. The backend container then needs **~2 min**
  to recompile and bootstrap before `/health` answers.

## Open, deliberately not done

- `/.well-known/assetlinks.json` on the VM so the Android `/link` filter auto-verifies.
- A video self-sync **receive** test (only a text envelope is proven).
- **D** (hide `none_for_device` rows), **E**-remainder, thief-matrix **Q2/Q3**, **F**.
- Clause 5 has no live proof (see Verification).
