# Media preview rendering proposal approved

**Date:** 2026-07-09

## What was done

- Diagnosed source-confirmed image/GIF preview crop: both force a full available-width × 220 logical-pixel box and use `BoxFit.cover`; fullscreen uses `BoxFit.contain`, so it displays the uncut image.
- Established that Fireplace has no VIDEO message enum, render widget, upload path, or player. Video poster/duration UX is future feature scope, not a third current renderer.
- Traced the E2E envelope and lifecycle: it has type/URL/duration/key/IV but no dimensions or preview hash; receivers cannot reserve true geometry before Signal decrypt under the current contract.
- Researched Telegram, Signal, WhatsApp private protocol, and the absence of public Messenger consumer-client source. Confirmed Telegram W×H sizing/min/max source behavior, Signal attachment dimensions+BlurHash, WhatsApp Web schema dimensions+JPEG poster, and Flutter web-capable placeholder options.
- Wrote the cited proposal and collected owner decisions. **Approved:** Stages A+B+C; encrypted `mediaWidth`/`mediaHeight` plus optional ThumbHash; contain/letterbox at `<1:2`/`>3:1`; IMAGE/GIF only; no video scope.
- No application code was changed.

## Key files

- `docs/review/2026-07-09-media-preview-rendering-proposal.md` — cited diagnosis, competitor comparison, formula, privacy/back-compat contract, staged implementation plan, and approved owner decisions.
- `.planning/2026-07-09-media-preview-proposal/{task_plan,findings,progress}.md` — research work record.
- `frontend/lib/widgets/message/{image_message_content,gif_message_content,chat_message_bubble,message_content_factory}.dart` — verified rendering path.
- `frontend/lib/{utils/e2e_envelope.dart,providers/messaging/messaging_provider.send.dart,providers/messaging/messaging_provider.decrypt.dart,models/message_model.dart}` — verified wire/timing path.

## Verification

- Targeted source tracing; no tests run because this session made no application-code change.
- Read direct official/open-source primary sources: Telegram Android/TDLib, Signal Android, official ThumbHash/Flutter APIs. WhatsApp evidence is labelled as a third-party mirror of the private web protocol; Messenger consumer UI is explicitly not claimed without a public source.
- Flutter package viability checked against Fireplace Dart `^3.10.7`: `fast_thumbhash 1.2.1` allows `<4.0.0`, declares pure Dart/zero dependencies, and has no platform import in entry source. Actual web build proof is owed in the implementation PR.

## Notes for next session

- Implementation is authorized but must respect the owner-approved wire boundary: `mediaWidth`, `mediaHeight`, and ThumbHash belong solely inside the Signal-encrypted `E2eEnvelope`; never add them to the outer socket payload, backend DTO/entity/mapper/log, REST message model, or database.
- Start with shared `MediaPreviewFrame`, then migrate both image and GIF routes. Use `BoxFit.contain`, not `cover`; retain a stable existing `width × 220` fallback for old envelopes with no dimensions.
- Future video is explicitly out of scope. Do not add an untested video path while fixing image/GIF.
