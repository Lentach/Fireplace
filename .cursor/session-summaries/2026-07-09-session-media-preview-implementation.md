# Encrypted media preview aspect-ratio implementation shipped

**Date:** 2026-07-09

## What was done

- Implemented the owner-approved IMAGE/GIF media-preview correction on `fix/media-preview-aspect-ratio`; PR [#58](https://github.com/Lentach/Fireplace/pull/58) is open at commit `dca8ccb`.
- Replaced duplicated fixed-height, `BoxFit.cover` previews with a shared `MediaPreviewFrame`: intrinsic aspect ratio for normal media, 3:1 panorama and 1:2 portrait bounds with intentional letterboxing, 96px minimum tappable media, and exact legacy 220px fallback when dimensions are absent.
- Added `mediaWidth`, `mediaHeight`, and optional `mediaThumbHash` to the Signal-encrypted `E2eEnvelope` only. The outer socket payload, server DTO/entity/mapper/log, REST payload, and database were not expanded.
- Extracted image/GIF dimensions and an optional compact ThumbHash before encrypting a new outbound message; preserved the fields across optimistic state, pending-send snapshots, acknowledgements, decrypt/cache recovery, history merge, and media retry.
- Added focused tests for envelope round trips and hostile metadata rejection, size bounds and legacy behavior, `BoxFit.contain` rendering, and non-leakage of geometry/hash from the outer send payload.
- Bumped the frontend release version from `0.0.102` to `0.0.103`.

## Key files

- `frontend/lib/utils/{e2e_envelope,media_preview_metadata}.dart` — encrypted metadata schema/validation and local dimension/ThumbHash extraction.
- `frontend/lib/models/message_model.dart` — metadata carried by message state and `copyWith`.
- `frontend/lib/providers/messaging/{messaging_provider.send,messaging_provider.decrypt,messaging_provider.history}.dart` and `messaging_provider.dart` — encrypted send, recovery, history, cache, and retry propagation.
- `frontend/lib/widgets/message/{media_preview_frame,image_message_content,gif_message_content}.dart` — bounded contain/letterbox rendering.
- `frontend/test/{utils/e2e_envelope_test.dart,providers/messaging_provider_media_send_test.dart,widgets/message/media_preview_frame_test.dart}` — regression coverage.
- `docs/review/2026-07-09-media-preview-rendering-proposal.md` — approved design and provenance.

## Verification

- `flutter test test/utils/e2e_envelope_test.dart test/widgets/message/media_preview_frame_test.dart test/providers/messaging_provider_media_send_test.dart` — **31 passed**.
- `flutter analyze --no-fatal-infos` — **no issues**.
- `flutter build web --release --no-wasm-dry-run` — **succeeded**.
- `graphify update` — **succeeded**; 8,212 nodes and 11,677 edges.
- Independent GPT-5.5 review confirmed the encrypted-only boundary, compatibility fallback, propagation, and IMAGE/GIF scope. Its initial isolate concern was adjudicated: `fast_thumbhash` async helpers are unsupported on Flutter web, but this implementation uses only synchronous encode/decode APIs; the web release build passed. The production code explicitly records that constraint.

## Notes for next session

- PR #58 is ready for normal review and merge approval; it does **not** deploy until merged to `master`.
- Do not call `fast_thumbhash` async helpers from web-executed code; they use isolates. Keep the current synchronous encode/decode calls unless a web-safe asynchronous path is deliberately designed and verified.
- VIDEO remains explicitly out of scope: Fireplace has no video message renderer, poster pipeline, or player. Do not extend this PR with one.
