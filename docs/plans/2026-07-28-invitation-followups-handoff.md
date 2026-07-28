# Invitation follow-ups — fresh agent handoff

**Written:** 2026-07-28, at the end of the session that implemented the invitation rework.
**Branch:** `feat/invitation-rework` · **Worktree:** `C:/Users/Lentach/Desktop/fireplace-wt-invitation` · **Head at handoff:** `6b8061a`
**Open PR:** [#106](https://github.com/Lentach/Fireplace/pull/106) — green on all three CI jobs, `MERGEABLE`/`CLEAN`, **not merged, not deployed**.

Copy the block at the bottom into a fresh session.

---

## Where things stand

The invitation rework is **finished and shipped to a PR**. Nothing about it is outstanding. Full detail: `.cursor/session-summaries/2026-07-28-invitation-implementation.md`; the executed spec is `docs/plans/2026-07-28-invitation-implementation-plan.md`.

Verified on the merged tree, exit codes captured without pipes: backend **564/47** + build, Flutter analyze clean + **960 passed / 4 skipped**, live `test_e2e` **11 passed**, backend lint ratchet **821 real / 429 formatting** (floor lowered from 839/481). Four independent reviews — two on the implementation, two on the fix delta — left no BLOCKER or MAJOR.

Three follow-ups were agreed with the owner **after** that work was done. All three are gated on #106 merging first.

## Task 1 — Wait for the owner to merge #106

Owner-only. Do not merge it yourself; root `CLAUDE.md` §1 forbids merging to `master` without explicit OK, and §4 governs deploy separately. Branch the follow-ups off fresh `master` once it lands.

If it has already merged when you start, confirm with `gh pr view 106 --json state,mergedAt` and move on.

## Task 2 — Offline accepted feedback (RESEARCH FIRST, then brainstorm, then build)

### The gap

`friendRequestAccepted` is emitted only to `onlineUsers.get(senderId)`, on both the normal accept path and `emitAutoAcceptFlow`. A sender who was offline when the recipient accepted is never told. They reconnect into `friendsList` / `conversationsList` / `friendRequestsList` / `sentRequestsList` — all pending-only — so the state is silently correct and the event is simply lost. Pre-existing behaviour; the rework did not change it.

### What the owner ruled

> "i dont wont cheap solutions implement it well it must work on mobile too research how similar apps solve that problem and get back to me we will brainstorm the idea"

So:

- **The client-side local-diff shortcut is REJECTED.** (The idea was: persist sent-peer ids, and on reconnect treat "peer now in `friendsList` + sent row gone" as accepted. Cheap, no migration, but single-device inference rather than server truth. The owner does not want it. Do not quietly resurrect it as "pragmatic".)
- **It must work on mobile**, which means the app being backgrounded or killed is in scope, not just a socket reconnect.
- **Research before designing.** Bring findings back and brainstorm with the owner before writing code.

### Research brief

Use the `research` skill. Same evidence discipline as `docs/plans/2026-07-28-invitation-flow-research.md`: first-party sources only, mark **Observed** vs **Not established**, never fill gaps from memory or third-party tutorials. That earlier doc already found that *sender-facing status is largely undocumented* across Signal/Discord/Session/Matrix — so expect to pivot from "how do they notify the sender" to the better-documented question below.

**Reframe the question, because it is really two:**

1. **State catch-up on reconnect** — how does a client learn about relationship-state changes that happened while it was away?
2. **Wake-up while killed** — how does a mobile client get told at all when it is not running?

Targets worth reading, with what each is likely to establish:

| Source | Likely to establish |
|---|---|
| Matrix Client-Server API `/sync` | The canonical state-delta model: membership changes returned as deltas since a `since` token. Directly analogous to "what changed while I was gone." Also `m.room.member` invite/join transitions. |
| Matrix Push Gateway / Push Rules spec | How a spec'd system separates *event delivery* from *push notification*, and what it puts in a push payload. |
| Discord Gateway docs | `READY` payload carrying relationships, and the `RELATIONSHIP_ADD` event — the "full state on connect + deltas after" pattern. |
| Signal | Server-side message queue semantics and sealed sender; what the server is allowed to know about who is talking to whom. |
| Web Push (RFC 8030) + FCM docs | Delivery guarantees, payload limits, and what the relay/transport can read. |

**Then answer, for Fireplace specifically:**

- Is this a push problem, a sync-on-connect problem, or both? (Almost certainly both: sync-on-connect for the in-app row, push for the killed-app case.)
- **The hard constraint is `backend/CLAUDE.md` §9.** FCM `data` transits Google **readable**, so Fireplace deliberately sends a content-free wake-up only — `type` + `conversationId`, never `senderName`. An "Alex accepted your invitation" FCM would leak the social graph to Google and violate that contract outright. Web Push bodies are E2E-encrypted to the browser and may carry richer metadata, but send **no `topic` header** because that is cleartext to the relay. Any design has to respect this asymmetry, and it is the most interesting part of the problem.
- Exactly-once matters. Whatever the mechanism, the sender must be told once, not on every reconnect forever. That is what pushed the original estimate toward a `senderNotifiedAt`-style column plus an ack — but do not assume that is the answer; let the research shape it.
- **UX ruling already made:** do **not** deliver this as a toast. A toast is for "just now"; firing one for something four days old reads as broken, and without an ack it repeats. It should be an accepted row in the Invitations screen that the user dismisses with `Done` — the `InvitationOutcome` machinery, the accepted-row rendering, `Open chat` and `Done` **already exist and are tested**, so the client-side cost of the right design is small. Whatever you build should feed that existing map.

Deliverable: a research doc under `docs/plans/`, then **stop and brainstorm with the owner**. Do not go straight to implementation.

## Task 3 — Two theme/spec fixes, teal rendered for the owner's judgment

The owner chose "both, teal rendered for your judgment first." Both were reported as NITs by the design reviews and deliberately left out of #106.

### 3a. Teal `buttonBg` disagrees with `colorScheme.primary`

`rpg_theme.dart` sets teal `buttonBg: secondaryTealStone` (`#0D9488`, teal-600) while `primary` is `primaryTealStone` (`#0F766E`, teal-700). `ElevatedButton` foreground comes from `readableOn(buttonBg)`, which returns **dark** for teal-600 (white on it is only 3.75:1), whereas the `Chat ready` pill uses `primary` with white. Result: in one invitation row, two different teals with opposite label polarity.

Fix is one token — teal `buttonBg` → `primaryTealStone` — which flips `readableOn` to white and matches the light theme's white-on-accent convention. Both variants already pass contrast (button 5.6:1, pill 5.53:1), so **this is a cohesion and taste change, not a correctness fix**.

It repaints **every `ElevatedButton` in the teal theme app-wide** and makes them darker. Render teal before/after across chat, contacts, settings and auth, and let the owner rule before it lands.

### 3b. `GlassSurface` opaque branch keeps the translucent border

`glass_surface.dart:90` swaps the fill to `opaqueFill` when opaque but line 92 still uses `border: glass.border` — a translucent token. SPEC §7 says the opaque fallback should use the solid content border (`convItemBorder`/`tabBorder`) at alpha 1.0. In light/teal the white-on-white border effectively vanishes.

**Treat this as bigger than its NIT label.** It fires for every `forceOpaque` surface *and* the whole accessibility fallback path — `MediaQuery.highContrast` and the `REDUCE_TRANSPARENCY` build flag — which covers the chat top bar, bottom nav, composer, sheets, dialogs and menus. Small diff, wide blast radius, on surfaces least likely to have ever been looked at in that mode. Do it with high contrast actually turned on and render the affected surfaces.

Sequence 3a and 3b as one PR (both are theme/spec), separate from Task 2.

---

## Critical context — traps this session paid for

- **`| tail` hides exit codes.** `cmd | tail` exits with `tail`'s status, so a failing suite reports `ok`. Redirect to a file and echo `$?`, or `set -o pipefail`.
- **`node scripts/lint-ratchet.mjs` runs ONLY in CI.** It failed the first PR run on +13 real type-safety and +24 formatting errors that four reviewers and every local gate missed. Run it locally before pushing backend changes. Fix the code; use `--update` only when the floor goes *down*.
- **The `data: any` + `data = dto` idiom is the ratchet's main source** in the chat services. The typed shape is `data: unknown` + `let dto: SomeDto` + narrowed extraction — see `handleSendFriendRequest` / `handleAcceptFriendRequest` / `handleEnsureInvitationChat` for the pattern.
- **Never re-derive test counts by arithmetic across a merge.** Master's 933 and the branch's 930 both grew from a 903 base; adding the deltas double-counts. Run the merged suite. It said **960**.
- **E2E register throttle is 10/hr/IP, in memory.** Between full `test_e2e` runs: `docker compose restart backend`, then poll `/health` — the container reinstalls and can take 2–5 minutes.
- **`docker compose up` (attached) swallows logs behind a TUI** and its readiness log never matches. Use `-d` and poll `curl -s http://localhost:3000/health` for `{"status":"ok","db":"ok"}`.
- **`flutter run -d web-server` goes stale across restarts** — once its hot-restart client is lost it serves a blank scaffold forever. Restart the process, open a fresh tab, and poll for a non-blank screenshot rather than trusting a `canvas` probe.
- **Ask the owner before opening the browser tool** — it is not headless and pops a window in front of them.
- **Never run `dart format lib/`** — it reformats ~70 untouched files. Format only what you edited.
- `GlassSurface(blur: false)` is **not** opaque; it still paints the translucent `glass.fill` and only skips the `BackdropFilter`. Only `forceOpaque: true` gives a solid surface.

## Verification commands

```bash
cd backend && npm test && npm run build
node scripts/lint-ratchet.mjs
cd frontend && flutter analyze --no-fatal-infos && flutter test
docker compose up -d                     # repo root; poll /health before E2E
cd frontend && flutter test test_e2e
node scripts/verify-claude-backend-test-counts.mjs --log <jest output>
node scripts/verify-claude-frontend-test-counts.mjs
```

Counts are volatile — take them from a run you did this session, then update root `CLAUDE.md` §3 and the cost-curve table in `frontend/CLAUDE.md` §1.

---

## Copy-paste prompt

```text
Role: You are picking up the Fireplace invitation follow-ups. The invitation rework itself is DONE and sitting in PR #106 (green, CLEAN, not merged). Your work is the three follow-ups agreed after it.

WORKTREE
- Work in: C:/Users/Lentach/Desktop/fireplace-wt-invitation (branch feat/invitation-rework, head 6b8061a).
- Never work in C:/Users/Lentach/Desktop/fireplace.
- Do not merge to master and do not deploy. Both need explicit owner approval.

READ FIRST, IN ORDER
1. CLAUDE.md (root)
2. backend/CLAUDE.md and frontend/CLAUDE.md
3. .cursor/session-summaries/LATEST.md
4. docs/plans/2026-07-28-invitation-followups-handoff.md  <- this file, the full brief
5. .cursor/session-summaries/2026-07-28-invitation-implementation.md  <- what already shipped

TASK 1 — BLOCKED ON OWNER
PR #106 must merge before any follow-up work lands. Check `gh pr view 106 --json state,mergedAt`. Do not merge it yourself. Branch follow-ups off fresh master once it lands.

TASK 2 — OFFLINE ACCEPTED FEEDBACK: RESEARCH, THEN BRAINSTORM, THEN BUILD
An offline sender is never told their invitation was accepted; acceptance only reaches a socket that is online at that moment. The owner explicitly REJECTED the cheap client-side local-diff fix and requires this to work on mobile, including a killed app.

Do NOT write implementation code yet. First use the research skill to study how comparable systems deliver relationship-state changes to an absent client — Matrix /sync state deltas and its push gateway, Discord READY + RELATIONSHIP_ADD, Signal's queue and sealed sender, Web Push RFC 8030 and FCM. First-party sources only; mark Observed vs Not established; do not pad gaps from memory.

The binding constraint is backend/CLAUDE.md section 9: FCM data transits Google READABLE, so Fireplace sends a content-free wake-up only. "X accepted your invitation" over FCM would leak the social graph and is not acceptable. Web Push bodies are E2E-encrypted and may carry more, but send no topic header. Design around that asymmetry.

Also settled already: delivery must be exactly-once (not a toast repeating every reconnect), and the UI must reuse the existing InvitationOutcome accepted-row machinery with Open chat and Done — that is already built and tested.

Deliver a research doc under docs/plans/, then STOP and brainstorm with the owner before implementing.

TASK 3 — TWO THEME/SPEC FIXES, ONE PR
3a. Teal buttonBg (#0D9488) disagrees with colorScheme.primary (#0F766E), so a button label and a pill label in the same row have opposite polarity. One-token fix, but it repaints every teal ElevatedButton app-wide and darkens them. Render teal before/after across chat, contacts, settings and auth and let the owner rule before landing.
3b. glass_surface.dart keeps the translucent glass.border in its opaque branch; SPEC section 7 wants the solid content border. This is the accessibility fallback path (MediaQuery.highContrast and REDUCE_TRANSPARENCY) plus every forceOpaque surface — wide blast radius, so verify with high contrast actually enabled.

TRAPS (all paid for in the last session, details in the handoff file)
- `cmd | tail` hides exit codes; redirect and echo $?.
- node scripts/lint-ratchet.mjs runs ONLY in CI — run it before pushing backend changes.
- Never re-derive test counts by arithmetic across a merge; run the suite.
- E2E register throttle is 10/hr/IP in memory: docker compose restart backend between full runs, then poll /health.
- Use docker compose up -d; attached mode hides logs behind a TUI.
- flutter run -d web-server goes stale across restarts and serves a blank scaffold; restart the process and open a fresh tab.
- Ask before opening the browser tool; it pops a visible window.
- Never run dart format lib/.
- GlassSurface(blur:false) is NOT opaque; only forceOpaque:true is.

Follow the repo's session-summary, test-count, branch, commit and push rules. Report what you changed, the exact commands you ran with their real exit codes, and anything you could not finish.
```
