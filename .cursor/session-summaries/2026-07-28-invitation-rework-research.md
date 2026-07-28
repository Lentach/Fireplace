# Invitation rework research and UX proposal

**Date:** 2026-07-28

## What was done

- Created isolated worktree `C:/Users/Lentach/Desktop/fireplace-wt-invitation` on `feat/invitation-rework` from clean `master` at `63f4ef2`.
- Audited the existing invitation lifecycle across Flutter and NestJS.
- Confirmed outbound pending invitations already exist in the backend and `FriendsProvider`, but `AddOrInvitationsScreen` renders only inbound requests and pops immediately after send.
- Confirmed acceptance and reciprocal auto-accept both misuse `openConversation` as a navigation trigger for the caller; the accept button also shows success before backend confirmation.
- Researched first-party request/consent flows for Signal, Discord, Session, Matrix/Element, with explicit evidence gaps for Instagram, Messenger, and Snapchat.
- Recommended one `Invitations` relationship inbox with `Waiting for you` and `Sent` sections, authoritative action states, an accepted/chat-ready confirmation, and explicit `Open chat` instead of automatic navigation.
- Defined the visual direction: Fireplace floating glass chrome, opaque compact rows, Contacts hex identity language, primary Accept/quiet Decline, skeleton loading, reduce-motion-aware row transition, and no chat-route animation.

## Key files

- `docs/plans/2026-07-28-invitation-flow-research.md` — cited first-party product evidence.
- `docs/plans/2026-07-28-invitation-flow-rework.md` — recommended flow, alternatives, wire/module seam, visual direction, implementation slices, and acceptance criteria.
- `docs/plans/2026-07-28-invitation-implementation-handoff.md` — copy-paste implementation prompt with exact scope, contracts, non-goals, regressions, visual loop, and required verification.
- `.planning/invitation-rework/` — task plan, findings, and progress.

## Verification

- Read the current backend send/accept/reciprocal/reject flows and frontend provider/screen/navigation paths directly.
- Research artifact was read back after the background agent wrote it; material product claims link to first-party sources and evidence gaps are marked.
- No application source, tests, configuration, migrations, or version changed; app tests/builds were therefore not run.
- Three optional parallel designer agents returned HTTP 429 before output. Their scoped alternatives were synthesized inline from the code audit and source-backed research instead of retrying.
- Proposal artifacts were committed and `feat/invitation-rework` was pushed to `origin`; no merge or deployment was performed.
- Added a fresh-agent implementation handoff for the approved design; it requires work in the isolated branch and forbids merge/deploy without owner approval.

## Notes for next session

- Core decision: acceptance changes relationship and prepares the conversation; it must not navigate. Only explicit `Open chat` may navigate.
- The authoritative accepted outcome, including nullable `conversationId`, must reach both sender and accepter. Remove acceptance-driven `openConversation`; keep it for explicit `startConversation` only.
- Do not show `Chat ready` when friendship succeeded but conversation creation failed. Provide an honest retry state.
- Do not add client refetches inside `onFriendRequestAccepted`; existing docs prohibit the stale-snapshot race.
- Withdrawal is deliberately optional follow-up; no sender-authorized cancel operation exists today.
- This session is design/research only. Implementation and render verification remain pending owner selection.
