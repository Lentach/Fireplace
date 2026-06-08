# Latest session summary

**Date:** 2026-06-08

**Topic:** **Media-send de-duplication** — removed ~4× duplicated encrypt→upload→patch boilerplate across `sendImageMessage`/`sendVoiceMessage`/`sendGif`/`sendFileMessage`, behavior-preserving. New pure **`EncryptedMediaUploadService`** (injectable; wraps `MediaCryptoService.encrypt` + `ApiService.uploadEncryptedMedia`; `onEncrypted` callback fires between encrypt and upload await to keep the `_pendingSendContent` key/iv invariant). New `_buildOptimisticMediaMessage` factory + `_mediaUpload` test seam (`setMediaUploadServiceForTest`). New provider tests for image/voice/file success+failure; gif download path is manual-review-only (non-injectable Giphy `http.get`). Per-type divergence preserved exactly. Version `0.0.44 → 0.0.45` (plan said 0.0.37 but repo had drifted to 0.0.44). `flutter analyze` clean, suite **308** green. Commits `cad36d9`/`0d673bf`/`e92f58f` + docs. Not yet deployed.

→ [2026-06-08-session-media-send-dedup.md](./2026-06-08-session-media-send-dedup.md)

**Previous:** 2026-06-08 — Fixed **received voice messages failing to replay after reopening the chat** (one-shot E2E media keys): downgrade guard in `saveDecryptedContent` + `_hasUsableDecryptedContent` accepts keyed non-TEXT rows despite placeholder text. Stale-build detour documented. v0.0.44. → [2026-06-08-session-voice-replay-reopen-fix.md](./2026-06-08-session-voice-replay-reopen-fix.md)

**Earlier:** 2026-06-08 — Voice audio coordination (`VoiceAudioCoordinator`: one-voice-at-a-time, pause-on-record, stop-on-leave) + iOS mic re-prompt diagnostic (Part B, still open). v0.0.36. → [2026-06-08-session-voice-audio-coordination.md](./2026-06-08-session-voice-audio-coordination.md)
