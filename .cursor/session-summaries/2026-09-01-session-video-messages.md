# Video messages: aspect-correct bubble, fullscreen player, immediate send, cap realignment

**Date:** 2026-09-01

## What was done

Owner reported three video-message defects and approved a scoped plan (moves 1+2+3 of a five-move
roadmap; moves 4/5 — native transcode and chunked-AEAD streaming — deliberately NOT built).

**The "20 second cap" does not exist in the codebase.** Grepped exhaustively: the only duration gate
was 60 s, and `image_picker.pickVideo(maxDuration:)` is never called. iOS's file-input camera caps at
10 minutes. Measured the owner's actual 0:19 clip still on the VM (`2202fec3-….bin`, **1.96 MB**) =
**103 KB/s**, matching the documented WebKit behaviour that HTML Media Capture downsamples to
~360x480. At that bitrate no size limit produces a 20 s wall. Reported as unexplained rather than
"fixed"; the owner's number remains unreproduced.

**The real defect nobody reported:** the client promised 20 MB while prod nginx allowed 11 MB, so
11–20 MB uploads 413'd *after* a full upload with a hardcoded-English generic error. A full-quality
gallery clip (~12 Mbps) hits 11 MB in ~7 s.

1. **Geometry (move 1).** `sendVideoMessage` never wrote `mediaWidth`/`mediaHeight`/`mediaThumbHash`,
   so `MediaPreviewFrame` fell to its fixed `legacyHeight = 220` — the squat letterboxed box with
   white side bars. All plumbing already existed (model fields, envelope keys, ratio math); only the
   producer was missing. Added `probeVideoPreview` (web: `<video>` + canvas frame-0 → ThumbHash;
   native: `video_player` coded size). Probed ONCE in the composer and threaded through — the
   provider never re-probes. **Zero backend change**: geometry rides inside the encrypted envelope.
2. **Playback (move 2).** Bubble is now a static poster (ThumbHash + duration pill + play badge) with
   **no `VideoPlayerController` in the list at all**; tap opens a new fullscreen viewer that owns the
   only controller. Kills the "N live players / N decrypted multi-MB buffers" hazard the old file's
   own header warned about.
3. **Immediate send (move 3).** Video no longer stages — iOS's own `Retake / Use Video` screen is
   already the confirmation, so the composer chip was a second confirm. Video staging removed
   entirely (`StagedAttachmentKind`, `stageVideo`, chip video branch); images still stage because a
   gallery tap is their only confirmation and they carry captions.
4. **Caps, atomically.** duration 60 → **180 s** (`MediaCryptoService.maxVideoDurationSeconds`; at the
   measured 103 KB/s that is 18.5 MB, inside `maxBytes`), host nginx `client_max_body_size`
   **11m → 21m**, and a new `_kLargeMediaTimeout = 180 s` for the two encrypted-media calls
   (`uploadEncryptedMedia`, `fetchMediaBytes`) — 20 MB in 60 s needs ~2.8 Mbps sustained, and
   `fetchMediaBytes` has no streaming/resume so a timeout there is a permanently unplayable video.
   Avatar upload stays at 60 s.

### Two defects caught by review before shipping

- **Android rotation.** `video_player` reports `value.size` as the CODED size with
  `rotationCorrection` separate, and its `aspectRatio` getter IGNORES rotation (the widget
  compensates with `RotatedBox`). A phone portrait recording arrives 1920x1080 + 90° — the probe
  would have published every portrait clip as landscape. Added `videoRotationSwapsAxes`, applied in
  the native probe AND in the fullscreen viewer's `AspectRatio`.
- **ThumbHash red X.** `fast_thumbhash.toImage()` returns a `MemoryImage` from its own hand-rolled
  PNG encoder, which Flutter web's browser `ImageDecoder` REJECTS
  (`EncodingError: Failed to decode frame at index 0`). Pre-existing for images/GIFs too, but hidden
  behind the loaded photo; a video poster has nothing on top, so it filled the whole bubble. Added an
  `errorBuilder` degrading to blank. **Confirmed pre-existing** by sending a control image through
  the untouched path and observing the identical error.

## Key files

