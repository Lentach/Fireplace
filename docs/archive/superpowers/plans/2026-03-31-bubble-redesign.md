# Bubble Redesign: Telegram-style time overlay + media full-bleed

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace character-count heuristic layout with Telegram-style time overlay for text messages, and make GIF/image messages fill the bubble edge-to-edge with an overlay timestamp.

**Architecture:** `TextMessageContent` gains an optional `timeOverlay: Widget?` param — when set, appends a ghost `WidgetSpan` spacer and positions the time as a `Positioned` overlay in a `Stack`. `MessageContentFactory` forwards the param. `ChatMessageBubble` routes by message type: overlay for text (no link preview), full-bleed zero-padding Stack for GIF/image, unchanged Column for ping/file/text+link-preview. `GifMessageContent` and `ImageMessageContent` expand to fill bubble width at fixed 220px height.

**Tech Stack:** Flutter 3.x, Dart — no new dependencies.

---

## File Map

| File | Change |
|---|---|
| `frontend/lib/widgets/message/gif_message_content.dart` | Remove `maxWidth:200`/`ClipRRect`; full-width 220px, `BoxFit.cover` |
| `frontend/lib/widgets/message/image_message_content.dart` | Same as gif |
| `frontend/lib/widgets/message/text_message_content.dart` | Add `timeOverlay` param; ghost `WidgetSpan`; Stack overlay |
| `frontend/lib/widgets/message/message_content_factory.dart` | Add `timeOverlay` param; forward to `TextMessageContent` |
| `frontend/lib/widgets/message/chat_message_bubble.dart` | Type-based routing; media full-bleed; pass `timeOverlay` to factory |
| `frontend/test/widgets/message/bubble_redesign_test.dart` | New widget tests |

---

## Task 1: Resize GifMessageContent to full-bleed

**Files:**
- Modify: `frontend/lib/widgets/message/gif_message_content.dart`
- Test: `frontend/test/widgets/message/bubble_redesign_test.dart`

- [ ] **Step 1.1: Create test file with failing test for GIF sizing**

Create `frontend/test/widgets/message/bubble_redesign_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/providers/auth_provider.dart';
import 'package:fireplace/widgets/message/gif_message_content.dart';

MessageModel _gifMessage() => MessageModel(
      id: 1,
      content: '',
      senderId: 1,
      conversationId: 1,
      deliveryStatus: MessageDeliveryStatus.read,
      messageType: MessageType.gif,
      createdAt: DateTime(2026, 1, 1, 14, 30),
      mediaUrl: 'https://example.com/test.gif',
    );

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        body: MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
          ],
          child: child,
        ),
      ),
    );

void main() {
  group('GifMessageContent', () {
    testWidgets('renders SizedBox with height 220', (tester) async {
      await tester.pumpWidget(_wrap(GifMessageContent(message: _gifMessage())));
      // FutureBuilder not yet done — loading state
      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      // Loading placeholder should be height 220
      expect(
        sizedBoxes.any((b) => b.height == 220.0),
        isTrue,
        reason: 'Loading placeholder must use height 220',
      );
    });

    testWidgets('does not render a ConstrainedBox with maxWidth 200', (tester) async {
      await tester.pumpWidget(_wrap(GifMessageContent(message: _gifMessage())));
      final boxes = tester.widgetList<ConstrainedBox>(find.byType(ConstrainedBox));
      expect(
        boxes.any((b) => b.constraints.maxWidth == 200.0),
        isFalse,
        reason: 'GIF must not be capped at 200px',
      );
    });
  });
}
```

- [ ] **Step 1.2: Run test to confirm it fails**

```bash
cd frontend && flutter test test/widgets/message/bubble_redesign_test.dart --name "GifMessageContent"
```

Expected: FAIL — `ConstrainedBox(maxWidth: 200)` exists.

- [ ] **Step 1.3: Update `gif_message_content.dart` — loading/error placeholders**

Replace the loading `SizedBox` (line ~252–256) and error `Container` (line ~260–264):

```dart
// Loading state — replace:
// const SizedBox(width: 150, height: 150, ...)
// with:
const SizedBox(
  width: double.infinity,
  height: 220,
  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
);

// Error state — replace:
// Container(width: 150, height: 150, ...)
// with:
SizedBox(
  width: double.infinity,
  height: 220,
  child: ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: const Center(child: Icon(Icons.broken_image, size: 48)),
  ),
);
```

