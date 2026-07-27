# Ping visual and sonic identity research

**Date:** 2026-07-10

## What was done
- Traced Fireplace's ping UI and audio path without changing application code.
- Confirmed the mismatch: action tile uses `Icons.auto_awesome`; message and overlay use `Icons.campaign`; the overlay adds an orange circle.
- Confirmed the active sound is `assets/sounds/ping_alert.mp3` (~1.071 s, 44.1 kHz, 320 kbps); the unused `ping.mp3` is zero bytes.
- Identified Wire's official ping glyph from its 2024 support guide: a centerless radial attention burst used consistently for the action and the resulting indicator.
- Researched sound-source licensing and developed four icon directions plus three sound directions.
- Recommended an original Fireplace 8-ray pulse burst shared everywhere, paired with a short warm double-tap sound. No Wire vector/audio should be copied.
- Built the owner-requested throwaway warm double-tap prototype: original 660→990 Hz synthesis, 420 ms, with an audition page combining the proposed pulse-burst visual and replay controls. It remains outside the app.
- Owner rejected the sharper 1320 Hz revision and approved the original 660→990 Hz sound. Integrated that original render as `ping_alert.wav`, removed the obsolete MP3, updated web/native playback paths, added a bundled-asset contract test, and bumped the app to 0.0.105.
- Owner then approved the original shared pulse-burst. Added one reusable centerless 8-ray `PingGlyph`; action tile, message indicator, and overlay now use it at 24/18/50 px. The overlay uses two restrained orange pulse rings behind the white glyph. Old sparkles/megaphones are gone.
- Isolated the release from unrelated `chore/node-22-upgrade` work, committed/pushed `a31fab2`, and the owner merged PR #62 as master commit `2afdd50`. Rebuilt and atomically published merged master to production.

## Key files
- `.planning/2026-07-10-ping-identity-research/findings.md`
- `.planning/2026-07-10-ping-identity-research/prototype/generate_ping.py`
- `.planning/2026-07-10-ping-identity-research/prototype/fireplace_ping_warm_double_tap.wav`
- `.planning/2026-07-10-ping-identity-research/prototype/audition.html`
- `frontend/assets/sounds/ping_alert.wav`
- `frontend/lib/widgets/ping_glyph.dart`
- `frontend/test/widgets/ping_glyph_test.dart`
- `frontend/test/utils/ping_sound_asset_test.dart`
- `frontend/lib/widgets/chat_action_tiles.dart`
- `frontend/lib/widgets/message/ping_message_content.dart`
- `frontend/lib/widgets/ping_effect_overlay.dart`
- `frontend/lib/utils/ping_sound_web.dart`
- `frontend/lib/utils/ping_sound_stub.dart`

## Verification
- Source-read all current ping visual and playback call sites.
- Verified the Wire reference against Wire's official support article and attachments: https://support.wire.com/hc/en-us/articles/204140584-Send-a-ping
- Verified licensing summaries from Freesound and Pixabay; Mixkit's notification catalogue and license entry were reviewed, but an individual downloaded effect was not selected.
- Validated the prototype WAV: mono 48 kHz/16-bit, 420 ms, −6.000 dBFS peak, −19.422 dBFS RMS, zero clipped samples, 41.77 ms final tail below −50 dBFS, and exact digital silence at EOF.
- Browser audition loaded the WAV (`readyState=4`) and played once through `ended` at 0.42 s.
- Pulse-burst verification: focused analyze clean; `ping_glyph_test.dart` + `ping_effect_overlay_test.dart` + `chat_input_bar_send_test.dart`, **27 tests passed**. LSP diagnostics clean; `graphify update .` completed with 8247 nodes/11727 edges.
- Production smoke passed: `/health`, frontend 0.0.105, backend 0.0.104/b7708ed, served bundle contains exact master SHA `2afdd50`, and fresh Chromium app boot rendered.

## Notes for next session
- Approved sound and shared pulse-burst are live in production as frontend 0.0.105 / master `2afdd50`.
- Fully close and reopen the PWA to load the new service-worker bundle; do not uninstall or clear site data.
