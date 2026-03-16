# GIF Support — Design Spec

**Date:** 2026-03-16
**Level:** Medium privacy (Giphy API → Cloudinary upload → E2E envelope)

---

## Overview

Add GIF search and sending to Fireplace using Giphy API. GIFs are downloaded from Giphy, uploaded to Cloudinary, and the Cloudinary URL is encrypted in the E2E envelope. Server never sees the content.

## User Flow

1. User taps GIF icon in action tiles → bottom sheet opens
2. Bottom sheet shows trending GIFs in a grid + search field
3. User searches → results update with 500ms debounce
4. User taps a GIF → sheet closes, optimistic message appears (SENDING)
5. App downloads GIF from Giphy (`fixed_height` format, ~1-3MB)
6. App uploads to Cloudinary via `POST /messages/upload-media` (type: `gif`)
7. Cloudinary URL placed in E2E envelope: `{ content: '', messageType: 'GIF', mediaUrl: cloudinaryUrl }`
8. Envelope encrypted → `sendMessage` emitted
9. Recipient decrypts → sees animated GIF in chat bubble

## Backend Changes

### MessageType enum (`message.entity.ts`)
Add `GIF = 'GIF'` to the enum.

### Upload media DTO (`upload-media.dto.ts`)
Add `'gif'` to allowed `type` values.

### MessageMapper (`message.mapper.ts`)
Add GIF case in reply-to preview text → `"GIF"`.

### Tests
Add GIF case to `message.mapper.spec.ts`.

## Frontend Changes

### New: `GifService` (`services/gif_service.dart`)
- `fetchTrending({int limit = 25, int offset = 0})` → calls `api.giphy.com/v1/gifs/trending`
- `search(String query, {int limit = 25, int offset = 0})` → calls `api.giphy.com/v1/gifs/search`
- Returns list of GIF objects with preview URL and full URL
- API key stored in `app_config.dart`

### New: `GifPickerSheet` widget (`widgets/gif_picker_sheet.dart`)
- `showModalBottomSheet` with ~60% screen height
- Top: search `TextField` with debounce 500ms
- Body: `GridView` (2 columns) showing preview images (`fixed_height_small.url`)
- On open: loads trending GIFs
- On search: replaces grid with search results
- On tap: calls `onGifSelected(String gifUrl)` callback and closes sheet
- Pagination: load more on scroll to bottom

### MessageModel (`models/message_model.dart`)
Add `GIF` to `MessageDeliveryStatus` enum (the messageType field).

### ChatActionTiles (`widgets/chat_action_tiles.dart`)
Replace `_showComingSoon` on GIF tile with opening `GifPickerSheet`.

### ChatProvider (`providers/chat_provider.dart`)
New method `sendGif(int conversationId, String gifUrl)`:
1. Create optimistic message with `messageType: MessageType.GIF`, status SENDING
2. Download GIF bytes from Giphy URL (`http.get`)
3. Upload to Cloudinary via `POST /messages/upload-media` (type: `gif`)
4. Build E2E envelope with `mediaUrl: cloudinaryUrl`, `messageType: 'GIF'`
5. Call `_encryptAndSend()`
6. On failure: mark message as failed

### ChatMessageBubble (`widgets/chat_message_bubble.dart`)
For `MessageType.GIF`:
- Display `Image.network(mediaUrl)` — Flutter handles animated GIF natively
- Rounded corners matching bubble style
- No tap-to-fullscreen (unlike IMAGE)
- Loading placeholder while image loads

### E2eEnvelope parsing
Add `'GIF'` to known messageType values in `E2eEnvelope.parse()`.

### L10n (`l10n/app_pl.arb`, `l10n/app_en.arb`)
- Existing `actionTileGif` string already present
- Add: conversation list preview text for GIF messages

### Tests
- Frontend unit tests for GifService (mock HTTP)
- Verify E2E envelope round-trip with GIF type

## Giphy API Details

- **Trending:** `GET api.giphy.com/v1/gifs/trending?api_key=KEY&limit=25&offset=0&rating=pg-13`
- **Search:** `GET api.giphy.com/v1/gifs/search?api_key=KEY&q=QUERY&limit=25&offset=0&rating=pg-13`
- **API key:** Beta key for development (`dc6zaTOxFJmzC`), production key via Giphy developer portal
- **Preview images (picker grid):** `images.fixed_height_small.url` (100px height, fast load)
- **Full image (to send):** `images.fixed_height.url` (200px height, good quality, max ~3MB)
- **Rating:** `pg-13` default (no explicit content)

## Privacy Model

| Who | Sees what |
|---|---|
| Giphy | User IP + search query (no proxy) |
| Cloudinary | Uploaded GIF file (unencrypted, same as current images) |
| Fireplace server | `[encrypted]` — blind to content, URL, and type |
| Recipient | Decrypted GIF from Cloudinary URL |

Same privacy level as current IMAGE messages. Giphy additionally sees search queries — documented trade-off for medium privacy level.

## Out of Scope

- Privacy proxy for Giphy requests (Signal-level)
- GIF → MP4 conversion
- Stickers
- GIF favorites/recents
