# 2026-09-08 (part 4) — final pre-ship review of 0.2.25: clause 6's third change over-held the gate

**Commit** `3971db3` on `master` (== `feat/passcode-lock`). **Version 0.2.26, web-only.** Spec:
`docs/design/multi-device.md` §12, amendment **2026-09-08b (D27)**, new item **(lxxx) clause 7**.
Backend `0.2.24 / 89088143` untouched — `git diff --name-only 8908814..HEAD -- backend/` is empty.

## What the owner asked

"Review whole thing final time before shipment", then "test it and proof it works". Everything
before this was already deployed (0.2.23 / 0.2.24 / 0.2.25); the unreviewed delta was the four
commits after the D27 two-axis review — i.e. the clause-6 fix itself (`25fdc25...4fae484`,
12 files, 483 insertions). I read that diff personally instead of spawning reviewers: it was
small enough, and the reviewer model had 429'd earlier in the day.

## What was wrong (found by reading, confirmed by a RED test, then live)

`restoreUnfinished` (`_restoreStage != idle && != done`) was added as the third clause-6 change
to hold the gate through the rebind's reconnect — correct for a restore that has ADOPTED the
backup identity. But **nothing ever returned `_restoreStage` to `idle`**: not `clearAll()`
(logout / account switch — which resets every OTHER per-account flag on the provider), not
`onConnect(false)`, not another door succeeding. Consequences, all reachable on the shipped
0.2.25:

1. A restore that failed BEFORE adopting anything — wrong phrase, `exists:false`, a fetch that
   never answered — set `failed` and held `needsDeviceLink` for the life of the process. A user
   who mistyped the phrase and then linked by QR (or completed a 72 h reset) had
   `identityIncomplete` cleared by the post-rebind init and **stayed on the gate with nothing
   left to retry** — clause 6's stuck state, one door over.
2. It outlived the account: user A's failed attempt gated user B's next login on the same
   install.
3. The kept clause-6 test (`an unfinished restore holds the gate even when init cleared the
   flag`) PINNED the defect: it failed the restore at `fetching` (nothing adopted) and asserted the
   gate held.

## Fix (`encryption_provider.dart`, 32+/6-)

- `_restoreAdopted`: true when `adoptRestoredIdentity` returns, false at `done`.
  `restoreUnfinished => _restoreAdopted`. Before adopt nothing is half-done and the gate is held
  by whatever brought the user to it (the failure is still shown — the section reads
  `restoreStage`, unchanged); after adopt the install holds an identity whose prekeys are
  unpublished and the idempotent retry (clause 6) is the way out.
- `_resetRestoreMachine()` (stage → idle, failure → null, adopted → false) from `clearAll()` and
  the `!isReconnect` branch of `onConnect`. The §6.2 rebind is `connect()` with the SAME user id
  (`connection_provider.dart:203`), so it is a reconnect and never reaches either.

Deliberately NOT done: no reset of the machine when another door's upload lands. After a
post-adopt failure the QR door is refused anyway (`adoptProvisionedIdentity` sees a held
identity with no disposal authorization) and the retry button is on the same gate; a reset
completed in that state is an edge the amendment names rather than adds machinery for.

## Proof

- **RED first:** the two new tests (`a restore that failed BEFORE adopt does not hold the gate`,
  `clearAll returns a failed, adopted restore to idle`) ran `+8 -2` on `4fae484`; the rewritten
  hold test now fails at UPLOAD after adopt and stays green on both sides of the fix.
- **F23** (`_restoreAdopted || stage == failed`) and **F24** (delete the `clearAll` teardown):
  1 substitution each, printed, `+9 -1` each, restored — `git diff --stat` after showed only the
  intended 32+/6-.
- frontend **2058 / 14 skipped**, analyzer clean on `lib test test_e2e`; CI run `34252083326`
  green on all five jobs before the deploy.
- **Live, on a rebuilt bundle against the local stack** (two isolated Chromes on
  `--remote-debugging-port`, driven by pixel coordinates + CDP `Input.insertText` — Flutter's
  semantics placeholder never populated the tree from a synthetic click, so `observe()` was
  useless here): `c7prim#8596` enabled linking with the mandatory phrase; a fresh browser logged
  in as the same account hit the gate; a **valid-checksum WRONG phrase** ("abandon ×11 about")
  drew `Fraza nie pasuje do kopii kluczy tego konta` (a bad-checksum phrase never reaches the
  machine — it stops at the local `_malformed` check); then the primary pasted the new device's
  `fp-link.v2…web.n` code, SAS **467 444** on both sides, approve → **the new device landed in
  the shell** and the primary's roster read `web · #1 · główne` + `web · #2`. Then logout on the
  new device → login as `c7other#6320` → shell, no gate. `identity_change_audit` for 199: 0 rows.

## Also

- `scripts/verify-claude-frontend-test-counts.mjs` refused a with-skips TTY log because that
  shape ends `All other tests passed!`, not `All tests passed!` — accepted now; CLAUDE.md §3
  count 2056 → 2058.
- Noticed, NOT touched: the gate's reset copy still says "(1 godzinie z kluczem odzyskiwania)".
  `_identityResetShortened` and the server-side shortening still exist, so the sentence is not
  false — but for an account WITH a backup the phrase restores instantly and the 1 h clause is
  noise. Owner's call whether that copy should change.

## Lessons

- A term added to a gate predicate needs an OWNER that clears it, and every per-account flag on
  this provider has one in `clearAll()` — the new one did not. Read the teardown when adding
  state to a process singleton.
- The test that pinned the defect was written to a marker of the mechanism ("failed → gated"),
  not to the user's situation ("nothing adopted → the other doors must still work"). Ask what
  the user can DO from the asserted state.