- [ ] **Step 1.4: Update `gif_message_content.dart` — main image widget**

In the `build()` return (bottom of the `FutureBuilder`, line ~296–306), replace the `GestureDetector` child:

```dart
return GestureDetector(
  onTap: () => _showFullscreen(context, d),
  child: SizedBox(
    width: double.infinity,
    height: 220,
    child: preview,
  ),
);
```

Also update both `Image.network` and `Image.memory` preview builders to use `BoxFit.cover` instead of `BoxFit.contain`, and remove `width`/`height` from the `Image` widgets (sizing comes from the `SizedBox`). Remove the `ConstrainedBox(maxWidth: 200)` and inner `ClipRRect(radius: 8)` wrappers — the parent bubble `Container` handles corner clipping.

Full updated `build()` return block:

```dart
Widget preview;
if (d.networkUrl != null) {
  preview = Image.network(
    d.networkUrl!,
    fit: BoxFit.cover,
    width: double.infinity,
    height: 220,
    loadingBuilder: (context, child, loadingProgress) {
      if (loadingProgress == null) return child;
      return const SizedBox(
        width: double.infinity,
        height: 220,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    },
    errorBuilder: (context, error, stackTrace) => SizedBox(
      width: double.infinity,
      height: 220,
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.broken_image, size: 48)),
      ),
    ),
  );
} else {
  preview = Image.memory(
    d.memoryBytes!,
    fit: BoxFit.cover,
    width: double.infinity,
    height: 220,
    gaplessPlayback: true,
  );
}

return GestureDetector(
  onTap: () => _showFullscreen(context, d),
  child: SizedBox(
    width: double.infinity,
    height: 220,
    child: preview,
  ),
);
```

- [ ] **Step 1.5: Run test to confirm it passes**

```bash
cd frontend && flutter test test/widgets/message/bubble_redesign_test.dart --name "GifMessageContent"
```

Expected: PASS.

- [ ] **Step 1.6: Commit**

```bash
git add frontend/lib/widgets/message/gif_message_content.dart frontend/test/widgets/message/bubble_redesign_test.dart
git commit -m "feat(ui): gif full-bleed 220px height, BoxFit.cover, no inner clip"
```

---

## Task 2: Resize ImageMessageContent to full-bleed

**Files:**
- Modify: `frontend/lib/widgets/message/image_message_content.dart`
- Modify: `frontend/test/widgets/message/bubble_redesign_test.dart`

- [ ] **Step 2.1: Add failing test for image sizing**

Append to the `main()` in `bubble_redesign_test.dart`:

```dart
group('ImageMessageContent', () {
  testWidgets('loading placeholder uses height 220', (tester) async {
    // message with mediaUrl — will trigger async load, stays in loading state
    final msg = MessageModel(
      id: 2,
      content: '',
      senderId: 1,
      conversationId: 1,
      deliveryStatus: MessageDeliveryStatus.read,
      messageType: MessageType.image,
      createdAt: DateTime(2026, 1, 1, 14, 30),
      mediaUrl: 'https://example.com/test.jpg',
    );
    await tester.pumpWidget(_wrap(ImageMessageContent(message: msg)));
    final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
    expect(
      sizedBoxes.any((b) => b.height == 220.0),
      isTrue,
      reason: 'Loading placeholder must use height 220',
    );
  });

  testWidgets('does not render ConstrainedBox with maxWidth 200', (tester) async {
    final msg = MessageModel(
      id: 2,
      content: '',
      senderId: 1,
      conversationId: 1,
      deliveryStatus: MessageDeliveryStatus.read,
      messageType: MessageType.image,
      createdAt: DateTime(2026, 1, 1, 14, 30),
      mediaUrl: 'https://example.com/test.jpg',
    );
    await tester.pumpWidget(_wrap(ImageMessageContent(message: msg)));
    final boxes = tester.widgetList<ConstrainedBox>(find.byType(ConstrainedBox));
    expect(
      boxes.any((b) => b.constraints.maxWidth == 200.0),
      isFalse,
    );
  });
});
```

- [ ] **Step 2.2: Run test to confirm it fails**

```bash
cd frontend && flutter test test/widgets/message/bubble_redesign_test.dart --name "ImageMessageContent"
```

