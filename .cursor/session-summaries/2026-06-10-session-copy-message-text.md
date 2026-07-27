# Copy message text — context-menu Copy action (Clipboard Phase 1)

**Date:** 2026-06-10

## What was done
Implemented Phase 1 of the clipboard spec (`docs/superpowers/specs/2026-06-10-clipboard-copy-paste-design.md`) via plan `docs/superpowers/plans/2026-06-10-copy-message-text.md`, TDD task-by-task. (1) `MessageModel.hasCopyablePlaintext` — TEXT + non-empty + not `[encrypted]`/`[Decryption failed]`/`[Encryption not initialized]`. (2) ARB keys `messageActionCopy` ("Copy"/"Kopiuj") + `snackbarMessageCopied` ("Message copied"/"Skopiowano wiadomość"), `flutter gen-l10n`. (3) Nullable `onCopy` through `openMessageContextMenu` → `MessageActionPanel` (row below Reply, hidden when null — voice/media unaffected; existing call sites compile unchanged); `computeMessageContextMenuLayout` gained `panelHeight` param (default 184) + new const `kMessageActionPanelRowHeightEstimate = 46.0` so the 5-row panel still clears the composer. (4) `ChatMessageBubble._openContextMenu` passes `onCopy` gated on `hasCopyablePlaintext` → `Clipboard.setData` + `showTopSnackBar(snackbarMessageCopied)`. Copy IS allowed on disappearing messages (explicit product decision in spec — timed-disappearing, not view-once). Spec review items resolved earlier this session: Phase-2 image-then-caption ordering contract (verified `sendImageMessage` fire-and-forgets `_encryptAndSend` at `messaging_provider.send.dart:162` — must await before caption emit), Android URI-only `commitContent` guard, cursor-aware mixed-paste insertion.

## Key files
- `frontend/lib/models/message_model.dart` (+`hasCopyablePlaintext`)
- `frontend/lib/widgets/message/message_action_panel.dart` (+nullable `onCopy` row)
- `frontend/lib/widgets/message/message_context_menu_overlay.dart` (+`kMessageActionPanelRowHeightEstimate`, `panelHeight` param, callback threading)
- `frontend/lib/widgets/message/chat_message_bubble.dart` (Clipboard + snackbar wiring)
- `frontend/lib/l10n/app_en.arb`, `app_pl.arb` (+2 keys each)
- Tests: `frontend/test/models/message_model_copyable_test.dart` (new, 4), `frontend/test/widgets/message/message_context_menu_overlay_test.dart` (+6)

## Verification
- `flutter test test/models/message_model_copyable_test.dart` → 4/4 pass (failed pre-impl with getter-undefined, TDD verified)
- `flutter test test/widgets/message/message_context_menu_overlay_test.dart` → 26/26 (driver test red pre-wiring, green post)
- `flutter test` (full) → **335 passed** (was 325; +10 = exactly the new tests)
- `flutter analyze` → 1 pre-existing info only (`_buildApp` underscore in main_shell_notification_nav_test.dart)
- Commits on master: `fdd3aa2`, `ec91d23`, `476b03d`, `8bfa66a` (+docs commit)

## Notes for next session
- **Not yet deployed** — decrypt-cascade fix deploy is also pending; both ride the next `./deploy.sh` (version bump per `.cursor/rules/version-bump.mdc` at that point).
- Phase 2 (paste: staged composer chip) is next — plan not yet written; spec §3 ordering contract + §5 Phase-2 table are the inputs. Remember: `sendImageMessage` must await `_encryptAndSend` before the composer emits the caption text.
- Manual QA still worthwhile on device: long-press copy on iOS PWA (callout vs custom menu interplay) — unit/widget tests can't cover Safari.
