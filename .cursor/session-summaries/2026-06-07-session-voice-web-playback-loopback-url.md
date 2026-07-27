# Voice (and all) media playback broken on web — loopback media-URL rewrite skipped on web

**Date:** 2026-06-07

## What was done

Diagnosed and fixed: voice messages record + send fine everywhere but **fail to play on web** ("nie można odtworzyć / Nie udało się wczytać dźwięku" top-snackbar = `snackbarFailedToLoadAudio`). User confirmed it fails on **every device**, for **both own and received** messages.

### Root cause
`ApiService._effectiveMediaUrl` (now `rewriteLoopbackMediaUrl`) short-circuited with `if (kIsWeb) return url;`. Stored `mediaUrl` carries the backend's `MEDIA_BASE_URL`, default `http://localhost:3000`. Native rewrites that `localhost` host to `AppConfig.baseUrl`'s host (the fix originally added for the Android emulator, commit `3225a5f`), so native always reaches the real backend. **Web never rewrote**, so it fetched `http://localhost:3000/media/msgs/…` verbatim — and on any device that isn't the backend host (a phone via `run_web_for_phone.ps1`, or any non-dev-PC browser), `localhost` resolves to that device itself → fetch fails → `snackbarFailedToLoadAudio`. Recording/sending works because upload uses `BASE_URL` correctly; both own and received rows fail because both carry a `localhost` URL.

### Ruled out (with evidence, before fixing)
- **Typeless blob MIME hypothesis** — empirically **disproved** in real Chrome (Playwright): generated genuine webm/opus and mp4/aac recordings via `MediaRecorder` (synthetic oscillator, no mic), confirmed both typed AND typeless blob URLs load in an `<audio>` element. So the missing blob `type` is not the cause.
- Safari/WebM-Opus format incompat — ruled out: fails on *every* device, not Safari-only.
- Storage path / 404 — read/write paths match (`mediaDir/msgs/{uuid}.bin`).

### Fix
- Extracted the rewrite into a pure top-level `rewriteLoopbackMediaUrl(url, baseUrl)` applied on **all platforms** (removed the `kIsWeb` gate). Also adopts baseUrl's authority **fully**: `port: b.port` (was `b.hasPort ? b.port : u.port`) so an https same-origin base doesn't get a stray `:3000` (Dart drops default ports in `toString`). Android case (baseUrl always `:3000`) unchanged.
- Added regression test (a unit test could not have caught the original bug: `kIsWeb` is `false` under `flutter test`, so the buggy web branch was never exercised on the VM).
- Bumped version `0.0.32` → `0.0.33`. Updated CLAUDE.md §1 (Frontend, "Authenticated media").

### Latent issue flagged (NOT fixed — out of scope)
`playback_controller.dart` web branch `else { _audioPlayer.setUrl(mediaUrl); }` (taken when `mediaKey`/`mediaIv` are null) loads the JWT-guarded, still-encrypted blob with no auth header → would fail. Not the reported bug (E2E voice carries keys), but worth hardening later.

## Key files
- `frontend/lib/services/api_service.dart` — `rewriteLoopbackMediaUrl` (new top-level fn), `_effectiveMediaUrl` delegates; removed `kIsWeb` gate; `port: b.port`.
- `frontend/test/services/api_service_media_url_test.dart` — new (7 tests).
- `frontend/pubspec.yaml` — `0.0.33`.
- `CLAUDE.md` — §1 Frontend "Authenticated media" bullet.

## Verification
- `flutter analyze lib/services/api_service.dart test/services/api_service_media_url_test.dart` → No issues found.
- `flutter test` → **All tests passed (282)** (275 prior + 7 new).
- Empirical browser check (Playwright/Chrome) disproving the MIME hypothesis.
- **PENDING user device confirmation:** (1) browser console shows the failing `/media/msgs/…` request URL contains `localhost`; (2) after `flutter run`/rebuild, voice plays on the phone-web build. Could not reproduce locally — this dev PC has no microphone, so a fresh web recording can't be made here.

## Notes for next session
- If the user's console error shows a non-`localhost` failing URL (e.g. a prod `https://…/media/msgs/…` 401), the loopback fix is still correct but a second cause exists — investigate auth/CORS or the null-key `else setUrl` branch above.
- Consider hardening the `playback_controller` web `else` branch (authenticated fetch instead of raw `setUrl`).
- Deploy needs prod `MEDIA_BASE_URL` set to the public origin so stored URLs aren't `localhost` going forward.
