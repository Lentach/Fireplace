# Media preview rendering: diagnosis and owner proposal

**Date:** 2026-07-09  
**Scope:** research and approval proposal only. No application code changed.

## Verdict

Fireplace does not have three preview bugs. It has one implemented bug in two media types: image and GIF previews force an available-width × 220 logical-pixel box and use `BoxFit.cover`; source pixels outside that fixed aspect ratio are cropped. The full-screen viewer uses `BoxFit.contain`, so it exposes the complete media and makes the mismatch conspicuous. There is no video message type, upload path, or renderer in the current app; video poster behavior is future scope.

A one-line `cover → contain` change would stop cropping, but it would leave every media message at an arbitrary fixed aspect ratio and cannot reserve the true geometry during receive/decryption. The durable fix is encrypted-envelope width/height plus bounded, aspect-aware layout. Optional ThumbHash is a polish layer, not a prerequisite for correct geometry.

## 1. Fireplace current behavior

| Area | Verified behavior | Evidence |
|---|---|---|
| Bubble width | The bubble computes max width as 85% of parent constraints, then passes `maxBubbleWidth - 32` as content width. | `frontend/lib/widgets/message/chat_message_bubble.dart:275-282` |
| Image loading | Fetches media bytes, AES-GCM decrypts when key/IV exist, then returns bytes. | `frontend/lib/widgets/message/image_message_content.dart:47-71` |
| Image preview | Loading, failure, and success all reserve `double.infinity × 220`; success uses `Image.memory(... BoxFit.cover)`. | `image_message_content.dart:91-127` |
| GIF loading | Fetches/decrypts bytes; web turns them into an object URL to preserve animation. | `frontend/lib/widgets/message/gif_message_content.dart:61-104` |
| GIF preview | Loading/error/success use the same `double.infinity × 220`; network and memory paths use `BoxFit.cover`. | `gif_message_content.dart:140-205` |
| Actual clipping | Media bubbles have `Clip.hardEdge`. It clips the fixed child box, but `cover` is the direct image-content crop rule. Flutter defines `cover` as filling the target box and requires clipping to discard overflow. | `chat_message_bubble.dart:475-505`; [Flutter BoxFit API](https://api.flutter.dev/flutter/painting/BoxFit.html) |
| Fullscreen | Image and GIF dialogs use `InteractiveViewer` with `BoxFit.contain`; no crop. | `image_message_content.dart:73-88`; `gif_message_content.dart:106-137` |
| Video | No `video` enum member, no factory branch, no video content widget, and no `MessageType.video` reference in `frontend/lib`. | `frontend/lib/models/message_model.dart:7-16`; `frontend/lib/widgets/message/message_content_factory.dart:22-46`; targeted source search 2026-07-09 |
| Current envelope | The inner encrypted envelope is content/type/URL/duration/key/IV/link preview only. No dimensions, MIME, poster, thumbnail, BlurHash, or ThumbHash. | `frontend/lib/utils/e2e_envelope.dart:7-65` |
| Timing | The sender inserts optimistic IMAGE/GIF rows before reading/uploading bytes, without dimensions. Recipients obtain envelope values only after Signal decrypt; decrypted values are then persisted locally. | `messaging_provider.send.dart:126-180`, `:322-385`; `messaging_provider.decrypt.dart:102-143` |
| Server visibility | The inner envelope is JSON-encoded then Signal-encrypted. The existing outer socket payload separately exposes type, media URL, and duration for blob lifecycle. | `messaging_provider.send.dart:891-907`, `:932-952` |

**Consequence:** no receiver can determine the true aspect ratio from the current server message row or encrypted envelope before it decrypts/downloads the media. Correct no-jump geometry is a shared encrypted-envelope contract change, not a rendering-only change.

## 2. Major-app evidence

The request named Telegram, Signal, WhatsApp, and Messenger. The table separates source-verified facts from unverified folklore. Meta does not publish the current Messenger consumer-client rendering source or its private media envelope, so no claim about Messenger clamp constants is made.

| App | Verified sizing/metadata technique | Placeholder / video / GIF facts | Concrete clamps documented or source-observable |
|---|---|---|---|
| **Telegram** | TDLib `photoSize` contains width and height; `video` contains sender-defined duration, width, height, minithumbnail, thumbnail, and media file. Android's `ChatMessageCell` selects image sizes before full media and scales source W×H to `maxPhotoWidth - 2dp`. | Android selects a close `PhotoSize` thumbnail (`40` for a small fallback) and has a stripped-thumbnail path. TDLib explicitly supports video minithumbnails and thumbnails. | The Android client caps ordinary rendered height at **one third of display height**, with a **60dp minimum**; special Instagram/other path allows one half. This is direct source, not a universal Telegram product spec. |
| **Signal** | Current open Android `Attachment` has `width`, `height`, `videoGif`, and `blurHash`; `PointerAttachment.forPointer` maps all four from the received encrypted attachment pointer. | Signal stores/uses `BlurHash`; attachments expose a thumbnail URI when restored. This establishes dimensions + E2E-compatible blurred-preview design. | No single-chat-bubble min/max constant was established from the audited source in this session. Do not invent one. |
| **WhatsApp** | Meta's public Cloud API does not document consumer-client rendering layout. Its Business API is not proof of app UI. The widely used WhatsApp-Web protobuf (third-party Baileys mirror; private protocol, not a Meta stability guarantee) defines IMAGE width/height + JPEG thumbnail and VIDEO duration, GIF-playback flag, width/height, JPEG thumbnail, and thumbnail location. | The private-protocol schema shows poster thumbnail, duration, and inline GIF playback metadata are sent with the E2E media object. | No audited client-side bubble clamp constant. |
| **Messenger** | No current official/open-source consumer Messenger renderer or encrypted media envelope was found. Meta's public Messenger Platform Send API is a bot/business API, not consumer UI evidence. | No source-verified claim. | No source-verified clamp. |

### Primary / direct source links

- Telegram: [photoSize TDLib](https://core.telegram.org/tdlib/docs/classtd_1_1td__api_1_1photo_size.html), [video TDLib](https://core.telegram.org/tdlib/docs/classtd_1_1td__api_1_1video.html), [official Android `ChatMessageCell`](https://github.com/TelegramOrg/Telegram-Android/blob/master/TMessagesProj/src/main/java/org/telegram/ui/Cells/ChatMessageCell.java#L8468-L8545). The last link implements W×H scaling, min 60dp, and display-height cap.
- Signal: [Attachment](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/attachments/Attachment.kt), [PointerAttachment](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/attachments/PointerAttachment.kt), [DatabaseAttachment](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/attachments/DatabaseAttachment.kt).
- WhatsApp protocol evidence, explicitly **unofficial**: [Baileys `WAProto.proto` image fields](https://github.com/WhiskeySockets/Baileys/blob/master/WAProto/WAProto.proto#L2631-L2659), [video/GIF fields](https://github.com/WhiskeySockets/Baileys/blob/master/WAProto/WAProto.proto#L3598-L3636).
- Messenger limitation: [Meta Messenger Platform Send API](https://developers.facebook.com/documentation/business-messaging/messenger-platform/reference/send-api) is public bot API documentation, not the consumer app source.

## 3. Recommended full design — approval required

### 3.1 Envelope: encrypted only

Add nullable fields to the inner JSON envelope:

```json
{
  "mediaWidth": 3024,
  "mediaHeight": 4032,
  "mediaThumbHash": "base64url-or-base64"
}
```

- `mediaWidth`, `mediaHeight`: positive integer intrinsic pixel dimensions after orientation normalization. Required for all **new IMAGE and GIF** sends.
- `mediaThumbHash`: optional. Client-generated from a downscaled maximum-100px decoded image, stored as Base64. Recommend **ThumbHash** over BlurHash because the reference algorithm itself carries approximate aspect ratio, alpha, average colour and low-resolution appearance in roughly 25 bytes. Width/height remain authoritative because they are exact.
- Do **not** add any of these to `sendMessage` outer payload, backend DTO/entity/mapper, REST message fields, media-upload response, logs, or database columns. They remain only in `E2eEnvelope.build` → Signal ciphertext → local plaintext cache. This preserves what the server learns today.
- Validate when parsing: finite positive ints, range e.g. `1..32768`; ignore malformed/absent hash. Envelope input is sender controlled after decryption and must not be trusted for unbounded layout allocations.

This is a **shared wire-contract change** under `CLAUDE.md` §§7–8. It needs explicit owner approval before implementation, despite requiring no database migration.

### 3.2 Bounded geometry rule

At build time let `A` be the width available to the chat row, `dpr` be device pixel ratio, and `r = mediaWidth / mediaHeight`.

```text
Wmax = min(0.85 × A − bubbleHorizontalChrome, 360dp)
Hmax = min(0.65 × usableViewportHeight, 480dp)
Hmin = 96dp
Rframe = clamp(r, 0.50, 3.00)
WsourceCap = clamp(mediaWidth / dpr, Hmin, Wmax)
(frameW, frameH) = largest W×H inside (min(Wmax, WsourceCap), Hmax)
                   whose ratio is Rframe and whose H >= Hmin when possible
```

Use a `SizedBox`/`AspectRatio` whose ratio is `Rframe`, then stack metadata/play controls over it. Render the placeholder and decoded media with **`BoxFit.contain`**.

| Media shape | Result |
|---|---|
| `0.50 ≤ r ≤ 3.00` (ordinary photo, screen shot, 16:9 GIF) | Frame ratio equals source ratio; `contain` fills it. No crop or letterbox. |
| `r > 3.00` panorama | Width hits `Wmax`; frame is capped at 3:1. Image is contained/letterboxed vertically. No source pixels are discarded. |
| `r < 0.50` tall screenshot | Height hits `Hmax`; frame is capped at 1:2. Image is contained/letterboxed horizontally. No source pixels are discarded. |
| Tiny media | `WsourceCap` prevents a 16×16 or 40×40 asset from claiming the full chat width; `Hmin` preserves a tappable, legible 96dp minimum. |
| Missing/invalid dimensions (old messages) | Use current width × 220 fallback. When bytes later decode, keep that message's fallback geometry: no receive-time layout jump. It is compatible but may still letterbox after the UI-only `contain` change. |

**Decision:** choose letterboxing, not crop, at ratio extremes. The stated defect is lost visual content; cropping a panoramic/tall image merely moves the defect to its least-common aspect ratios. A neutral/ThumbHash-average background makes letterboxing intentional rather than broken.

### 3.3 Loading and animation

1. Build the exact outer frame immediately from encrypted metadata after envelope decrypt. It is stable while the blob fetch/AES decrypt/image decode runs.
2. If present, decode ThumbHash into the same frame, using `BoxFit.cover` **only for the placeholder background** or `contain` for exact no-crop parity; draw it behind the full media and crossfade the full media in.
3. Without a hash or for legacy messages, show a neutral surface colour plus progress indicator in the same fixed calculated/fallback frame.
4. Fullscreen remains `BoxFit.contain` + `InteractiveViewer`; no semantics change.
5. Future VIDEO should follow the same dimensions frame and use encrypted poster data/ThumbHash, centre play control, and duration badge. GIF is its own animation path today but should use the exact same `MediaPreviewFrame`; no separate sizing logic.

### 3.4 Flutter package viability

**Recommended candidate:** [`fast_thumbhash` 1.2.1](https://pub.dev/packages/fast_thumbhash). Its manifest permits Dart `>=2.19 <4` and Flutter `>=3`; Fireplace requires Dart `^3.10.7`. The package reports zero dependencies/pure Dart and provides synchronous/asynchronous encoder/decoder plus `ThumbHashPlaceholder`; its source entrypoint has no `dart:io`, FFI, or platform-channel import. **[INFERENCE]** This makes web compilation viable; prove it with `flutter test` plus `flutter build web` in the implementation PR.

Sources: [package manifest](https://raw.githubusercontent.com/KhaledSMQ/fast_thumbhash/main/pubspec.yaml), [README/API](https://github.com/KhaledSMQ/fast_thumbhash#readme), [entrypoint](https://raw.githubusercontent.com/KhaledSMQ/fast_thumbhash/main/lib/fast_thumbhash.dart), [official ThumbHash specification](https://github.com/evanw/thumbhash#readme).

Fallback: [`blurhash` 1.2.0](https://pub.dev/packages/blurhash) declares an Android, iOS, **and web** plugin and supports the project's Dart/Flutter floor. BlurHash requires separate W/H because decoding needs caller-provided output dimensions; its official API examples decode to explicit W×H. Sources: [pub API manifest](https://pub.dev/api/packages/blurhash), [BlurHash repo](https://github.com/woltapp/blurhash). Do not choose the old `thumbhash`, `flutter_thumbhash`, or `thumbhash_flutter` packages: their published SDK ceilings are `<3.0.0`, incompatible with Fireplace's `^3.10.7`.

## 4. Staged delivery estimate

| Stage | Scope | Estimate | Result |
|---|---|---:|---|
| **A — UI safety fix** | Create one shared image/GIF frame wrapper; keep current `width × 220` fallback; replace `cover` with `contain`; retain fullscreen. Add targeted widget tests. | **0.5–1 engineer-day** | Cropping stops immediately. Geometry remains arbitrary and no metadata work occurs. |
| **B — correct geometry contract** | Add nullable dimensions through envelope build/parse/model/local cache/pending-send/retry; extract dimensions on sender after orientation normalization; shared bounded frame; old-message fallback; tests including cached/reopened media. | **2–3 engineer-days** | Exact stable geometry for new messages; no layout jump after metadata decrypt. **Requires owner approval for envelope change.** |
| **C — polished placeholder** | Add and client-generate ThumbHash, pass it only in encrypted envelope/cache, crossfade; mobile/web package validation and visual/device QA. | **1–2 engineer-days** | Useful blurred preview while encrypted media downloads; no server metadata disclosure. **Requires owner decision to add the optional field.** |
| **D — future video** | Separate feature: video picker/upload/decrypt/poster generation/playback and platform codec QA, reusing B/C frame metadata. | **3–5 engineer-days** | Video media previews; not a crop-fix patch because video support does not exist now. |

## Owner approval items

1. Approve Stage A now, or take the full Stage B cutover instead.
2. Approve inner-envelope `mediaWidth`/`mediaHeight`, explicitly keeping them out of the server DTO/database/outer event.
3. Approve `ThumbHash` as optional encrypted preview metadata (recommended), or choose solid-colour only.
4. Confirm `contain`/letterbox at `<1:2` and `>3:1` instead of crop (recommended).
5. Confirm whether video is intentionally in next scope. Current app has none; do not smuggle it into image/GIF remediation.

## Owner decisions — approved 2026-07-09

- **Delivery:** Stages A+B+C together.
- **Contract:** add `mediaWidth`/`mediaHeight` and optional encrypted `mediaThumbHash`; no outer event, server DTO, entity, mapper, log, or database exposure.
- **Extremes:** `BoxFit.contain` with letterboxing at `<1:2` / `>3:1`; never crop source media.
- **Scope:** IMAGE and GIF only. Video is explicitly excluded because Fireplace does not currently implement it.