Expected: FAIL.

- [ ] **Step 2.3: Update `image_message_content.dart`**

Replace the loading placeholder (line ~92–96):

```dart
return const SizedBox(
  width: double.infinity,
  height: 220,
  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
);
```

Replace the error state (line ~98–106):

```dart
return SizedBox(
  width: double.infinity,
  height: 220,
  child: Padding(
    padding: const EdgeInsets.all(8.0),
    child: Text(
      AppLocalizations.of(context).imageFailedToLoad,
      style: RpgTheme.bodyFont(fontSize: 12, color: Colors.red),
    ),
  ),
);
```

Replace the success `GestureDetector` return (line ~108–120):

```dart
return GestureDetector(
  onTap: () => _showFullscreen(context, bytes),
  child: SizedBox(
    width: double.infinity,
    height: 220,
    child: Image.memory(
      bytes,
      fit: BoxFit.cover,
      width: double.infinity,
      height: 220,
    ),
  ),
);
```

Remove the `ConstrainedBox(maxWidth: 200)` and inner `ClipRRect(radius: 8)` — parent bubble handles clipping.

- [ ] **Step 2.4: Run test to confirm it passes**

```bash
cd frontend && flutter test test/widgets/message/bubble_redesign_test.dart --name "ImageMessageContent"
```

Expected: PASS.

- [ ] **Step 2.5: Commit**

```bash
git add frontend/lib/widgets/message/image_message_content.dart frontend/test/widgets/message/bubble_redesign_test.dart
git commit -m "feat(ui): image full-bleed 220px height, BoxFit.cover, no inner clip"
```

---

## Task 3: Add `timeOverlay` to `TextMessageContent`

**Files:**
- Modify: `frontend/lib/widgets/message/text_message_content.dart`
- Modify: `frontend/test/widgets/message/bubble_redesign_test.dart`

- [ ] **Step 3.1: Add failing test for text overlay**

Append to `main()` in `bubble_redesign_test.dart`:

```dart
group('TextMessageContent overlay', () {
  testWidgets('renders Stack with Positioned when timeOverlay provided', (tester) async {
    final msg = MessageModel(
      id: 3,
      content: 'Hej co słychać dzisiaj u ciebie?',
      senderId: 1,
      conversationId: 1,
      deliveryStatus: MessageDeliveryStatus.read,
      messageType: MessageType.text,
      createdAt: DateTime(2026, 1, 1, 14, 30),
    );
    const overlay = SizedBox(key: Key('time-overlay'), width: 60, height: 16);
    await tester.pumpWidget(_wrap(
      TextMessageContent(
        message: msg,
        isMine: true,
        textColor: Colors.white,
        isDark: true,
        maxWidth: 250,
        timeOverlay: overlay,
      ),
    ));
    expect(find.byType(Stack), findsOneWidget);
    expect(find.byKey(const Key('time-overlay')), findsOneWidget);
    final positioned = tester.widgetList<Positioned>(find.byType(Positioned));
    expect(positioned.any((p) => p.bottom == 0 && p.right == 0), isTrue);
  });

  testWidgets('renders plain Column when timeOverlay is null', (tester) async {
    final msg = MessageModel(
      id: 4,
      content: 'Hello',
      senderId: 1,
      conversationId: 1,
      deliveryStatus: MessageDeliveryStatus.read,
      messageType: MessageType.text,
      createdAt: DateTime(2026, 1, 1, 14, 30),
    );
    await tester.pumpWidget(_wrap(
      TextMessageContent(
        message: msg,
        isMine: true,
        textColor: Colors.white,
        isDark: true,
        maxWidth: 250,
      ),
    ));
    expect(find.byType(Stack), findsNothing);
  });
});
```

- [ ] **Step 3.2: Run test to confirm it fails**

```bash
cd frontend && flutter test test/widgets/message/bubble_redesign_test.dart --name "TextMessageContent overlay"
```

Expected: FAIL — `Stack` not found.

- [ ] **Step 3.3: Update `TextMessageContent` — add `timeOverlay` param and ghost spacer**

New field and constructor in `text_message_content.dart`:

