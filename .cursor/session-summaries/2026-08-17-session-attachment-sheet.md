# 2026-08-17 — Attachment picker: 0.1.14 (in-app sheet) then 0.1.15 (sheet deleted, OS picker direct)

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

---

# Same session, second release — 0.1.15: the flatten (PR #143, `9cdf916`)

Owner spotted that 0.1.14's in-app sheet was a redundant hop on iOS: a plain
`<input type=file>` (NO capture attribute) with a mixed media+document accept list makes
iOS Safari itself present **Photo Library / Take Photo or Video / Choose File** — camera
photo/video toggle included. Device-proven via `probe2.html` (LAN, beaconed) BEFORE
building: trio appears for both extension-style and MIME-style accept; owner picked
successfully from both; the `cancel` event fired twice (closing 0.1.14's residual unknown).

## What shipped

- Paperclip → ONE `FilePicker.pickFiles(type: custom, allowedExtensions: images+videos+docs,
  withData: true)`. No in-app sheet.
- `_routePickedFile`: image whitelist → stage, video whitelist → stage, document whitelist →
  `_sendDocument` (immediate send, extracted from the old `_pickDocument`), anything else →
  `attachmentUnsupportedFileType` toast.
- DELETED: `_AttachmentSheet`, `_AttachmentAction`, `camera_capture_stub/web.dart`,
  ARB keys `attachmentOptionPhotoLibrary`/`attachmentOptionTakePhoto`. Net −238 lines.
- Trade-offs (owner-informed): **Android loses the in-chat camera shortcut** (mixed accept →
  generic file UI); a native APP build would get a file browser instead of the photo gallery
  (`pickMedia()` branch deleted; PWA-only surface, reviewer-flagged, accepted).

## Verification

- Analyze clean; suite 1315/10sk; CI 4/4 on all three branch commits.
- Browser E2E: paperclip opens the chooser DIRECTLY (no sheet); PDF → sent document bubble;
  mp4 → staged video chip; fake `.heic` → unsupported toast, nothing staged.
- **Evidence-precision episode (advisory challenged the heic claim):** the challenge said
  CDP-fed files are accept-filtered before Dart runs, making the toast unreachable —
  DISPROVEN by re-demo with screenshot (CDP `DOM.setFileInputFiles` bypasses accept
  filtering; the earlier chooser timeout was a stale-ref misclick that opened the timer
  sheet). Honest residue, noted on the PR: the branch is code-exercised; its REAL-WORLD
  trigger (an iOS HEIC Safari didn't transcode) has never been observed on a device.
- Independent reviewer (reviewer agent): verdict SHIP; 1 stale doc comment fixed (`23afe08`).

## Deploy + the Giphy-key incident

- Merge `318bdf3` (a parallel-session docs commit `64ca12e` rode along), bump `9cdf916`,
  build in worktree, manual staged publish, smoke 5/5.
- **⚠️ The FIRST 0.1.15 publish shipped without the Giphy key** — `deploy-web.config.ps1`
  (gitignored) wasn't copied into the fp-flatten worktree; the script's BaseUrl/VAPID
  parameter defaults masked the miss and smoke passed (smoke has no GIF check). GIF search
  was dead in prod for ~15 minutes. Caught by advisory, rebuilt with the config,
  republished, key presence verified in the LIVE `main.dart.js` (1 occurrence, md5-matched
  to the local build), smoke re-run 5/5.
- **Rule going forward: before publishing any worktree build, grep the built
  `main.dart.js` for the Giphy key** (and remember the `bash` tool mangles `$var` in ssh
  command strings — the false-negative remote grep here; verify via python subprocess).
