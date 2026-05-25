# Bubble Redesign: Telegram-style time overlay + media full-bleed

**Date:** 2026-03-31
**Status:** Approved

---

## Problem

1. **Text messages (26–80 chars):** time renders in a separate row below text. Last line of text has large empty space on one side. Cause: `_isShortMessage` threshold of 25 chars switches to Column layout.

2. **GIF / Image messages:** media is small (`maxWidth: 200`, `BoxFit.contain`) and floats inside a padded bubble — bubble background color is visible around the media. Time is in a separate row below.

---

## Solution

### Part A — Text overlay (ghost spacer technique)

For `MessageType.text` without `linkPreviewUrl`:

- Remove short/long branching (`_isShortMessage` no longer used for text).
- `TextMessageContent` receives an optional `timeOverlay: Widget?` parameter.
- When `timeOverlay != null`: append a `WidgetSpan(SizedBox(width: 66, height: 1), alignment: PlaceholderAlignment.bottom)` ghost spacer at the end of all text spans. Wrap the resulting `RichText` in a `Stack` with `Positioned(bottom: 0, right: 0, child: timeOverlay)`.
- `chat_message_bubble.dart` passes `MessageMetadataRow(message, isMine, timeColor)` as `timeOverlay` and omits the external time row from the Column.
- `MessageContentFactory.build()` gets a new optional `timeOverlay: Widget?` parameter — forwarded only to `TextMessageContent`, ignored by all other types.

**Text WITH `linkPreviewUrl`:** keep current Column layout (time below link preview card). Overlay would place time between text and card — wrong position.

**Ping:** keep current Row inline layout (unchanged, `_isShortMessage` still returns `true` for ping).

**Ghost spacer width:** `const double _kTimeOverlayWidth = 66.0` — covers time text (~28px) + space (4px) + delivery icon (12px) + buffer (22px). Declared in `chat_message_bubble.dart`.

### Part B — Media full-bleed (GIF + Image)

For `MessageType.gif` and `MessageType.image`, the bubble Container changes:

| Property | Before | After |
|---|---|---|
| `padding` | `EdgeInsets.fromLTRB(16, 10, 16, 8)` | `EdgeInsets.zero` |
| `color` | `bubbleColor` | `Colors.transparent` |
| `clipBehavior` | not set | `Clip.hardEdge` |
| time row | Column, external row below | `Positioned(bottom: 8, right: 8)` overlay |

The content widget (`GifMessageContent` / `ImageMessageContent`) changes:

- Remove inner `ConstrainedBox(maxWidth: 200)` and `ClipRRect(radius: 8)` — parent bubble clips corners.
- Size: `SizedBox(width: double.infinity, height: 220)` — fixed height, fills bubble width.
- `BoxFit.cover` — fills without letterboxing. Fullscreen tap still shows unclipped.
- Loading/error placeholders use same `220` height for consistent layout.

Time overlay for media (built in `chat_message_bubble.dart`):

```dart
Positioned(
  bottom: 8,
  right: 8,
  child: Container(
    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(10),
    ),
    child: MessageMetadataRow(
      message: message,
      isMine: isMine,
      timeColor: Colors.white.withValues(alpha: 0.9),
    ),
  ),
)
```

---

## Files Changed

| File | Change |
|---|---|
| `chat_message_bubble.dart` | Remove text short/long branching; build media bubble with zero padding + overlay; pass `timeOverlay` to factory |
| `message_content_factory.dart` | Add optional `timeOverlay: Widget?` param, forward to `TextMessageContent` |
| `text_message_content.dart` | Add optional `timeOverlay: Widget?` param; ghost spacer + Stack overlay when set |
| `gif_message_content.dart` | Remove `maxWidth: 200`, `ClipRRect`; use `SizedBox(h:220)`, `BoxFit.cover` |
| `image_message_content.dart` | Same changes as `gif_message_content.dart` |

---

## Out of Scope

- Voice, File, Ping message layout — no changes.
- Reply quote layout — overlay still applies to the text portion below the quote (correct behavior).
- Link preview messages — Column layout with time below (unchanged).
- Backend / models — no changes.

---

## Edge Cases

| Case | Behavior |
|---|---|
| Text + reply quote, no link preview | Overlay on text portion; reply quote above — correct |
| Text + link preview | Column, time below link card — unchanged |
| Very short text (1–5 chars) | Ghost spacer widens last line to 66px; bubble widens slightly — acceptable |
| GIF loading state | Placeholder `SizedBox(h:220)` with spinner — same height as loaded |
| GIF error state | Placeholder `SizedBox(h:220)` with broken image icon |
| Timer text in metadata | May slightly overlap ghost spacer for very long timer strings — rare, acceptable |
