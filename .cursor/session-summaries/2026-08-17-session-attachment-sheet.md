# 2026-08-17 — Attachment sheet: Gallery/Camera tiles collapsed into the paperclip (0.1.14)

Owner follow-up to the 0.1.12 picker redesign: the separate Gallery and Camera action tiles
are deleted; the paperclip is the single attachment door again, opening a three-option glass
sheet. Shipped as **0.1.14 / `74d6764`** (PR #142, frontend-only — backend stays 0.1.11),
deployed, smoke 5/5.

## What shipped

- Action row back to 6 tiles (delete, timer, ping, paperclip, GIF, anti-quantum).
- Paperclip → `_AttachmentSheet` (same `showGlassSheet` pattern the camera-mode sheet used):
  - **Biblioteka zdjęć** (`attachmentOptionPhotoLibrary`) → the existing gallery flow
    (photos AND videos; native `pickMedia()`, web FilePicker media whitelist).
  - **Zrób zdjęcie** (`attachmentOptionTakePhoto`) → ONE row for both stills and clips.
    Web uses a raw capture input `accept="image/*,video/*" capture="environment"`
    (`lib/utils/camera_capture_stub.dart` / `camera_capture_web.dart`, conditional import
    mirroring `video_probe_*`) — the OS camera exposes its own photo/video toggle.
    `_CameraModeSheet` DELETED. Native mobile falls back to still-only capture
    (image_picker has no dual-mode camera API; the PWA is the shipped surface).
  - **Dokument** (`attachmentOptionDocument`, reused key) → unchanged docs flow.
- `_stagePickedMedia` routing is now explicit both ways: image whitelist → image, video
  whitelist → video, anything else → NEW red toast `attachmentUnsupportedFileType`
  ("Nieobsługiwany typ pliku"). Previously an unknown extension (e.g. HEIC) fell through
  to `onStageVideo` and died with a video-shaped error.
- ARB: +`attachmentOptionPhotoLibrary` +`attachmentOptionTakePhoto`
  +`attachmentUnsupportedFileType`; −`actionTileGallery` −`actionTileCamera`
  −`cameraModePhoto` −`cameraModeVideo`.
- Policy unchanged and still enforced at staging: extension whitelist, 20 MB, and the web
  duration probe rejects >60 s — the probe is what keeps camera clips capped now that
  `pickVideo(maxDuration: 60)` is gone from the web path.

## Device probe — the technique that unblocked the ship

The single-"Take photo" design stands on iOS Safari showing a photo/video toggle for a
broad-accept capture input. That is NOT testable in desktop/headless Chrome (capture
degrades to a file dialog). Instead of deploying blind: a ~50-line static
`probe.html` (three raw file inputs + a `fetch('/log?...')` beacon into `python -m
http.server` on the LAN — no HTTPS needed, plain file inputs have no secure-context
requirement, unlike the app itself whose Web Crypto login would fail over LAN HTTP).
Owner ran it on his iPhone; beacons proved:

- Shipped input → **`.MOV` / `video/quicktime` recorded** — the toggle EXISTS and the
  output extension passes the whitelist.
- Library pick with broad accept → **`IMG_3053.jpeg` / `image/jpeg`** — iOS transcodes
  HEIC→JPEG for web file inputs; the HEIC toast is a rarely-reachable safety net.
- `cancel` event: NOT exercised (owner never canceled). Failure mode benign — an
  unresolved future, no spinner, no hang; user just re-taps.

Keep this trick: **capture/file-input platform questions need only a static page on
`http.server`, not a deploy.**

## Verification ledger

- `flutter analyze` clean; full suite **1315 passed / 10 skipped** (twice, pre- and
  post-hardening); CI 4/4 green on both PR commits (`8a119ad`, `b256223`).
- Live two-client browser E2E on the dev stack (fresh accounts `attA4921`/`attB4921`):
  6-tile row confirmed; sheet renders (glass, PL labels); `.mp4` staged as video chip via
  Photo library; a real image staged via the CAPTURE-INPUT path → sent → decrypted →
  rendered on BOTH clients; chooser cancel → resolves null, zero leftover DOM inputs,
  nothing staged. (A degenerate 1×1 test PNG produced decode-error bubbles on both
  sides — test-file artifact, disproven with a real image, not a flow bug.)
- Deploy: build via `deploy-web.ps1 -SkipPublish -SkipVerify` in the worktree (config
  copied in), manual staged publish (exit-21 recipe), `/version.json` = `0.1.14/74d6764`,
  backend `/version` = 0.1.11 unchanged, `post-deploy-smoke.mjs --commit 74d6764` 5/5.

## Session notes / traps

- Dev stack was DOWN at session start despite hub `devstack` showing "ready" (its DB shut
  down hours earlier — the hub row was a stale compose attach). `docker compose up -d`
  from the main repo brought it back; `/version` needs ~2.5 min (nest watch-mode compile).
- Worked from throwaway worktree `C:/tmp/fp-attach`; main tree untouched (still has the
  parallel session's `deploy-web.ps1` delete).
- `gh pr merge --delete-branch` errors with "master is already used by worktree" when the
  main tree holds master — the MERGE still succeeds; delete the remote branch explicitly.
- Advisory-driven honesty round mid-review: my first ship report overclaimed
  device-dependent behavior (toggle, cancel) as verified. Corrected before merge; the
  probe then turned the inference into evidence. The HEIC routing hole was found in the
  same round and fixed as `b256223`.

## Open threads (unchanged from the 0.1.11 handoff)

- Owner's device A/B of the two composer-motion changes — still owed.
- `deploy-web.ps1` exit-21 publish halt — 7th manual publish this train; still un-root-caused.
- Phase-2 video candidates (posters, shared-media tiles, custom camera) — do not build unasked.