- `frontend/lib/utils/video_preview.dart` (new) — `VideoPreview`, `kSendableVideoExtensions`, `videoRotationSwapsAxes`
- `frontend/lib/utils/video_probe_web.dart` (rewritten), `video_probe_io.dart` (new), `video_probe_stub.dart`
- `frontend/lib/widgets/message/video_message_content.dart` (poster-only), `video_fullscreen_view.dart` (new)
- `frontend/lib/widgets/message/media_preview_frame.dart` — ThumbHash `errorBuilder`
- `frontend/lib/providers/messaging/messaging_provider.send.dart`, `messaging_provider.dart` — geometry through send
- `frontend/lib/widgets/input/chat_input_bar.dart` — `stagePickedVideo` → `sendPickedVideo` (immediate)
- `frontend/lib/widgets/chat_action_tiles.dart` — `onStageVideo` → `onPickedVideo`
- `frontend/lib/services/api_service.dart`, `media_crypto_service.dart`, `frontend/nginx.conf`
- `frontend/integration_test/video_probe_device_test.dart` (new) — on-device native-probe acceptance
- VM: `/etc/nginx/sites-enabled/fireplace:23` (backup `.fireplace.bak-<ts>` alongside)

## Verification

- `flutter analyze --no-fatal-infos` clean; **`flutter test` 1342 passed / 10 skipped** (was 1330);
  CLAUDE.md §3 bumped and `verify-claude-frontend-test-counts.mjs` OK.
- **On-device probe acceptance (new): `integration_test/video_probe_device_test.dart`, 3/3 on a
  Pixel 7.** Asserts the EXACT values the native probe returns — `width == 1080`, `height == 2400`,
  duration ≈ 7.66 s, `durationInSeconds == 8` — plus graceful `unknown` for non-video bytes. This
  replaces an earlier claim that rested on measuring bubble pixels. **Falsified before trusting it:**
  forcing `hasGeometry = false` in the probe turns it red with `probe returned no geometry`; reverted
  and re-greened.
  - Fixture must live at `/data/local/tmp/clip.mp4` (0644). `/sdcard/Download` is blocked by scoped
    storage (stats fine, throws on open) and anything under the app's own dirs is destroyed every
    run — **`flutter test integration_test` UNINSTALLS the package when it finishes**. Missing
    fixture SKIPS, never fails.
- **Live two-account browser E2E** (isolated backend on :3010, real Signal): pick → immediate send →
  portrait bubble → tap → decrypt → fullscreen playback, on BOTH sender and receiver. Receiver sized
  the bubble portrait from the encrypted envelope alone.
- **Android emulator (Pixel 7) UI pass**: picked `clip.mp4` → sent immediately, portrait bubble,
  `0:08` from the native probe, fullscreen decrypt+playback OK. web→Android also carried geometry.
- **Prod ceiling proven moved**: `POST /media/upload` with 15 MB → **401** (body reached the backend;
  it was a 413 before), 25 MB → **413**. `nginx -t` OK, reload clean.

## Notes for next session

- **⚠ Android→web decryption failed in the scratch setup — for PLAIN TEXT too** (`[Decryption failed]`
  on a text message from the same session). Encryption code was not touched; this is the known
  pre-existing session issue, reproduced here with three throwaway accounts. **Android→web video
  geometry is therefore UNVERIFIED end to end** (web→web, web→Android and Android-local all verified).
  Worth a look on its own — a clean repro with fresh accounts may be valuable for the standing
  `[Decryption failed]` investigation.
- **A real rotated phone recording is untested.** `videoRotationSwapsAxes` has unit coverage and the
  emulator clip carried no rotation matrix, so the 1920x1080+90° path is logic-verified only.
- **X-Accel offload is NOT a small deploy — dropped.** `MEDIA_X_ACCEL_REDIRECT` is absent from prod
  `.env` and there is no `internal/media` location on the host, so Express `res.sendFile()` serves
  every media byte through the Node event loop. Enabling it needs nginx to read the Docker volume,
  but `/var/lib/docker` is `710 root:root` and `www-data` is DENIED. Would require loosening Docker
  root perms or remounting the media volume. Matters before any streaming work (move 5).
- **Ranged fetch already works** end to end (`curl -r 0-1023` → `206 content-range`), so move 5 needs
  no server work. The only blocker is client-side: whole-file AES-GCM with a single IV
  (`media_crypto_service.dart`) cannot authenticate a byte until the last one.
- `/media/avatars/:filename` has **no `JwtAuthGuard`** (`msgs` does) — fetched a 2.8 MB avatar
  unauthenticated. UUID filenames so not enumerable; noted, not fixed, not asked for.
- Not committed and not deployed to the frontend — awaiting owner review. The nginx change IS live.
- Kaspersky deleted `deploy-web.ps1` from the working tree again mid-session; restored via
  `git checkout`. Exclude the repo directory in AV.