```dart
class TextMessageContent extends StatelessWidget {
  final MessageModel message;
  final bool isMine;
  final Color textColor;
  final bool isDark;
  final double maxWidth;
  final Widget? timeOverlay;   // NEW

  const TextMessageContent({
    super.key,
    required this.message,
    required this.isMine,
    required this.textColor,
    required this.isDark,
    required this.maxWidth,
    this.timeOverlay,           // NEW
  });
```

Update `_buildTextWithLinks` to accept a ghost spacer width and always return `RichText`:

```dart
Widget _buildTextWithLinks(BuildContext context, {double ghostSpacerWidth = 0}) {
  final text = message.content;
  final urlRegex = RegExp(r'https?://[^\s]+', caseSensitive: false);
  final spans = <InlineSpan>[];
  int last = 0;
  final linkColor = isMine ? textColor : Theme.of(context).colorScheme.primary;

  for (final match in urlRegex.allMatches(text)) {
    if (match.start > last) {
      spans.add(TextSpan(
        text: text.substring(last, match.start),
        style: RpgTheme.bodyFont(fontSize: 14, color: textColor),
      ));
    }
    final url = match.group(0)!;
    spans.add(TextSpan(
      text: url,
      style: RpgTheme.bodyFont(fontSize: 14, color: linkColor)
          .copyWith(decoration: TextDecoration.underline),
      recognizer: TapGestureRecognizer()
        ..onTap = () =>
            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
    ));
    last = match.end;
  }
  if (last < text.length) {
    spans.add(TextSpan(
      text: text.substring(last),
      style: RpgTheme.bodyFont(fontSize: 14, color: textColor),
    ));
  }

  // Ghost spacer: reserves room for the time overlay on the last line.
  if (ghostSpacerWidth > 0) {
    spans.add(WidgetSpan(
      child: SizedBox(width: ghostSpacerWidth, height: 1),
      alignment: PlaceholderAlignment.bottom,
    ));
  }

  return RichText(
    textAlign: isMine ? TextAlign.right : TextAlign.left,
    text: TextSpan(children: spans),
  );
}
```

Update `build()` to wire the overlay:

```dart
@override
Widget build(BuildContext context) {
  final hasOverlay = timeOverlay != null;

  final textWidget = ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxWidth),
    child: _buildTextWithLinks(
      context,
      ghostSpacerWidth: hasOverlay ? 66.0 : 0,
    ),
  );

  final content = Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment:
        isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
    children: [
      textWidget,
      if (message.linkPreviewUrl != null)
        Align(
          alignment:
              isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: _buildLinkPreviewCard(context),
        ),
    ],
  );

  if (!hasOverlay) return content;

  return Stack(
    children: [
      content,
      Positioned(
        bottom: 0,
        right: 0,
        child: timeOverlay!,
      ),
    ],
  );
}
```

- [ ] **Step 3.4: Run test to confirm it passes**

```bash
cd frontend && flutter test test/widgets/message/bubble_redesign_test.dart --name "TextMessageContent overlay"
```

Expected: PASS.

- [ ] **Step 3.5: Commit**

```bash
git add frontend/lib/widgets/message/text_message_content.dart frontend/test/widgets/message/bubble_redesign_test.dart
git commit -m "feat(ui): text bubble overlay — ghost spacer + Positioned time"
```

---

## Task 4: Forward `timeOverlay` through `MessageContentFactory`

**Files:**
- Modify: `frontend/lib/widgets/message/message_content_factory.dart`

- [ ] **Step 4.1: Update `MessageContentFactory.build` signature**

Replace the entire `build` method in `message_content_factory.dart`:

```dart
static Widget build({
  required BuildContext context,
  required MessageModel message,
  required bool isMine,
  required bool isDark,
  required Color textColor,
  required double contentAreaWidth,
  Widget? timeOverlay,             // NEW — forwarded to TextMessageContent only
}) {
  switch (message.messageType) {
    case MessageType.voice:
      return VoiceMessageContent(message: message, isMine: isMine);

    case MessageType.text:
      return TextMessageContent(
        message: message,
        isMine: isMine,
        textColor: textColor,
        isDark: isDark,
        maxWidth: contentAreaWidth,
        timeOverlay: timeOverlay,  // NEW
      );

    case MessageType.ping:
      return PingMessageContent(isMine: isMine, textColor: textColor);

    case MessageType.image:
      return ImageMessageContent(message: message);

    case MessageType.gif:
      return GifMessageContent(message: message);

    case MessageType.file:
      return FileMessageContent(
        message: message,
        textColor: textColor,
      );
  }
}
```

