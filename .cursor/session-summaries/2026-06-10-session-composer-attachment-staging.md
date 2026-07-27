# Composer attachment staging + ordering contract (Clipboard Phase 2)

**Date:** 2026-06-10

## What was done
Implemented Phase 2 of the clipboard spec via plan `docs/superpowers/plans/2026-06-10-composer-attachment-staging.md` (TDD). (1) **Ordering contract:** `_encryptAndSend` → `Future<bool>` (true only after the `sendMessage` socket emit; false on e2e-not-ready / encrypt failure — all internal mark-failed paths preserved); `sendImageMessage` → `Future<bool>` (`return await _encryptAndSend(...)`; false on no-conv/oversize/upload-throw); `AttachmentHandler.sendImage` → `Future<bool>` (also dropped the no-op `kIsWeb ? bytes : bytes` + unused import). (2) **`ComposerAttachmentController`** (`widgets/input/composer_attachment_controller.dart`): max 1 `StagedAttachment` (bytes/mime/filename, RAM-only), `stage()` validates `kStageableImageMimeTypes` (png/jpeg/gif/webp) + `MediaCryptoService.maxBytes`, replace-on-restage, `StageResult` enum. (3) **`ComposerAttachmentBar`** chip (thumbnail `Image.memory` `cacheWidth:120` + `errorBuilder`, filename, size, remove ✕) rendered in `ChatInputBar`'s column directly above the input row (sibling of ReplyPreviewBar — TextField never unmounts). (4) `ChatInputBar._send()` branches to `_sendStaged()`: captures caption, clears chip+field, awaits `AttachmentHandler.sendImage` post-emit completion → on true sends caption (`sendMessage`), on false restores caption to field (prepend-newline if user typed meanwhile); `_isSendingStagedImage` re-entrancy guard; trailing send visible when text non-empty OR staged. ARB `composerAttachmentRemoveTooltip` (en/pl). No paste source yet — Phase 3 (web `paste` event) / Phase 4 (Android `contentInsertionConfiguration`) feed the controller; tests feed it via `attachmentControllerForTest`/`sendForTest` hooks.

## Key files
- `frontend/lib/providers/messaging/messaging_provider.send.dart` (`Future<bool>` contract)
- `frontend/lib/widgets/input/attachment_handler.dart`, `composer_attachment_controller.dart` (new), `composer_attachment_bar.dart` (new), `chat_input_bar.dart`
- Tests: `test/widgets/input/composer_attachment_controller_test.dart` (new, 5), `test/widgets/input/chat_input_bar_attachment_test.dart` (new, 4), ordering-contract group in `test/providers/messaging_provider_media_send_test.dart` (+3)

## Verification
- Ordering contract test proves emit-before-completion: `await sendImageMessage` → emitted == ['IMAGE'] already; caption then ['IMAGE','TEXT'].
- Widget tests: chip show/remove; send affordance with staged-only; success flow emits IMAGE→TEXT + composer cleared; failure flow restores caption, no TEXT emit, guard resets (subsequent text send works).
- `flutter test` full → **347 passed** (was 335; +12 = exactly the new tests). `flutter analyze` → 1 pre-existing info (3 new lints introduced and fixed: wildcard params, unnecessary import).
- Commits on master: `59ab1d5`, `b63593d`, `345adbf` (+docs commit).

## Notes for next session
- **Phase 3 next: web paste source** — `composer_paste_stub/web.dart` pair (capture-phase `window` `paste` listener via `package:web`; `preventDefault` only when an image is consumed; insert clipboard text at cursor — see spec §5 Phase 3). Wire callback → `attachmentControllerForTest`'s production twin (`_attachment.stage`) + snackbars for `StageResult.tooLarge`/`unsupportedType` (ARB keys not yet added — Phase 3).
- Phase 4: Android `contentInsertionConfiguration` with URI-only (`data == null`) guard.
- Deploy still pending (rides with decrypt-cascade fix + Phase 1 Copy); bump version then.
- Flagged extra (not done): routing the existing file-picker image flow through staging for competitor parity — currently still insta-sends.
