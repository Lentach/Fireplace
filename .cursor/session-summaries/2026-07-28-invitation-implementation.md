# Invitation rework — implemented end to end

**Date:** 2026-07-28 — worktree `fireplace-wt-invitation`, branch `feat/invitation-rework`. Executes `docs/plans/2026-07-28-invitation-implementation-plan.md` in full. Not merged, not deployed. No migration, no new dependency, no `pubspec.yaml` bump.

## What was done

**Backend wire contract.** `friendRequestAccepted` is now the authoritative accepted result: the request payload plus `conversationId: number|null` and `chatReady: boolean`, composed at the emit site so `FriendRequestMapper` (shared by five other events) stays pure. It is emitted **after `conversationsList` and before `friendRequestsList`/`sentRequestsList`** — after the conversation list so `Open chat` resolves locally without the banned refetch, before the request lists so the acting row transforms instead of unmounting. `emitAutoAcceptFlow` mirrors it. Both `openConversation` emitters are gone; `handleStartConversation` is now its only producer.

Failures became scoped: `friendRequestFailed {action, requestId, recipientId, reason}` replaces the generic `error` in send/accept/reject, following the documented `editMessageFailed` precedent (the gateway has no ack path and the backend has no exception filter — verified, not assumed).

Partial-success retry is a new correlated pair, `ensureInvitationChat {peerUserId, correlationId}` → `invitationChatReady {peerUserId, correlationId, conversationId, chatReady, reason?}`, authorized by the shared `ChatValidationService.validateCanMessage` gate and idempotent through `findOrCreate`. Peer addresses the row; the client-minted token addresses the attempt, so a slow first failure cannot overwrite a fast second success. The token is DTO-bounded (`/^[A-Za-z0-9_-]{1,64}$/`) because the server echoes it verbatim.

**Invitation identity is the peer user id, never the request id.** `friends.service.ts:91-119` creates a *new* row on reciprocal auto-accept and returns it, so the accepted payload carries an id neither client holds. Outcome map, both pending-list removals, row keys, `_requestActions` cleanup and retry addressing are all peer-keyed. Direction resolves from local state with a load-bearing precedence — `_sendActions` → `_friendRequests` → `_sentRequests` → payload role — because the reciprocal second sender matches the first two at once and their row belongs under `Sent`.

**Every server confirmation is one atomic swap** with a single notification: `onFriendRequestSent` clears the send flag *and* inserts the sent row; `onFriendRequestAccepted` clears both action maps by peer, drops both pending rows, inserts the outcome; `onFriendRequestRejected` is the only path that retires a declined row. Nothing is optimistic. Reconnect preserves `_acceptedOutcomes` (the server never replays acceptance) while clearing action maps and retry tokens.

**UI.** `AddOrInvitationsScreen` became `InvitationsScreen`: one scroll view with `Waiting for you` + `Sent`, no tabs. Auto-send, pop-after-send, the optimistic `friendAdded` snackbar and both `consumePendingOpen` consumers are deleted. `Open chat` pops the peer id and is the only thing that navigates; `Done` clears the outcome; `Create chat` retries in place. Rows are opaque `GlassSurface(forceOpaque: true)`, glass stays on the floating header, status pills are solid, `Accept` is the only accent action. Desktop is the same module in a centered 560 px column with the chrome aligned to it.

## Key files

- `backend/src/chat/services/chat-friend-request.service.ts` + spec, `chat.gateway.ts`, `chat/dto/chat.dto.ts`
- `frontend/lib/models/invitation_state.dart` (new), `providers/friends_provider.dart`, `providers/connection_provider.dart`
- `frontend/lib/screens/invitations_screen.dart` (renamed + rewritten), `widgets/invitations/{invitation_row,invitation_status_pill}.dart` (new)
- `frontend/lib/screens/{contacts_screen,main_shell}.dart`, `widgets/top_snackbar.dart` (optional tappable action; default path byte-identical)
- `frontend/lib/theme/rpg_theme.dart` — `mutedTextBlue` `0xFF8A8A8A` → `0xFF8A9BA8`, the SPEC §4 value
- `frontend/lib/l10n/app_{en,pl}.arb` + regenerated output; `test_e2e/{full_stack_e2e_test,stale_otp_epoch_test,support/e2e_test_client}.dart`

## Verification

Exit codes captured without pipes (a `| tail` hides them):