- [ ] **Step 4.2: Run all tests**

```bash
cd frontend && flutter test
```

Expected: all existing tests pass (no signature breakage — `timeOverlay` is optional).

- [ ] **Step 4.3: Commit**

```bash
git add frontend/lib/widgets/message/message_content_factory.dart
git commit -m "feat(ui): forward timeOverlay through MessageContentFactory"
```

---

## Task 5: Wire everything in `ChatMessageBubble`

**Files:**
- Modify: `frontend/lib/widgets/message/chat_message_bubble.dart`
- Modify: `frontend/test/widgets/message/bubble_redesign_test.dart`

- [ ] **Step 5.1: Add `timeOverlay` param to `_buildContentColumn`**

In `chat_message_bubble.dart`, update the `_buildContentColumn` method signature and body:

```dart
Widget _buildContentColumn(
  BuildContext context,
  bool isDark,
  Color textColor,
  Color borderColor, {
  required double contentAreaWidth,
  Widget? timeOverlay,          // NEW
}) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment:
        isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
    children: [
      if (message.replyTo != null) ...[
        _buildReplyQuote(context, message.replyTo!, isDark, textColor, borderColor),
        const SizedBox(height: 8),
      ],
      MessageContentFactory.build(
        context: context,
        message: message,
        isMine: isMine,
        isDark: isDark,
        textColor: textColor,
        contentAreaWidth: contentAreaWidth,
        timeOverlay: timeOverlay,  // NEW
      ),
      Builder(
        builder: (ctx) {
          final retryBtn = _buildRetryButton(ctx);
          if (retryBtn == null) return const SizedBox.shrink();
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              retryBtn,
            ],
          );
        },
      ),
    ],
  );
}
```

- [ ] **Step 5.2: Rewrite the `LayoutBuilder` body in `build()`**

Constant to add at class level (or inside `build()`):

```dart
static const double _kTimeOverlayWidth = 66.0;
static const double _kTimeRowWidth = 88.0;
```

Replace the entire `LayoutBuilder` body (from `final maxBubbleWidth = ...` through the closing `);` of the `Container`) with:

```dart
builder: (context, layoutConstraints) {
  final maxBubbleWidth = layoutConstraints.maxWidth * 0.85;
  final contentAreaWidth = maxBubbleWidth - 32;

  final isMediaMessage = message.messageType == MessageType.gif ||
      message.messageType == MessageType.image;
  final useTextOverlay = message.messageType == MessageType.text &&
      message.linkPreviewUrl == null;

  // ── Time widgets ──────────────────────────────────────────────────
  final standardTimeWidget = MessageMetadataRow(
    message: message,
    isMine: isMine,
    timeColor: timeColor,
  );

  // Semi-transparent pill overlay used on top of media.
  final mediaTimeOverlay = Positioned(
    bottom: 8,
    right: 8,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
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
  );

  // ── Content + time layout ─────────────────────────────────────────
  Widget child;

  if (isMediaMessage) {
    // Media fills bubble edge-to-edge; time is a dark pill overlay.
    child = Stack(
      children: [
        _buildContentColumn(context, isDark, textColor, borderColor,
            contentAreaWidth: contentAreaWidth),
        mediaTimeOverlay,
      ],
    );
  } else if (useTextOverlay) {
    // Text (no link preview): ghost spacer + Positioned time inside
    // TextMessageContent. No external time row needed.
    child = _buildContentColumn(
      context, isDark, textColor, borderColor,
      contentAreaWidth: contentAreaWidth,
      timeOverlay: standardTimeWidget,
    );
  } else {
    // Ping, file, text+link-preview: original Row/Column layout.
    final displayContent = _displayContent(context);
    final isShortMessage = _isShortMessage(displayContent);

    if (isShortMessage) {
      final maxContentWidthInline =
          contentAreaWidth - 6 - _kTimeRowWidth;
      child = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            fit: FlexFit.loose,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidthInline),
              child: _buildContentColumn(
                context, isDark, textColor, borderColor,
                contentAreaWidth: maxContentWidthInline,
              ),
            ),
          ),
          const SizedBox(width: 6),
          standardTimeWidget,
        ],
      );
    } else {
      child = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          _buildContentColumn(context, isDark, textColor, borderColor,
              contentAreaWidth: contentAreaWidth),
          const SizedBox(height: 4),
          Align(
            alignment:
                isMine ? Alignment.centerRight : Alignment.centerLeft,
            child: standardTimeWidget,
          ),
        ],
      );
    }
  }

  // ── Bubble Container ──────────────────────────────────────────────
  return ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxBubbleWidth),
    child: Container(
      margin: EdgeInsets.only(
        left: isMine ? 48 : 0,
        right: isMine ? 0 : 48,
        bottom: 10,
      ),
      decoration: BoxDecoration(
        color: isMediaMessage ? Colors.transparent : bubbleColor,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: isMediaMessage ? Clip.hardEdge : Clip.none,
      padding: isMediaMessage
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: child,
    ),
  );
},
```

