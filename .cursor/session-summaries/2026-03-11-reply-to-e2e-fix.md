# Session Summary — 2026-03-11 (Reply-to E2E fix)

## Accomplished

- **Fixed reply-to preview E2E leak**: Backend MessageMapper now uses "Encrypted message" when `replyTo.encryptedContent` is present (never exposes plaintext in reply preview).
- **Frontend fallback**: `chat_message_bubble.dart` and `voice_message_bubble.dart` display "Encrypted message" when `replyTo.content == '[encrypted]'` (backwards compat).
- **Test**: Added `message.mapper.spec.ts` test for encrypted replyTo case.
- **Docs**: Updated CLAUDE.md, design doc; removed from known limitations.

## Key Files Modified

- `backend/src/messages/message.mapper.ts` — contentPreview for encrypted replyTo
- `backend/src/messages/message.mapper.spec.ts` — new test
- `frontend/lib/widgets/chat_message_bubble.dart` — `_replyDisplayContent()` helper
- `frontend/lib/widgets/voice_message_bubble.dart` — encrypted content check
- `CLAUDE.md` — E2E rule, removed limitation
- `docs/plans/2026-02-21-e2e-encryption-design.md` — marked fix

## Project Status

Reply-to preview no longer leaks content to server. All E2E text message flows now properly hide plaintext from server.
