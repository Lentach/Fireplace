# Web paste source (Clipboard Phase 3)

**Date:** 2026-06-10

## What was done
Implemented Phase 3 of the clipboard spec via plan `docs/superpowers/plans/2026-06-10-web-paste-source.md`. New conditional-import triple `utils/composer_paste.dart` (facade) + `composer_paste_stub.dart` + `composer_paste_web.dart` (pattern: `web_focus_guard`): ONE capture-phase `window` `paste` listener (`package:web`, `AddEventListenerOptions(capture: true, passive: false)`), installed/uninstalled with `ChatInputBar` lifecycle inside the existing `kIsWeb` blocks. Behavior: scans `clipboardData.files` for the first `image/*`; **no image → returns without `preventDefault`** (text-only paste flows into Flutter's hidden textarea natively); image found → `preventDefault()`, forwards `text/plain` (if any) to `_insertPastedText` (selection-replacing insertion at the cursor, collapses caret after) and reads the file via `arrayBuffer()` → `_onPastedImage` → `ComposerAttachmentController.stage()`; `StageResult.tooLarge`/`unsupportedType` → new snackbars `snackbarPastedImageTooLarge`/`snackbarPastedImageUnsupported` (en/pl). `_canAcceptPaste` gates on mounted + not recording + not mid-staged-send. Filename falls back to `pasted.<ext>` when the clipboard File has no name. `navigator.clipboard.read()` deliberately NOT used (permission-gated; unsupported as permission in Safari/Firefox).

## Key files
- `frontend/lib/utils/composer_paste.dart`, `composer_paste_stub.dart`, `composer_paste_web.dart` (new)
- `frontend/lib/widgets/input/chat_input_bar.dart` (install/uninstall, `_canAcceptPaste`, `_onPastedImage`, `_insertPastedText`, test hooks `handlePastedImageForTest`/`insertPastedTextForTest`)
- `frontend/lib/l10n/app_en.arb`, `app_pl.arb` (+2 keys)
- Tests: `test/widgets/input/chat_input_bar_attachment_test.dart` (+4: cursor insertion, oversize snackbar, unsupported-type snackbar, valid-paste chip)

## Verification
- `flutter test` full → **351 passed** (was 347; +4). `flutter analyze` → 1 pre-existing info only.
- Commits on master: `19ef19e`, `0272672` (+docs commit).
- **Manual web QA still REQUIRED** (DOM listener invisible to `flutter test`, kIsWeb=false):
  - Desktop Chrome/Firefox: copy screenshot → Ctrl+V → chip + caption send; text-only Ctrl+V → text in field natively, no chip
  - Copy image+text together (web page / Word) → both staged + inserted at cursor
  - macOS Safari: Cmd+V image
  - iPhone Safari + PWA: long-press field → Paste with copied photo; paste during voice recording → ignored

## Notes for next session
- **Phase 4 next (last): Android `contentInsertionConfiguration`** on the composer TextField — `allowedMimeTypes: kStageableImageMimeTypes`, `onContentInserted` → guard `data == null` (URI-only keyboards → snackbar fallback per spec), else `_onPastedImage(bytes, mimeType, filename)`. Manual QA: Gboard clipboard chip with a screenshot.
- Deploy pending: decrypt-cascade fix + Phases 1–3 ride the next `./deploy.sh` (+ version bump). Run the manual web QA list above on production after deploy.
- Flagged extra (undone): route the existing file-picker image flow through staging for competitor parity.
