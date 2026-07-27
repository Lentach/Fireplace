# Message editing — design → plan → implementation → review (0.0.62)

**Date:** 2026-06-22

## What was done
End-to-end delivery of **message editing** (text-only) for the E2E messenger, in four gated phases:

1. **Design spec** (`docs/plans/2026-06-22-message-editing-design.md`) — research (WhatsApp/Telegram/Signal/iMessage, cited), current-state map of the delete-for-everyone flow, options + recommendation, edge-case decisions. Approved decisions: **text-only**, **15-min window**, **replace-in-place + `editedAt`** (no history), **web+mobile parity**, **no disappearing-timer reset**. Reviewer corrections folded in (reply-quote re-enrich, unsent-row gate, offline interleave test).
2. **Implementation plan** (`docs/plans/2026-06-22-message-editing-plan.md`).
3. **Implementation** — backend (delegated to a subagent) + frontend (main), TDD.
4. **Code review** (subagent) → fixed every actionable finding (H1, M1, L1, L2; L4 already covered).

**Wire contract:** `editMessage {messageId, content:'[encrypted]', encryptedContent}` → server (sender-only, 15-min, **text-only**, blind) swaps `encryptedContent` + stamps `editedAt`, leaves `expiresAt`/`disappearAfterSeconds`/`deliveryStatus` untouched → broadcasts `messageEdited {…, editedAt}`; rejects via `editMessageFailed {messageId, reason}` (`not_sender`/`window_expired`/`not_found`/`not_text`). Edit = a NEW ciphertext over the existing Signal session.

**Recipient correctness:** peer edit re-decrypts — live in the active conversation, deferred otherwise; offline/reconnect re-decrypts via an **`editedAt`-stamped plaintext cache** (`_isEditStale` in decrypt cache-restore + `_mergeMessagePreferNewer` + `invalidateDecryptionCache`). Ratchet ordering relies on libsignal skipped-key storage; no path calls `deleteSessionWithPeer`. Sender is optimistic + reverts fully on reject (in-memory row **+ persisted cache + last-message preview**).

## Key files
- Backend: `backend/src/messages/message.entity.ts` (`editedAt`), `message.mapper.ts`, `messages.service.ts` (`editMessage`), `backend/src/chat/dto/edit-message.dto.ts` (new; `encryptedContent` required+non-empty), `backend/src/chat/services/chat-message.service.ts` (`handleEditMessage` + text-only guard), `backend/src/chat/chat.gateway.ts`.
- Frontend model/wiring: `lib/models/message_model.dart` (`editedAt`), `lib/providers/messaging_provider.dart` (`_editingMessage`/`_pendingEdits` + begin/cancel), `lib/providers/messaging/messaging_provider.{actions,events,decrypt,history}.dart`, `lib/providers/connection_provider.dart`, `lib/providers/encryption_provider.dart` (`invalidateDecryptionCache`).
- Frontend UI: `lib/utils/message_edit_eligibility.dart` (new), `lib/widgets/message/{message_action_panel,message_context_menu_overlay,chat_message_bubble,message_metadata_row}.dart`, `lib/widgets/input/{chat_input_bar,edit_preview_bar(new)}.dart`, `lib/l10n/app_{en,pl}.arb` (`messageEditedLabel`/`messageEditingTitle`, dropped `messageEditComingSoon`).
- Tests: `backend/src/chat/services/chat-message.service.spec.ts`, `messages.service.spec.ts`, `message.mapper.spec.ts`; `frontend/test/providers/message_editing_test.dart`, `test/utils/message_edit_eligibility_test.dart`, `test/widgets/message_edited_label_test.dart`, updated `message_context_menu_overlay_test.dart`.
- Docs: root/back/front `CLAUDE.md` (wire contract, gotchas, schema, limitation removed), `frontend/pubspec.yaml` 0.0.60→**0.0.62** (0.0.61 was already claimed by the concurrent prod-readiness work — avoided the collision).

## Verification
- Backend: `npx jest --config jest.config.json` → **326 passed / 41 suites**; `node scripts/verify-claude-backend-test-counts.mjs` → OK (326/41).
- Frontend: `flutter test` → **407 passed**; `flutter analyze lib` → clean.
- Review: 7/8 invariants confirmed first pass; the one refuted (incomplete revert, H1) fixed + regression test added (`message_editing_test.dart` "rolls back the persisted plaintext cache").
- **NOT yet done (device/prod):** manual on-device QA (edit shows on peer, "edited" label, offline reconnect, expiry untouched); **prod deploy owed** — run manual SQL `ALTER TABLE messages ADD COLUMN "editedAt" timestamp NULL;` on the VM **before** `./deploy-backend.sh`, then frontend `.\deploy-web.ps1`.

## Notes for next session
- Branch **`feat/message-editing`** (off `docs/message-editing-design`); pushed, **PR open, NOT merged to master** — needs the user's explicit OK + device QA before merge (CLAUDE branch+PR norm).
- **Deploy order matters:** manual SQL first (prod `synchronize:OFF`), then backend, then frontend. Backend column-only change → after merge: `git pull && docker compose restart backend` won't apply schema — the SQL is manual.
- Known v1 limitations (intentional, documented): text-only; replace-in-place (no history); link preview kept-as-is on edit (not regenerated). Deferred-edit conv-list preview keeps pre-edit text until the row re-decrypts on open (M1 fix avoids the `[encrypted]` regression but does not actively refresh the preview post-open).
- Untouched review nits: N1 (composer draft discarded on enter-edit). Optional follow-ups.
