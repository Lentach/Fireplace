# Clipboard copy/paste design (research + spec, no code)

**Date:** 2026-06-10

## What was done
Researched and wrote a decision-ready design for (1) copy message text from the chat context menu and (2) paste text + images into the composer. Scope confirmed with user: copy-text included; images-only paste; v1 = 1 staged image + caption; web parity required. Competitor survey (WhatsApp/Telegram/Signal/iMessage/Messenger/Discord/Slack): long-press → Copy is universal; every app *stages* pasted images with a preview (chip or confirm sheet) — none send instantly. Code audit confirmed: context menu (`MessageActionPanel`, 4 rows, `kMessageActionPanelHeightEstimate=184`) is the copy insertion point; bubbles are NOT selectable (`RichText`); current image flow has **no staging preview and no caption** (`content: ''`); `AttachmentHandler.sendImage(bytes, filename, mimeType)` is the ideal paste→E2E reuse point into `sendImageMessage` → `EncryptedMediaUploadService`. Platform paths: web = `paste` DOM event (`clipboardData.files`, no permission prompt; NOT `navigator.clipboard.read()`) via a new stub/web pair; Android native = `TextField.contentInsertionConfiguration` (Gboard commitContent, no plugin); native iOS deferred (PWA covers iOS). Recommended: context-menu Copy (TEXT only, placeholder/failed guards) + staged composer chip above the input row (sibling of ReplyPreviewBar — TextField never unmounts), send = image then caption text as two messages from one gesture (true captions are envelope-ready, Phase-2).

## Key files
- `docs/superpowers/specs/2026-06-10-clipboard-copy-paste-design.md` (the spec — 5 phases, file-level)
- Audited: `widgets/message/message_action_panel.dart`, `message_context_menu_overlay.dart`, `chat_message_bubble.dart`, `widgets/input/chat_input_bar.dart`, `attachment_handler.dart`, `chat_action_tiles.dart`, `providers/messaging/messaging_provider.send.dart`, `models/message_model.dart`

## Verification
Design-only session — no code changed, no tests run. Spec self-reviewed (no placeholders/contradictions).

## Notes for next session
- Awaiting user review of the spec; then `superpowers:writing-plans` → implementation.
- Implementation gotchas already identified: panel-height estimate must become row-count-aware (5th row); trailing-send visibility needs `|| staged`; `[Decryption failed]` label is library-private in `messaging_provider.dart` — copy guard needs a public helper; web paste invisible to `flutter test` (kIsWeb false) → manual QA list in spec Phase 3.