- `cd backend && npm test` → exit 0, **564 tests / 47 suites**; `npm run build` → exit 0
- `cd frontend && flutter analyze --no-fatal-infos` → exit 0, **No issues found**
- `cd frontend && flutter test` → exit 0, **930 passed / 4 skipped**
- `cd frontend && flutter test test_e2e` vs live backend + Postgres → exit 0, **11 passed**
- Both count verifiers green; root `CLAUDE.md` §3 and `frontend/CLAUDE.md` §1 updated to 564 / 930
- Rendered blue/dark/light/teal at 390×844 and 1440×900 and inspected them

Four independent reviews (two pre-fix, two on the fix delta) — **no BLOCKER, no MAJOR outstanding**. Acted on: blue muted text measured 4.08:1 on the new opaque row fill (now 4.92:1 via the SPEC token), a dead `SocketService.ensureInvitationChat`, an unreachable `ensure_chat` failure branch (backend now echoes the peer id when the raw payload carries a usable one), an unguarded `findOrCreate` in the retry handler that could hang the row forever, a `Pending` pill outline at 1.92:1 in blue, an invisible count chip in light/teal, over-tall rows, and a search button mislabelled `Send invitation`.

## Notes for next session

- **PR #106 open, NOT merged, NOT deployed.** Needs owner approval; the VM pulls `master`, so nothing is live.
- **`origin/master` was 17 commits ahead** when the PR opened (0.0.133 five-bug batch). Merged it into the branch: **only two doc conflicts**, `CLAUDE.md` (test counts) and `LATEST.md` (entry rotation) — zero source conflicts. Master had already reconciled the frontend count to 933; the post-merge suite **measured 960** (933 + this branch's 27), and backend stays **564**. Both verifiers green on the merged tree, and all gates were re-run after the merge, not inherited.
- **CI caught what four reviewers and every local gate missed: the backend lint ratchet.** `scripts/lint-ratchet.mjs` runs only in CI, and the first PR run failed it — my new code added **+13 real type-safety errors and +24 formatting**. Root cause was structural, not cosmetic: the pre-existing `data: any` handler signature plus the `data = dto` reassignment idiom meant every new `friendRequestFailed` emit read `recipientId`/`requestId` off an `any`. Fixed properly by giving `handleSendFriendRequest` and `handleAcceptFriendRequest` the same typed-local shape `handleEnsureInvitationChat` already used (`data: unknown` + `let dto: Dto` + narrowed extraction), and by typing the `@Transform` callback through `TransformFnParams` + `unknown` locals. Net effect: real errors **839 → 821 (−18)** and formatting **481 → 429**, so the floor was lowered with `--update` rather than raised. **Run `node scripts/lint-ratchet.mjs` locally before pushing backend changes** — nothing else surfaces it.
- **Three follow-ups agreed with the owner AFTER this work, all gated on #106 merging. Full brief: `docs/plans/2026-07-28-invitation-followups-handoff.md`.**
  - **Offline accepted feedback** — the owner rejected a cheap client-side local-diff and requires it to work on mobile including a killed app. **Research first, then brainstorm, then build.** The binding constraint is `backend/CLAUDE.md` §9: FCM `data` is Google-readable so it must stay a content-free wake-up, while Web Push bodies are E2E-encrypted; an "X accepted your invitation" FCM would leak the social graph. Delivery must be exactly-once and must reuse the existing `InvitationOutcome` accepted-row UI, not a toast.
  - **Teal `buttonBg`** (`#0D9488`) vs `colorScheme.primary` (`#0F766E`) — one token, but it darkens every teal `ElevatedButton` app-wide, so render teal before/after for the owner to rule on.
  - **`GlassSurface` opaque border** — `glass_surface.dart:92` keeps the translucent `glass.border` when opaque; SPEC §7 wants the solid content border. Bigger than its NIT label: it is the `MediaQuery.highContrast` / `REDUCE_TRANSPARENCY` accessibility fallback for the whole app.
  - Still out of scope entirely: `Withdraw invitation` and `Block` on the invitation row.
- `flutter run -d web-server` for the preview is flaky across restarts — it serves a blank scaffold once its hot-restart client is lost. Restart the process, do not reuse the tab.
- The E2E register throttle is 10/hr/IP in memory: `docker compose restart backend` between full `test_e2e` runs, and give it ~2 min to reinstall and boot.
- Do not re-derive counts by arithmetic across a merge. Master's 933 and this branch's 930 both came from a 903 base, so adding them double-counts. The merged suite was run and it said 960.
