# GIF Support — Design Spec

**Date:** 2026-03-16
**Level:** Medium privacy (Giphy API → Cloudinary upload → E2E envelope)

---

## Overview

Add GIF search and sending to Fireplace using Giphy API. GIFs are downloaded from Giphy, uploaded to Cloudinary, and the Cloudinary URL is encrypted in the E2E envelope. Server never sees the content.

## User Flow

1. User taps GIF icon in action tiles → bottom sheet opens
2. Bottom sheet shows trending GIFs in a grid + search field
3. User searches → results update with 500ms debounce (cancels in-flight requests)
4. User taps a GIF → sheet closes, optimistic message appears (SENDING)
5. App downloads GIF from Giphy (`fixed_height` format, ~1-3MB)
6. App uploads to Cloudinary via `POST /messages/upload-media` (type: `gif`)
7. Cloudinary URL placed in E2E envelope: `{ content: '', messageType: 'GIF', mediaUrl: cloudinaryUrl }`
8. Envelope encrypted → `sendMessage` emitted
9. Recipient decrypts → sees animated GIF in chat bubble

## Backend Changes

### MessageType enum (`message.entity.ts`)
Add `GIF = 'GIF'` to the enum.

### Upload media controller (`messages.controller.ts`)
Add `'gif'` branch: allow MIME type `image/gif`, use `cloudinaryService.uploadImage()` (GIF is an image format). File size limit: 5MB (same as images).

### Upload media DTO (`upload-media.dto.ts`)
Add `'gif'` to allowed `type` values.

### MessageMapper (`message.mapper.ts`)
Add GIF case in the reply-to preview ternary chain (after IMAGE check): `rt.messageType === 'GIF' ? 'GIF' : ...`

### Tests
- Add GIF case to `message.mapper.spec.ts`
- Add GIF upload test to controller tests (MIME validation)
- Add GIF to E2E encryption tests (alongside existing IMAGE/VOICE/PING tests from `cbd210c`)

## Frontend Changes

### New: `GifService` (`services/gif_service.dart`)
- `fetchTrending({int limit = 25, int offset = 0})` → calls `api.giphy.com/v1/gifs/trending`
- `search(String query, {int limit = 25, int offset = 0})` → calls `api.giphy.com/v1/gifs/search`
- Returns list of GIF objects with preview URL and full URL
- API key injected via `--dart-define=GIPHY_API_KEY=...` (like `BASE_URL`), fallback to beta key in debug mode
- Cancels previous request when new search arrives (using `CancelToken` or request abort)
- Error handling: returns empty list on API failure, picker shows "No results" state

### New: `GifPickerSheet` widget (`widgets/gif_picker_sheet.dart`)
- `showModalBottomSheet` with ~60% screen height
- Top: search `TextField` with debounce 500ms
- Body: `GridView` (2 columns) showing preview images (`fixed_height_small.url`)
- On open: loads trending GIFs
- On search: replaces grid with search results
- On tap: calls `onGifSelected(String gifUrl)` callback and closes sheet
- Pagination: load more on scroll to bottom
- Error state: "Could not load GIFs" when Giphy API unreachable
- Empty state: "No GIFs found" when search returns no results

### MessageModel (`models/message_model.dart`)
Add `gif` to `MessageType` enum. Add `'GIF'` case to `_parseMessageType()`.

### ChatActionTiles (`widgets/chat_action_tiles.dart`)
Replace `_showComingSoon` on GIF tile with opening `GifPickerSheet`.

### ChatProvider (`providers/chat_provider.dart`)
New method `sendGif(int conversationId, String gifUrl)`:
1. Create optimistic message with `messageType: MessageType.gif`, status SENDING
2. Store in `_pendingSendContent[tempId] = <String, dynamic>{'content': '', 'messageType': 'GIF'}` (prevents `[encrypted]` on history overwrite)
3. Download GIF bytes from Giphy URL — on web: use backend proxy endpoint if CORS blocks direct fetch; on native: direct `http.get`
4. Client-side size guard: reject if downloaded bytes > 5MB
5. Upload to Cloudinary via `POST /messages/upload-media` (type: `gif`, expiresIn: conversation's disappearing timer)
6. Update `_pendingSendContent[tempId]` with `mediaUrl`
7. Build E2E envelope with `mediaUrl: cloudinaryUrl`, `messageType: 'GIF'`
8. Call `_encryptAndSend()`
9. On failure: mark message as failed

### ChatMessageBubble (`widgets/chat_message_bubble.dart`)
For `MessageType.gif`:
- Display `Image.network(mediaUrl)` — Flutter handles animated GIF natively
- Rounded corners matching bubble style
- Tap to expand in dialog (for small GIFs that are hard to see at bubble width)
- Loading placeholder while image loads

### E2eEnvelope parsing
Add `'GIF'` to known messageType values in `E2eEnvelope.parse()`.

### L10n (`l10n/app_pl.arb`, `l10n/app_en.arb`)
- Existing `actionTileGif` string already present
- Conversation list: encrypted GIFs show "Encrypted message" (same as all encrypted messages — no special handling needed)

### Tests
- Frontend unit tests for GifService (mock HTTP)
- Verify E2E envelope round-trip with GIF type

## Giphy API Details

- **Trending:** `GET api.giphy.com/v1/gifs/trending?api_key=KEY&limit=25&offset=0&rating=pg-13`
- **Search:** `GET api.giphy.com/v1/gifs/search?api_key=KEY&q=QUERY&limit=25&offset=0&rating=pg-13`
- **API key:** Beta key for development, production key injected via `--dart-define=GIPHY_API_KEY=...` (never hardcoded in committed code)
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

## CLAUDE.md Updates After Implementation

- Database schema: add GIF to MessageType enum
- Section 1 E2E Encryption: add GIF to "All message types encrypted" list
- Section 8 E2E Envelope: add GIF to envelope description
- Section 3 File Location Map: add gif_service.dart, gif_picker_sheet.dart
- Section 10 Environment & Config: add GIPHY_API_KEY
- Tests count update

## Out of Scope

- Privacy proxy for Giphy requests (Signal-level)
- GIF → MP4 conversion
- Stickers
- GIF favorites/recents
