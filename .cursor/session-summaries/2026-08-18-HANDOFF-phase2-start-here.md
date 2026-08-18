# HANDOFF — 0a + 0b + Phase 1 are DONE and reviewed. You are starting Phase 2.

**Date:** 2026-08-18 · branch `feat/takeover-alarm-0a` · worktree
`C:/Users/Lentach/Desktop/fireplace-0a` · HEAD `edd3bb4` · **nothing merged,
nothing deployed** (owner's ruling: the whole program accumulates on one branch
and merges once, at the end).

Three phases are on this branch, each gate-reviewed by three independent
reviewers, all findings fixed:

| Phase | What it is | Gate |
|---|---|---|
| 0a | identity-replacement alarm (audit row, session/peer/push notice) | reviewed, live-fired |
| 0b | registration lock §6.1, reset ceremony §6.2, recovery key §6.2.1, enrolment UI | 3 reviewers, PASS; 6 defects fixed |
| 1 | per-device key material, sessions, messages (§4/§5.1/§8) | 3 reviewers, PASS; 4 defects fixed |
| final | whole-program pass before this handoff | 3 reviewers, PASS; 1 fix + these notes |

**Do NOT rebuild any of it.** Read this file, then
`docs/design/multi-device.md` §5 (the Phase 2 protocols) and
`2026-08-17-HANDOFF-multidevice-execution.md` (client-side landmines, still
valid).

---

## 0. Before you write a line of Phase 2 code

Spec §9 requires **a Phase-2 spec review of its own** before implementation —
provisioning, DAK, signed device lists, envelopes, self-sync and revocation are
where this design is most likely to be wrong, and they are the parts nobody has
reviewed yet. Do that first, then build.

Owner's standing rules (all still binding):

1. **Investigate and PROVE, then ASK before writing code.** Diagnostics count.
2. **Ask before opening the browser tool** — every time.
3. **Never merge or deploy without an explicit OK.**
4. **Never self-review** — use `reviewer` subagents, defensive framing.
5. Anthropic-only subagents, writer concurrency ≤ 2.
6. Format only the files you touched; never `dart format lib/`, never a
   `prettier --write src/**` glob (that reformatted three untouched files here).

---

## 1. The five things that will bite you in Phase 2

Consolidated from the final three reviewers. None is a bug on this branch;
every one is a precondition Phase 2 builds on.

### 1.1 deviceId 1 is currently REUSED across a reset — §5.3 says it must never be

Phase 1 pins every session to device 1 (`auth.service.ts`, `DEFAULT_DEVICE_ID`).
A user who loses their keys and completes the reset ceremony comes back as
device 1 again. §5.3 states device ids are monotonic and **never reused,
including across a §6.2 reset**, because the device-gated legacy fallback
treats `deviceId == 1` as "the original owner of this row" and serves it the
legacy ciphertext. Wire that gate on top of today's behaviour and a
post-reset device gets served the PRE-reset device-1 history and attempts a
foreign-ratchet decrypt — the terminal `[Decryption failed]` the gate exists to
prevent. **Phase 2 must allocate a fresh monotonic deviceId on reset/recovery.**

### 1.2 The identity lock's "lowest deviceId == the account identity" shortcut

`key-bundles.service.ts` reads ONE bundle (`order: { deviceId: 'ASC' }`) to
decide what the account's identity is. That is sound today only because all of
an account's devices share one IK and `purgeSupersededDevices` deletes the
others the moment an authorized change lands. If Phase 2 ever allows a
persistent window where devices legitimately publish different identity halves,
this comparison reads a stale row. Keep the purge atomic with the identity
upsert and never introduce a divergent-identity window.

### 1.3 `purgeSupersededDevices` drops key material only

It deletes other devices' `key_bundles` and `one_time_pre_keys` — not their
`devices` rows, `refresh_tokens`, or push registrations. After a §6.2 reset
("all devices lost"), a device that is actually still alive keeps a valid
session and a live push endpoint; its uploads are refused by the lock, but it
still receives the account's notifications. Phase 2 revocation must fold
session + push + device-row invalidation into the same transaction as the
signed list mutation. The purge also runs AFTER the upsert rather than with it,
so a crash between them leaves stale sibling bundles until the next authorized
change.

### 1.4 Two wire fields exist server-side that the app never sends

- **`sendToken`** — the server accepts, stores and de-duplicates it (same
  conversation → re-ack; different conversation → `duplicate_send_token`), but
  `grep sendToken frontend/lib` returns nothing. A lost ack today behaves
  exactly as it always has. Minting tokens in the real send path is §5.4 work.
- **The registration-lock SIGNATURE path** (`getRegistrationLockNonce` →
  `identitySignature`) — harness-only for the same reason: a device that lost
  its keys cannot sign with them. In the live app the only route through the
  lock is spending a completed reset ceremony. A signed rotation is §6.3.

Do not assume either is exercised by real users.

### 1.5 Scaffolding that is written but never read

`devices` rows are created and touched on every connect, and
`refresh_tokens.device_id` / the push tables' `deviceId` are populated — but
nothing READS them yet (`DevicesService.listForUser` has no caller). The
device-list, per-device revoke and per-device push targeting surfaces are yours
to build. Likewise `originDeviceId` is stored and echoed in every message
payload, but the Flutter `Message` model does not parse it — self-sync scoping
(§5.4) has to add that first.