- [ ] **Step 5.3: Add widget tests for the bubble routing**

Append to `main()` in `bubble_redesign_test.dart`. These tests require a more complete provider setup — add a helper that includes `MessagingProvider`:

```dart
// Add this import at top of test file:
// import 'package:fireplace/providers/messaging_provider.dart';

// Add helper for bubble tests (needs MessagingProvider for countdownTickNotifier):
Widget _wrapBubble(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
            ChangeNotifierProvider<MessagingProvider>(
                create: (_) => MessagingProvider()),
          ],
          child: child,
        ),
      ),
    );

group('ChatMessageBubble routing', () {
  testWidgets('GIF bubble: Container has zero padding', (tester) async {
    final msg = MessageModel(
      id: 5,
      content: '',
      senderId: 1,
      conversationId: 1,
      deliveryStatus: MessageDeliveryStatus.read,
      messageType: MessageType.gif,
      createdAt: DateTime(2026, 1, 1, 14, 30),
      mediaUrl: 'https://example.com/test.gif',
    );
    await tester.pumpWidget(_wrapBubble(
      ChatMessageBubble(message: msg, isMine: true),
    ));
    final containers = tester.widgetList<Container>(find.byType(Container));
    // The bubble Container must have zero padding for GIF
    expect(
      containers.any((c) => c.padding == EdgeInsets.zero),
      isTrue,
      reason: 'GIF bubble must have zero padding',
    );
  });

  testWidgets('text bubble (>25 chars, no link preview): renders Stack for overlay', (tester) async {
    final msg = MessageModel(
      id: 6,
      content: 'Hej, co słychać u Ciebie dzisiaj wieczorem?',
      senderId: 1,
      conversationId: 1,
      deliveryStatus: MessageDeliveryStatus.read,
      messageType: MessageType.text,
      createdAt: DateTime(2026, 1, 1, 14, 30),
    );
    await tester.pumpWidget(_wrapBubble(
      ChatMessageBubble(message: msg, isMine: true),
    ));
    // TextMessageContent with overlay renders a Stack
    expect(find.byType(Stack), findsWidgets);
  });
});
```

- [ ] **Step 5.4: Run new bubble tests**

```bash
cd frontend && flutter test test/widgets/message/bubble_redesign_test.dart --name "ChatMessageBubble"
```

Expected: PASS.

- [ ] **Step 5.5: Run full test suite**

```bash
cd frontend && flutter test
```

Expected: all tests pass.

- [ ] **Step 5.6: Run Flutter analyze**

```bash
cd frontend && flutter analyze
```

Expected: no new warnings or errors.

- [ ] **Step 5.7: Commit**

```bash
git add frontend/lib/widgets/message/chat_message_bubble.dart frontend/test/widgets/message/bubble_redesign_test.dart
git commit -m "feat(ui): telegram-style bubble redesign — text overlay + media full-bleed"
```

---

## Verification Checklist

Before calling this done:

- [ ] Text message 30 chars: time appears inline on last line, no separate row below
- [ ] Text message 3 lines: time appears bottom-right of last line, no separate row
- [ ] Text message with link preview: time appears below link card (unchanged)
- [ ] Ping: time appears inline in row (unchanged)
- [ ] GIF: fills bubble edge-to-edge, time is a dark pill at bottom-right
- [ ] Image: same as GIF
- [ ] `flutter test` passes
- [ ] `flutter analyze` no new issues
