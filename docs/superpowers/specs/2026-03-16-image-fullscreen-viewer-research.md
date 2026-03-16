# Image / media full-screen viewer — research (popular messengers)

**Date:** 2026-03-16  
**Purpose:** Deep research how WhatsApp, Telegram, Facebook Messenger, Slack, and Discord handle tap-to-enlarge for images/documents in chat; use findings to design Fireplace’s image preview feature.

---

## 1. WhatsApp

### Trigger
- **Tap on a photo** in the chat → image opens in a **full-screen media viewer**.

### Media viewer behavior
- Full-screen display: image takes up the whole screen.
- **Reply**: Reply button at the bottom opens keyboard for in-line reply.
- **Reactions**: Emoji reaction icon; quick access to frequently used emojis; reactions show on the photo (e.g. left of the reaction icon).
- **Quality**: On iOS, full-quality viewing is supported; standard sent photos are compressed; sending as “document” preserves quality but removes thumbnail preview in chat.

### Summary
- Single tap on thumbnail → dedicated full-screen viewer.
- Viewer is a separate screen/activity with overlay controls (reply, react), not just a zoomed image.
- Source: [Stack Overflow – WhatsApp-style expand](https://stackoverflow.com/questions/47611290/how-can-i-click-a-picture-and-make-it-expand-to-full-screen-like-in-whatsapp-mes), [WhatsApp Help – view once media](https://faq.whatsapp.com/578442220724722/), [Android Police – media viewer UI](https://androidpolice.com/whatsapp-beta-message-reactions-media-viewer).

---

## 2. Telegram

### Trigger
- **Tap on a photo or video** in the chat → opens in a **media viewer**.

### Media viewer behavior (Desktop)
- **Default**: Full-screen mode (fills entire screen).
- **Windowed mode**: If the main Telegram window is not maximized, media can open in a windowed viewer instead of true full-screen.
- **Maximize/restore**: Media viewer has a button to toggle full-screen vs windowed; preference can be remembered (OS-dependent, especially on Linux).
- Users have requested an option to “fill the Telegram window” instead of the whole screen.

### Summary
- Tap → dedicated media viewer (full-screen or windowed).
- Same pattern as WhatsApp: separate viewer screen/window, not inline zoom.
- Source: [Telegram FAQ](https://telegram.org/faq), [GitHub tdesktop #27388, #10075, #6069](https://github.com/telegramdesktop/tdesktop/issues) (windowed/fullscreen options).

---

## 3. Facebook Messenger

### Trigger
- **Tap on the image** in the conversation → image opens in **full-size view**.

### Behavior
- In chat, images can appear zoomed/cropped or compressed (especially on mobile).
- Tapping shows the **full-size version** (full-screen style view).
- On desktop (messenger.com), images may appear less cropped in the bubble than on mobile; tap still opens full-size.

### Summary
- Same pattern: tap thumbnail → full-screen/full-size viewer.
- Source: [Facebook Help – view photo full-screen](https://en-gb.facebook.com/help/408535062494209/), [CCM forum – image appear fully in Messenger](https://ccm.net/forum/affich-1118412-how-to-make-image-appear-fully-in-messenger).

---

## 4. Slack

### Trigger
- **Click on an image** in the channel → image **expands to full size** in place or in a viewer.

### Behavior
- Preview thumbnails are **cropped** (not scaled); click shows the **full original image**.
- Commands `/expand` and `/collapse` control whether link/image previews are shown expanded or collapsed by default across the conversation.

### Summary
- Click thumbnail → full-size view (expand).
- Optional global expand/collapse of previews.
- Source: [Slack unfurling docs](https://docs.slack.dev/messaging/unfurling-links-in-messages), [Super User – Slack image thumbnails](https://superuser.com/questions/1708147/thumbnails-of-posted-images-are-cropped-but-not-scaled-in-slack).

---

## 5. Discord

### Behavior
- Link previews (e.g. Open Graph) show title, description, image, URL.
- **Click on an image or link preview** → expands to show more detail.
- No built-in `/expand`/`collapse` like Slack; users have requested similar control.

### Summary
- Click → expanded/full view of image or preview.
- Source: [Discord support – collapse/expand](https://support.discord.com/hc/en-us/community/posts/360030124131-Collapse-images-website-info-and-other-expandos).

---

## 6. Common UX patterns (zoom/pan)

From generic chat/image-viewer UX and libraries:

- **Pinch zoom**: Pinch to zoom in/out, center on pinch point; often with “rubber band” at limits.
- **Pan**: When zoomed, drag to move around the image; momentum and boundary bounce.
- **Double-tap**: Toggle zoom level (e.g. fit vs 100% or 2x).
- **Toolbar (optional)**: Zoom in/out, reset, fit-to-view; sometimes zoom percentage overlay.
- **Gallery swipe**: In viewers that show “all media in chat”, swipe left/right to move between photos (e.g. Stream Chat Android).

Sources: [react-zoom-pan-pinch](https://www.npmjs.com/package/react-zoom-pan-pinch), [React Native Gesture Image Viewer](https://react-native-gesture-image-viewer.pages.dev/), [Stream Chat Android PR #3335](https://github.com/GetStream/stream-chat-android/pull/3335).

---

## 7. Implementation approaches (from research)

### Android (Stack Overflow – “like WhatsApp”)
- **Option A**: Full-screen **Dialog** with `FLAG_FULLSCREEN`, `MATCH_PARENT` layout — works but “not as slick” as a true transition.
- **Option B**: Dedicated **Activity** for the full-screen image + **transition animation** from list item to full screen (shared element / hero).
- **Option C**: **PhotoView**-style library for pinch-zoom on the enlarged image (e.g. PhotoViewAttacher).

### Flutter relevance for Fireplace
- **New route/screen**: e.g. `ImagePreviewScreen(imageUrl)` opened with `Navigator.push` — matches “dedicated viewer” pattern of WhatsApp/Telegram/Messenger.
- **Hero**: Use `Hero(tag: 'image_${message.id}')` on thumbnail and on full-screen image for shared-element transition.
- **Zoom/pan**: `InteractiveViewer` (built-in) or package `photo_view` for pinch-zoom and pan in the viewer.
- **Callback**: `ChatMessageBubble` gets `onImageTap(String url)` (and optionally `messageId` for Hero); `ChatDetailScreen` performs navigation.

---

## 8. Recommendations for Fireplace

| Aspect | Recommendation |
|--------|----------------|
| **Trigger** | Single tap on image (and later document) in the message bubble. |
| **Viewer type** | Dedicated full-screen screen (new route), not inline expand — consistent with WhatsApp, Telegram, Messenger. |
| **Minimum** | Full-screen image with close/back; image fits screen (e.g. `BoxFit.contain`). |
| **Enhancement** | Pinch-zoom and pan via `InteractiveViewer` or `photo_view`. |
| **Optional** | Hero animation from bubble to viewer. |
| **Later** | Reply/reaction from viewer (like WhatsApp); gallery swipe between images in conversation. |
| **Documents** | Same gesture: tap attachment → open in viewer; for non-image files, open in browser or system viewer. |

---

## 9. Sources (URLs)

- Telegram FAQ: https://telegram.org/faq  
- Telegram Desktop issues (media viewer fullscreen/windowed): https://github.com/telegramdesktop/tdesktop/issues/27388, /10075, /6069  
- WhatsApp: tap photo → full screen: https://stackoverflow.com/questions/47611290/how-can-i-click-a-picture-and-make-it-expand-to-full-screen-like-in-whatsapp-mes  
- WhatsApp media viewer UI (reactions, reply): https://androidpolice.com/whatsapp-beta-message-reactions-media-viewer  
- WhatsApp view once / open media: https://faq.whatsapp.com/578442220724722/  
- Facebook Help – view photo full-screen: https://en-gb.facebook.com/help/408535062494209/  
- CCM – make image appear fully in Messenger: https://ccm.net/forum/affich-1118412-how-to-make-image-appear-fully-in-messenger  
- Slack: click image to expand; /expand, /collapse: Slack docs + Super User (cropped thumbnails).  
- Discord: expand/collapse previews: https://support.discord.com/hc/en-us/community/posts/360030124131  
- Zoom/pan UX: react-zoom-pan-pinch, React Native Gesture Image Viewer, Stream Chat Android PR #3335  
