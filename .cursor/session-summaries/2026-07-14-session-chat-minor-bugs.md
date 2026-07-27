# Chat minor-bugs batch (composer, notifications, messaging)

**Date:** 2026-07-14 (branch `fix/chat-minor-bugs` off current `master` = 0.0.117; bumped to **0.0.118**; UNMERGED)

## What was done
Eight reported chat bugs fixed across composer, notifications, and messaging (frontend Flutter + two NestJS DTOs). Root-caused each with read-only `scout` subagents first.

- **Auto-capitalize sentences** — composer `TextField` had no `textCapitalization`; added `TextCapitalization.sentences` (mobile-IME hint; does not alter pasted/desktop text).
- **Notification blocks back arrow ~2.5s** — `showTopSnackBar` was an opaque `top:0` overlay over the app-bar back circle; wrapped its content in `IgnorePointer` (informational, never needs taps). Universal fix (snackbar is used app-wide).
- **Send button too small / near-miss dismisses keyboard** — replaced the bare 26px send icon with a 42px filled circular button (primary bg, white icon); 48×48 tap target unchanged. Verified visually on web (composer preview harness).
- **Composer doesn't expand for long messages** — `maxLines` 6→12, `maxComposerHeight` `*6`→`*12` (clamp 480).
- **Copy/save image from chat** (paste-into-composer already worked; user retracted the re-tap-paste item) — added Save + Copy actions to the fullscreen image viewer. Save reuses the existing cross-platform `saveBytesAsDownload` (web = real download; native = app storage, same as existing file downloads). Copy is web-only (`image_clipboard_web.dart`, Async Clipboard API, PNG re-encode via canvas), gated by `canCopyImageToClipboard`. MIME/filename sniffed from magic bytes (MessageModel carries no MIME).
- **Notifications shown while viewing that chat** — server push-skip was correct but the web-push SW showed every push. Added a client-focus guard in `web-push-sw.js`: the page posts `active-conversation` (via the existing `PushSwChannel`, from `_emitPushClientState`, keyed by client id), and the push handler suppresses ONLY the banner (badge/sweep still run) when a focused/visible client views that conv. Fails open on error.
- **Unread badges never clear** — `onConversationsList` merged unread as unconditional `max(prev, server)`, so a stale snapshot froze a badge forever after read. Replaced with server-trust (open conv forced to 0). Rejected a `_locallyReadConvIds` guard that would have hidden offline-received unread.
- **Very long messages can't be sent + retry broken** — server `SendMessageDto`/`EditMessageDto` `encryptedContent` cap was 10000/20000; E2E base64 ciphertext blew past it. Raised both to **65536** (matches the secret-notes ciphertext precedent; DB column is `text`, no migration; socket.io default 1 MB). Added a client UTF-8 **envelope-byte** budget (`AppConstants.maxEnvelopeBytes=45000`, checked via `isMessageWithinByteLimit` on `jsonEncode(E2eEnvelope.build())` — correct for JSON escaping + emoji) with a friendly pre-send error, plus an exact post-encryption guard in `_encryptAndSend`/edit path. Fixed the TEXT retry: it removed the bubble and only re-sent when that conv was active (silent data loss + wrong-conversation send); now retries in place to the message's own recipient.

## Key files
- `frontend/lib/widgets/input/chat_input_bar.dart`, `widgets/top_snackbar.dart`, `widgets/message/image_message_content.dart`
- `frontend/lib/providers/conversations_provider.dart`, `providers/messaging/messaging_provider.send.dart` + `.actions.dart`
- `frontend/web/web-push-sw.js`; `frontend/lib/constants/app_constants.dart`
- new: `frontend/lib/utils/{message_length,image_clipboard,image_clipboard_stub,image_clipboard_web}.dart`
- `backend/src/chat/dto/{chat,edit-message}.dto.ts`
- l10n keys (en/pl + regen); new tests: `test/utils/message_length_test.dart`, provider badge/SW tests in `conversations_provider_test.dart`

## Verification
- `flutter analyze --no-fatal-infos`: **No issues found**. `flutter test`: **714 passed**.
- Backend `nest build` clean; `chat.dto.spec` 59 passed (65536 cap).
- Composer send button confirmed visually on web (filled blue circle with draft text).
- **NOTE:** `dart format` (Dart 3 "tall" style) reflowed 141 files on this machine — the repo uses the older style and CI does not enforce format. Do NOT run `dart format` on the tree; hand-format edits to match surroundings. All churn was reverted; diff is scoped to the 16 changed files + 5 new.

## Notes for next session
- Branch `fix/chat-minor-bugs` UNMERGED, based on current master (0.0.117 → bump 0.0.118). PR to master.
- Not visually verified end-to-end (needs a live authed session): image save/copy dialog, in-app notification overlap, badge-in-list, capitalize — all covered by unit/widget tests + code.
- Pre-upload media retry (image/gif/file/voice failed before upload completes) is still a no-op — separate, harder edge (needs retained local source); not reported, left as-is.
- The dev environment was volatile mid-session (branch switched under me to `refactor/glass-dialog-migration`, master advanced 0.0.115→0.0.117); work was re-based cleanly onto current master. Backup patch at `C:/Users/Lentach/Desktop/cmb-tracked.patch` (can delete).