---

## 2. State of the tree

```
edd3bb4 docs: sendToken is server-side only — no production client emits one yet
e889495 fix: bind key uploads to the session's device, and make sendToken honest
d08d4ab feat: Phase 1 — key material, sessions and messages become per device
2bf60ea fix: stop the recovery path alarming its own user, and say every refusal out loud
ed77faa fix: close four 0b defects found by the live-fire and the phase-gate review
b0d8d42 docs: fresh-agent handoff + fix two late hygiene defects in 0b
7ab6495 feat: recovery-key enrolment UI
d79feb5 fix: do not warn a device about the identity replacement it performed
4475e0f test: Phase 0b wire harness + fix the recovery flow 0b silently broke
321f530 feat: Phase 0b frontend
07c4a39 feat: Phase 0b backend
50434a8 docs: 0a evidence   ← Phase 0a ends here
```

Green as of this handoff: **backend 769 / 52 suites**, **frontend 1371 / 10
skipped**, `flutter analyze` clean, **wire harness 24 / 2 skipped** against a
real backend + Postgres, **lint ratchet PASS at 906**.

```bash
cd backend && npm test
node ../scripts/lint-ratchet.mjs                 # must stay ≤ 906
cd frontend && flutter analyze --no-fatal-infos && flutter test
# wire harness (stack up, throttle reset):
docker compose restart backend && sleep 240
cd frontend && E2E_BASE_URL=http://127.0.0.1:3000 flutter test test_e2e
```

---

## 3. Traps this program paid for — do not re-pay them

- **`nest --watch` recompiles WITHOUT relaunching.** The container logs
  "Found 0 errors" while nothing listens on `:3000`; the wire suite then hangs
  for as long as you let it. `docker compose restart backend`, then poll
  `/health` for up to 4 minutes.
- **`localhost:3000` is broken on this PC** — a stale `wslrelay.exe` squats
  `[::1]:3000`. Always `127.0.0.1:3000`.
- **`flutter run -d web-server` serves exactly ONE debug client.** A second tab
  gets a blank scaffold and `Failed to create WebSocket debug connection`.
  Multi-client UI work needs `flutter build web --release` plus a static server,
  and two different origins (`127.0.0.1` vs `localhost`) for two storages.
- **CanvasKit accessibility** is empty until the `flt-semantics-placeholder` is
  clicked; `tab.click('aria-ref=…')` can still time out on canvas buttons — read
  the `flt-semantics` bounding box and use `page.mouse.click`, remembering
  screenshots are DPR-scaled (multiply by `viewport / screenshotWidth`).
- **`/auth/register` is 10/hr per IP** and the wire suite spends nine. Put new
  wire tests in a file that already owns accounts, or restart the backend to
  reset the in-memory counter.
- **`synchronize` drops indexes the entity does not declare.** Every index in a
  migration MUST be mirrored on its entity or dev and CI silently lose it —
  this cost the 0b one-pending guard and was only caught by hand.
- **Direct `flutter` spawn fails with os error 193** — use `cmd /c flutter …`.
- **Never give `flutter test` a file list** (per-argument compile cost).
- **Migration `0015` is not code-reversible** — see root `CLAUDE.md` §6 before
  any rollback.

---

## 4. Owner-blocked, still open

- **CI is BACK — the blackout was billing and it is fixed on master.** A
  parallel session measured it (2084 billable minutes since Aug 1 against the
  2000-minute free private-repo allowance, which is why jobs died in 2–4 s with
  `steps: []`), the owner flipped the repo **public** after a clean
  full-history secret audit, and PR #147 added `paths-ignore` for prose-only
  commits plus `concurrency: cancel-in-progress`. Unlimited runners now.
  **This branch still showed no runs for a different reason: it had drifted
  and no longer merged cleanly with master, so GitHub could not build the PR
  merge commit.** That is fixed by the merge in this handoff's HEAD — keep the
  branch merged up with master or CI silently stops reporting again. Never
  merge on red, and not at all until the program ends.
- **Note for whoever enables required status checks** (branch protection is
  free now that the repo is public): a workflow skipped by `paths-ignore`
  never reports, so a docs-only PR would hang on "Expected — waiting for
  status". Use the dummy-job pattern.
- `FIREBASE_SERVICE_ACCOUNT` absent from `~/fireplace/.env` on the VM → FCM is
  dead in prod, so 0b's pushes reach PWA endpoints only.
- `.jks` keystore off-PC backup (`docs/runbooks/android-release.md`).
- **Owner decision pending:** a password thief can hold the 24 h post-cancel
  cooldown open by looping start+cancel, keeping a genuine owner out of
  recovery. The cooldown is spec-mandated (§6.2) so nothing was changed; the
  question is whether a password change should clear it.

---

## 5. Known flake, NOT yours

`frontend/test/widgets/input/chat_input_bar_attachment_test.dart` →
"video-then-caption keeps the media-first ordering contract" fails roughly two
runs in three (`Expected: ['VIDEO','TEXT'] Actual: ['VIDEO']`). Proven
independent of this program by stashing every `lib/` change and reproducing it.
It deserves its own session; do not drive-by fix it.
