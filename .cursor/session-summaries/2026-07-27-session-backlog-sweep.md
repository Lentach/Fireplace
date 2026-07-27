# 2026-07-27 — backlog sweep on `feat/backlog-sweep`

Owner: **"do all Left on the table, deliberately"**. Five queued items, built in
parallel by five subagents on one branch off master `9d1828a` (frontend 0.0.130).
**Four landed; the fifth — the honeycomb `ListView` rewrite — was measured,
shown to the owner, and RE-DEFERRED by him. This is NOT a cleared backlog.**
**UNMERGED.** Live branch deploy **0.0.130 / `d2fd359`**, smoke 5/5.
**Frontend 903 passed / 4 skipped** (was 879). **Backend 538 / 47 suites** (was
536) — root `CLAUDE.md` §3 count updated because CI has a
`Verify CLAUDE.md backend test counts` step that fails the build otherwise.
`flutter analyze --no-fatal-infos lib/ test/` → 0 issues.

## Shipped

1. **Dependabot #95** (`207bc06`, committed separately). `brace-expansion
   5.0.7 → 5.0.8`. Verified surgical: `package.json` untouched, and a key-by-key
   comparison of the lock showed exactly four entries changed, all
   brace-expansion. npm's "removed 2 packages" was `node_modules` dedupe on
   disk, not the lock. Not runtime-reachable in the first place — every copy is
   `dev: true`, reached only via eslint / typescript-eslint / nest-cli's glob.
2. **Ghost invites.** `FriendsService.getSentRequests` (sender-filtered) plus a
   new `sentRequestsList` socket event, emitted wherever a user's inbound list
   refreshes AND after send / accept / reject so a ghost clears the moment the
   invite resolves. The reject path needed `server` + `onlineUsers` threaded
   through `chat.gateway.ts` to reach the original sender.
   **Deliberately ADDITIVE**: `pendingRequestsCount` stays INBOUND-only (it
   drives the Contacts core's `↓ N` port and badges in `conversations_screen`
   and `add_or_invitations_screen`), and `friendRequestsList` keeps its
   inbound-only meaning. Client side: `FriendsProvider.sentRequests` + both
   account-reset paths + the socket registration.
3. **Honeycomb** — see the DEFERRED section; what landed is the constant-factor
   cut plus ghost cells (hollow, long-dashed, send-marked, unwired, not
   focusable, no doubled socket, excluded from real-contact counts).
4. **Chats `+` → honeycomb picker.** Glass sheet of friends built from the
   shared `hex_avatar.dart` primitives, opening chats through the screen's
   EXISTING path. EN/PL localised, reduce-motion honoured.
5. **Glyph data refactor.** The per-glyph optical nudge, active stroke, spin and
   motion now live on `ConsoleGlyphGeometry`; `_motionOffset` switches once on a
   `ConsoleGlyphMotion` kind (none / lift / spread) instead of on the enum.
   Zero visible change. Done in ONE pass — a half refactor leaving two
   conventions in one file would have been worse than leaving it alone.

## DEFERRED AGAIN, by explicit owner decision: the honeycomb `ListView` rewrite

The queue item was *"`ListView` rewrite of the honeycomb for >200 contacts"*.
**That was NOT done and must not be recorded as done.** What landed is
windowing of the expensive VISUAL subtrees (two-row overscan) while a
lightweight focus/semantics control stays resident for every contact.
`contact_network_view.dart` still uses `SingleChildScrollView` + one
full-height `Stack`, so build+layout is still O(N).

A throwaway probe (written, run, **deleted**) measured the current build:

| contacts | 20 | 50 | 100 | 200 | 400 |
|---|---|---|---|---|---|
| median ms | 55.4 | 66.5 | 72.0 | 78.1 | 135.5 |

Marginal cost per contact is ~0.06 ms across 100→200 and ~0.29 ms across
200→400, i.e. **the cliff is still there**.

**Read that as DIRECTIONAL ONLY.** This probe forced a full subtree rebuild via
a changing key and re-pumped the whole host, which the deleted 2026-07-24 probe
did not — its absolute numbers (22.3 / 28.1 / 30.5 / 40.6 / 109.0) are NOT
comparable to these. Only the shape within one table is meaningful. Re-measure
both arms with one methodology before quoting a speedup.

Owner was shown the measurement and the tradeoff and chose to defer:
the cliff only bites above ~200 contacts, which is still not real, while today's
change already cut the constant factor and every contact stays reachable.

**Correction for whoever picks this up:** the older note claimed a ListView
rewrite "breaks focus traversal to unbuilt nodes" and that framing is too
strong. Keyboard traversal can only reach MOUNTED children at any instant —
that is true of every virtualized list — but accessibility does NOT require
keeping O(N) widgets resident. A proper rewrite uses `ListView.builder` over
rows with `semanticChildCount` and indexed row semantics, plus an explicit
programmatic scroll-then-focus for search-to-reveal. Do not treat the resident
control plane as the only way to stay accessible.

## Verification notes

- Each subagent was told to SKIP validation so they would not block each other;
  the lead ran everything once at the end. That caught three things the agents
  could not have seen: two `unnecessary_cast` analyzer warnings in the new
  picker; a `connection_provider.dart` diff of **+61 lines for a 3-line
  change** (`dart format` churning a file written under an older dart style —
  reverted to +3, CI does not enforce format); and the need to update the
  CI-verified backend test count.
- **The rewritten lazy-avatar tests were falsified BY THE LEAD, not trusted.**
  The honeycomb agent rewrote them around virtualization and claimed they still
  hold. Reintroducing the historical high-water-mark bug (never reset the mark
  on a contact-run change) turned the re-arm test red — `armed()` equalled
  `mounted()` at 32 where it demands fewer. The contract genuinely survives the
  rewrite.
- **Ghost invites are NOT visible on the deployed app.** The live backend is
  0.0.127/`3861166` and never emits `sentRequestsList`; the client degrades
  cleanly to an empty list. A backend deploy is required and is gated on the
  owner.

## Next

- Branch is unmerged. Merging needs the usual: version bump as the LAST commit,
  PR, CI, master deploy, smoke — all on his explicit word.
- A backend production deploy is required before ghost invites do anything.

## Release procedure exception (0.0.131)

**The version bump was NOT the last branch commit**, which is the convention
this project's handoffs carry. Actual order:

```
280a802 chore(release): 0.0.131
c0fcae1 test(e2e): prove the ghost-invite lifecycle over a real socket
```

Why: the bump went in when the PR was opened. Only then did it surface that the
cross-tier `sentRequestsList` contract had never been exercised end to end —
the backend emission and the client parsing were each unit-tested against a
mock, and the 5-point smoke cannot see a feature like that. Shipping it
unverified was the worse option, so a test-only commit landed after the bump.

Nothing in production is inconsistent as a result: deploys key off the MERGE
commit, and both surfaces report `0.0.131 / f4d3967`.

**Do not rewrite the merged history to tidy this.** The lesson for next time is
the opposite one: hold the bump until verification is genuinely finished, so
the bump can stay last.
