# Latest session summary

**Date:** 2026-06-08

**Topic:** Fixed **received voice messages failing to replay after reopening the chat** (own messages always worked; received died on reopen). Root cause = two coupled bugs on received E2E media (keys are one-shot per Double Ratchet): (1) on reopen the row was re-decrypted → `DuplicateMessage` → handler overwrote the persisted keyed entry with `[Decryption failed]`; (2) even when preserved, restore rejected the keyed row because a decrypted voice has empty text so content stays `[encrypted]`. Fix (both): **downgrade guard** in `EncryptionService.saveDecryptedContent` (never overwrite a keyed entry with a keyless one, +3 tests) + **`_hasUsableDecryptedContent`** treats `mediaKey`+`mediaIv`+`mediaUrl` non-TEXT rows as usable despite placeholder text (skips the pointless re-decrypt). **Big detour:** the fix (`ba414b3`) was pushed but `flutter build web` served a **cached** bundle (`gitCommit 958edfc` while version said 0.0.43) + PWA cache — we tested pre-fix code for many rounds until `flutter clean` + reinstall made it live → **confirmed working in prod**. Lesson documented in CLAUDE.md §0 (trust `gitCommit`, not version number). Shipped clean **`0.0.44`** (`d04c7a7`) stripping all temp diagnostics. `flutter analyze` clean, suite **299** green, web build OK. Pre-fix messages (7440–7442) are permanently unrecoverable.

→ [2026-06-08-session-voice-replay-reopen-fix.md](./2026-06-08-session-voice-replay-reopen-fix.md)

**Previous:** 2026-06-08 — Voice audio coordination (`VoiceAudioCoordinator`: one-voice-at-a-time, pause-on-record, stop-on-leave) + iOS mic re-prompt diagnostic (Part B, still open). v0.0.36. → [2026-06-08-session-voice-audio-coordination.md](./2026-06-08-session-voice-audio-coordination.md)

**Earlier:** 2026-06-07 — Fixed web voice playback: loopback media-URL rewrite on web (`rewriteLoopbackMediaUrl`) + blob MIME type (`detectAudioMimeType`) for mobile Safari/Chrome. v0.0.33→0.0.35. → [2026-06-07-session-voice-web-playback-loopback-url.md](./2026-06-07-session-voice-web-playback-loopback-url.md)
