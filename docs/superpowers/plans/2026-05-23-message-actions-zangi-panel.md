# Message Actions Zangi Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace swipe-to-delete and bottom-sheet reactions with a Zangi-style long-press overlay (emoji row + Reply/Edit/Pin/Delete), delete confirmation dialog, one pinned message per conversation with banner + scroll, and reply context on all send types including E2E-aware composer preview.

**Architecture:** Phase 1a refactors `MessageSwipeWrapper` to reply-only left swipe and introduces `OverlayEntry`-based `MessageContextMenuOverlay` (pattern from `top_snackbar.dart`). Phase 1b adds `conversations.pinnedMessageId` + WS `pinMessage`/`unpinMessage` with `pinnedMessage` snapshot in `ConversationMapper`. A **scroll-to-pinned spike** gates 1b banner shipping (`ListView.reverse: true` + pagination; caller-owned `GlobalKey` + `ensureVisible`). Phase 1c extracts **required** `reply_preview_helper.dart`, threads `replyToMessageId` through media sends, and enriches incoming quote previews from local decrypt cache. Edit stays a **greyed but tappable** stub (`messageEditComingSoon` snackbar) until Phase 2 (separate spec).

**Tech stack:** Flutter 3.x (Provider, OverlayEntry, `Scrollable.ensureVisible`), NestJS 11 + TypeORM + Socket.IO 4, PostgreSQL 16, ARB l10n (`app_en.arb` / `app_pl.arb`).

**Spec:** `docs/superpowers/specs/2026-05-23-message-actions-zangi-panel-design.md`

**Version bump:** On the final production-worthy commit for this feature set, increment PATCH in `frontend/pubspec.yaml` (`0.0.2` → `0.0.3` per `.cursor/rules/version-bump.mdc`) and mention `0.0.3` in the commit message.

---

## File structure

### Frontend — create

| File | Responsibility |
|------|----------------|
| `frontend/lib/widgets/message/message_context_menu_overlay.dart` | `openMessageContextMenu()`, scrim, emoji row, panel host, positioning |
| `frontend/lib/widgets/message/message_action_panel.dart` | Reply / Edit / Pin / Delete rows |
| `frontend/lib/widgets/dialogs/message_delete_dialog.dart` | Delete for me / for everyone / Cancel |
| `frontend/lib/widgets/message/pinned_message_banner.dart` | Banner under AppBar (Phase 1b) |
| `frontend/lib/utils/reply_preview_helper.dart` | Shared reply preview text — **required** (Phase 1c) |
| `frontend/lib/utils/scroll_to_message_helper.dart` | Reverse-list index math + pagination loop only (spike → 1b; no GlobalKey) |
| `frontend/test/widgets/message/message_swipe_wrapper_test.dart` | Swipe-only-reply tests |
| `frontend/test/widgets/message/message_context_menu_overlay_test.dart` | Overlay actions visible |
| `frontend/test/widgets/dialogs/message_delete_dialog_test.dart` | for_everyone visibility |
| `frontend/test/widgets/message/pinned_message_banner_test.dart` | Tap callback (1b) |
| `frontend/test/utils/scroll_to_message_helper_test.dart` | Index math unit tests |
| `frontend/test/providers/messaging_provider_reply_media_test.dart` | Media + replyToMessageId (1c) |
| `frontend/test/providers/messaging_provider_reply_quote_enrichment_test.dart` | Incoming quote enrichment from decrypt cache (1c #5) |
| `frontend/test/widgets/input/reply_preview_bar_test.dart` | E2E preview l10n (1c) |

### Frontend — modify

| File | Changes |
|------|---------|
| `frontend/lib/widgets/message_swipe_wrapper.dart` | Remove delete; clamp `dx ≤ 0` |
| `frontend/lib/widgets/message/chat_message_bubble.dart` | Overlay entry; remove bottom sheet + swipe delete |
| `frontend/lib/widgets/message/voice_message_content.dart` | Same wiring as bubble |
| `frontend/lib/screens/chat_detail_screen.dart` | Scroll helper; pinned banner; overlay dismiss on scroll |
| `frontend/lib/providers/messaging_provider.dart` | pin/unpin; media reply; delete pin local state; quote enrichment (1c #5) |
| `frontend/lib/providers/conversations_provider.dart` | Pin fields on list payloads |
| `frontend/lib/providers/connection_provider.dart` | `messagePinned` / `messageUnpinned` listeners |
| `frontend/lib/services/socket_service.dart` | `pinMessage` / `unpinMessage` emit helpers (optional) |
| `frontend/lib/models/conversation_model.dart` | `pinnedMessageId`, `pinnedMessagePreview` |
| `frontend/lib/widgets/input/reply_preview_bar.dart` | l10n + helper (1c) |
| `frontend/lib/l10n/app_en.arb`, `app_pl.arb` | New strings |
| `CLAUDE.md` | UX, pin model, delete table |

### Backend — create / modify

| File | Changes |
|------|---------|
| `backend/src/chat/dto/pin-message.dto.ts` | `PinMessageDto`, `UnpinMessageDto` |
| `backend/src/conversations/conversation.entity.ts` | `pinnedMessageId`, `pinnedAt`, `pinnedByUserId` |
| `backend/src/conversations/conversations.service.ts` | `setPinnedMessage`, `clearPinnedMessage`, lazy stale clear |
| `backend/src/chat/services/chat-conversation.service.ts` | `handlePinMessage`, `handleUnpinMessage` |
| `backend/src/chat/chat.gateway.ts` | `@SubscribeMessage('pinMessage'/'unpinMessage')` |
| `backend/src/messages/messages.service.ts` | `getPinnedMessagesBatch` for conversation list snapshots |
| `backend/src/chat/mappers/conversation.mapper.ts` | Pin fields + `pinnedMessage` snapshot |
| `backend/src/chat/services/chat-message.service.ts` | Clear pin on `for_everyone` delete |
| `backend/src/chat/services/chat-conversation.service.spec.ts` | Pin replace, auth |
| `backend/src/chat/services/chat-message.service.spec.ts` | Delete-for-everyone clears pin |

---

## Phase 1a — Swipe + overlay + delete dialog

### Task 1: Refactor `MessageSwipeWrapper` (reply-only swipe)

**Files:**
- Modify: `frontend/lib/widgets/message_swipe_wrapper.dart`
- Create: `frontend/test/widgets/message/message_swipe_wrapper_test.dart`

- [ ] **Step 1: Write failing swipe tests**

```dart
import 'package:fireplace/widgets/message_swipe_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('swipe left triggers onSwipeReply', (tester) async {
    var replyCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageSwipeWrapper(
            isMine: true,
            onSwipeReply: () => replyCount++,
            onLongPress: () {},
            child: const SizedBox(width: 200, height: 40),
          ),
        ),
      ),
    );
    await tester.drag(find.byType(MessageSwipeWrapper), const Offset(-80, 0));
    await tester.pumpAndSettle();
    expect(replyCount, 1);
  });

  testWidgets('swipe right does not call delete (no callback exists)', (tester) async {
    var replyCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageSwipeWrapper(
            isMine: true,
            onSwipeReply: () => replyCount++,
            onLongPress: () {},
            child: const SizedBox(width: 200, height: 40),
          ),
        ),
      ),
    );
    await tester.drag(find.byType(MessageSwipeWrapper), const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(replyCount, 0);
  });
}
```

- [ ] **Step 2: Run tests — expect compile failure**

Run: `cd frontend && flutter test test/widgets/message/message_swipe_wrapper_test.dart`  
Expected: FAIL — `onSwipeDelete` required / tests reference removed API

- [ ] **Step 3: Implement wrapper changes**

In `message_swipe_wrapper.dart`:

1. Remove `onSwipeDelete` parameter and all delete-zone UI (left red delete `AnimatedContainer`, delete background).
2. In `_onDragUpdate`, clamp offset to left only:

```dart
_dragOffset += details.delta.dx;
_dragOffset = _dragOffset.clamp(-_iconRevealPx * 1.5, 0.0);
```

3. In `_onDragEnd`, remove `else if (_dragOffset >= _thresholdPx)` branch; keep only:

```dart
if (_dragOffset <= -_thresholdPx) {
  widget.onSwipeReply();
}
setState(() => _dragOffset = 0);
```

4. Update class doc comment: swipe left = reply only; swipe right = no action.

- [ ] **Step 4: Run tests**

Run: `cd frontend && flutter test test/widgets/message/message_swipe_wrapper_test.dart`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/widgets/message_swipe_wrapper.dart frontend/test/widgets/message/message_swipe_wrapper_test.dart
git commit -m "refactor: message swipe reply-only, clamp right drag"
```

---

### Task 2: l10n keys for panel, dialog, edit stub

**Files:**
- Modify: `frontend/lib/l10n/app_en.arb`
- Modify: `frontend/lib/l10n/app_pl.arb`

- [ ] **Step 1: Add English keys** (`app_en.arb`)

```json
"messageActionReply": "Reply",
"messageActionEdit": "Edit",
"messageActionPin": "Pin",
"messageActionDelete": "Delete",
"messageDeleteDialogTitle": "Delete message?",
"messageDeleteForMe": "Delete for me",
"messageDeleteForEveryone": "Delete for everyone",
"messageEditComingSoon": "Edit is coming soon",
"messagePinRequiresSentMessage": "Wait until the message is sent before pinning",
"messageDeleteRequiresSentMessage": "Wait until the message is sent before deleting for everyone",
"snackbarPinnedMessageUnavailable": "Message is no longer available",
"pinnedMessageUnpinTooltip": "Unpin",
"pinnedMessageBannerSemantics": "Pinned message"
```

- [ ] **Step 2: Add Polish equivalents** (`app_pl.arb`)

```json
"messageActionReply": "Odpowiedz",
"messageActionEdit": "Edytuj",
"messageActionPin": "Przypnij",
"messageActionDelete": "Usuń",
"messageDeleteDialogTitle": "Usunąć wiadomość?",
"messageDeleteForMe": "Usuń u mnie",
"messageDeleteForEveryone": "Usuń dla wszystkich",
"messageEditComingSoon": "Edycja wkrótce",
"messagePinRequiresSentMessage": "Poczekaj na wysłanie wiadomości, aby ją przypiąć",
"messageDeleteRequiresSentMessage": "Poczekaj na wysłanie wiadomości, aby usunąć dla wszystkich",
"snackbarPinnedMessageUnavailable": "Wiadomość jest niedostępna",
"pinnedMessageUnpinTooltip": "Odepnij",
"pinnedMessageBannerSemantics": "Przypięta wiadomość"
```

- [ ] **Step 3: Regenerate l10n**

Run: `cd frontend && flutter gen-l10n`  
Expected: exit 0; `app_localizations.dart` updated

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/l10n/app_en.arb frontend/lib/l10n/app_pl.arb frontend/lib/l10n/
git commit -m "l10n: message action panel and delete dialog strings"
```

---

### Task 3: `MessageActionPanel` widget

**Files:**
- Create: `frontend/lib/widgets/message/message_action_panel.dart`

- [ ] **Step 1: Create panel**

```dart
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rpg_theme.dart';

class MessageActionPanel extends StatelessWidget {
  const MessageActionPanel({
    super.key,
    required this.isMine,
    required this.canPinOrDeleteForEveryone,
    required this.onReply,
    required this.onEdit,
    required this.onPin,
    required this.onDelete,
  });

  final bool isMine;
  final bool canPinOrDeleteForEveryone;
  final VoidCallback onReply;
  final VoidCallback onEdit;
  final VoidCallback onPin;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final fc = FireplaceColors.of(context);
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      color: fc.surface,
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _row(context, l10n.messageActionReply, Icons.reply, onReply, enabled: true),
            _row(
              context,
              l10n.messageActionEdit,
              Icons.edit_outlined,
              onEdit,
              enabled: true,
              muted: true,
            ),
            _row(
              context,
              l10n.messageActionPin,
              Icons.push_pin_outlined,
              onPin,
              enabled: canPinOrDeleteForEveryone,
            ),
            _row(
              context,
              l10n.messageActionDelete,
              Icons.delete_outline,
              onDelete,
              enabled: true,
              destructive: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback onTap, {
    required bool enabled,
    bool destructive = false,
    bool muted = false,
  }) {
    final color = muted
        ? Theme.of(context).disabledColor
        : !enabled
            ? Theme.of(context).disabledColor
            : destructive
                ? Colors.red.shade700
                : Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Text(label, style: RpgTheme.bodyFont(fontSize: 14, color: color)),
          ],
        ),
      ),
    );
  }
}
```

Edit row uses `muted: true` with `enabled: true` so it is **visually greyed but always tappable**. The overlay wires `onEdit` to `showTopSnackBar(..., l10n.messageEditComingSoon)` — do **not** use `enabled: false` / `onTap: null` for Edit.

- [ ] **Step 2: Analyze**

Run: `cd frontend && flutter analyze lib/widgets/message/message_action_panel.dart`  
Expected: no issues

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/widgets/message/message_action_panel.dart
git commit -m "feat: message action panel widget for context menu"
```

---

### Task 4: `MessageDeleteDialog` + widget test

**Files:**
- Create: `frontend/lib/widgets/dialogs/message_delete_dialog.dart`
- Create: `frontend/test/widgets/dialogs/message_delete_dialog_test.dart`

- [ ] **Step 1: Write failing test**

```dart
import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/widgets/dialogs/message_delete_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap({required bool isMine, required int messageId}) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (ctx) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showMessageDeleteDialog(
              context: ctx,
              isMine: isMine,
              messageId: messageId,
              onDeleteForMe: () {},
              onDeleteForEveryone: () {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
  }

  testWidgets('other user message hides delete for everyone', (tester) async {
    await tester.pumpWidget(wrap(isMine: false, messageId: 42));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Delete for me'), findsOneWidget);
    expect(find.text('Delete for everyone'), findsNothing);
  });

  testWidgets('own persisted message shows both options', (tester) async {
    await tester.pumpWidget(wrap(isMine: true, messageId: 42));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Delete for me'), findsOneWidget);
    expect(find.text('Delete for everyone'), findsOneWidget);
  });

  testWidgets('own optimistic temp id hides delete for everyone', (tester) async {
    await tester.pumpWidget(wrap(isMine: true, messageId: -1));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Delete for everyone'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test — expect fail**

Run: `cd frontend && flutter test test/widgets/dialogs/message_delete_dialog_test.dart`  
Expected: FAIL — `showMessageDeleteDialog` not defined

- [ ] **Step 3: Implement dialog**

`message_delete_dialog.dart`:

```dart
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

Future<void> showMessageDeleteDialog({
  required BuildContext context,
  required bool isMine,
  required int messageId,
  required VoidCallback onDeleteForMe,
  required VoidCallback onDeleteForEveryone,
}) {
  final l10n = AppLocalizations.of(context)!;
  final showForEveryone = isMine && messageId > 0;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.messageDeleteDialogTitle),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(ctx);
            onDeleteForMe();
          },
          child: Text(l10n.messageDeleteForMe),
        ),
        if (showForEveryone)
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDeleteForEveryone();
            },
            child: Text(
              l10n.messageDeleteForEveryone,
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
        ),
      ],
    ),
  );
}
```

- [ ] **Step 4: Run test**

Run: `cd frontend && flutter test test/widgets/dialogs/message_delete_dialog_test.dart`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/widgets/dialogs/message_delete_dialog.dart frontend/test/widgets/dialogs/message_delete_dialog_test.dart
git commit -m "feat: message delete confirmation dialog with ownership rules"
```

---

### Task 5: `openMessageContextMenu` + `MessageContextMenuOverlay`

**Files:**
- Create: `frontend/lib/widgets/message/message_context_menu_overlay.dart`
- Create: `frontend/test/widgets/message/message_context_menu_overlay_test.dart`

- [ ] **Step 1: Write failing overlay test**

```dart
import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/widgets/message/message_context_menu_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MessageModel _msg({required int id, required int senderId}) => MessageModel(
      id: id,
      content: 'hello',
      senderId: senderId,
      senderUsername: 'alice',
      conversationId: 1,
      createdAt: DateTime(2026, 5, 23),
      deliveryStatus: MessageDeliveryStatus.sent,
      messageType: MessageType.text,
    );

void main() {
  testWidgets('long-press entry shows four action labels', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: GestureDetector(
                onLongPress: () {
                  final box = ctx.findRenderObject() as RenderBox;
                  openMessageContextMenu(
                    context: ctx,
                    message: _msg(id: 10, senderId: 1),
                    bubbleRenderBox: box,
                    isMine: true,
                    currentUserId: 1,
                    onReply: () {},
                    onPin: () {},
                    onDelete: () {},
                    onReaction: (_, __) {},
                  );
                },
                child: const Text('bubble'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.longPress(find.text('bubble'));
    await tester.pumpAndSettle();
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Pin'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test — expect fail**

Run: `cd frontend && flutter test test/widgets/message/message_context_menu_overlay_test.dart`  
Expected: FAIL — `openMessageContextMenu` missing

- [ ] **Step 3: Implement overlay** (`message_context_menu_overlay.dart`)

Key API:

```dart
OverlayEntry? _activeMessageContextMenu;

void openMessageContextMenu({
  required BuildContext context,
  required MessageModel message,
  required RenderBox bubbleRenderBox,
  required bool isMine,
  required int? currentUserId,
  required VoidCallback onReply,
  required VoidCallback onPin,
  required VoidCallback onDelete,
  required void Function(String emoji, bool alreadyReacted) onReaction,
}) {
  _dismissMessageContextMenu();
  final overlay = Overlay.of(context);
  final l10n = AppLocalizations.of(context)!;
  final bubbleRect = bubbleRenderBox.localToGlobal(Offset.zero) &
      bubbleRenderBox.size;
  final viewPadding = MediaQuery.paddingOf(context);
  final viewSize = MediaQuery.sizeOf(context);
  final keyboardBottom = MediaQuery.viewInsetsOf(context).bottom;
  // ... position emoji row above bubbleRect; panel outward from center (isMine → left)
  // ... clamp to viewPadding; if bubbleRect.bottom > viewSize.height - keyboardBottom - 200 → flip panel above composer
  // Emoji list: const emojis = ['👍', '❤️', '😂', '😮', '😢', '🔥'];
  // on tap: onReaction(emoji, alreadyReacted); _dismissMessageContextMenu();
  // Panel callbacks:
  //   Reply → dismiss, onReply()
  //   Edit → onEdit() (caller shows showTopSnackBar messageEditComingSoon); dismiss
  //   Pin → if message.id <= 0 showTopSnackBar l10n.messagePinRequiresSentMessage else onPin(); dismiss
  //   Delete → dismiss; onDelete() opens dialog from caller
  _activeMessageContextMenu = OverlayEntry(builder: ...);
  overlay.insert(_activeMessageContextMenu!);
}

void dismissMessageContextMenu() => _dismissMessageContextMenu();
```

Use `MessageActionPanel` with `canPinOrDeleteForEveryone: message.id > 0` and:

```dart
onEdit: () {
  showTopSnackBar(context, l10n.messageEditComingSoon);
},
```

Scrim: `GestureDetector(onTap: dismissMessageContextMenu, child: ColoredBox(color: Colors.black54))`.

- [ ] **Step 4: Run overlay test**

Run: `cd frontend && flutter test test/widgets/message/message_context_menu_overlay_test.dart`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/widgets/message/message_context_menu_overlay.dart frontend/test/widgets/message/message_context_menu_overlay_test.dart
git commit -m "feat: Zangi-style message context menu overlay"
```

---

### Task 6: Wire `ChatMessageBubble` and `VoiceMessageContent`

**Files:**
- Modify: `frontend/lib/widgets/message/chat_message_bubble.dart`
- Modify: `frontend/lib/widgets/message/voice_message_content.dart`

- [ ] **Step 1: Add imports and delete dialog wiring in bubble**

Replace `_showReactionOptions` usage with:

```dart
void _openContextMenu(BuildContext context) {
  final messaging = context.read<MessagingProvider>();
  final auth = context.read<AuthProvider>();
  final renderBox = context.findRenderObject() as RenderBox?;
  if (renderBox == null) return;
  openMessageContextMenu(
    context: context,
    message: message,
    bubbleRenderBox: renderBox,
    isMine: isMine,
    currentUserId: auth.currentUser?.id,
    onReply: () => messaging.setReplyingTo(message),
    onPin: () {
      // Phase 1b: messaging.pinMessage(...); for 1a use snackbar or no-op
    },
    onDelete: () {
      showMessageDeleteDialog(
        context: context,
        isMine: isMine,
        messageId: message.id,
        onDeleteForMe: () =>
            messaging.deleteMessage(message.id, forEveryone: false),
        onDeleteForEveryone: () =>
            messaging.deleteMessage(message.id, forEveryone: true),
      );
    },
    onReaction: (emoji, alreadyReacted) {
      if (alreadyReacted) {
        messaging.removeReaction(message.id, emoji);
      } else {
        messaging.addReaction(message.id, emoji);
      }
    },
  );
}
```

Update `MessageSwipeWrapper`:

```dart
return MessageSwipeWrapper(
  isMine: isMine,
  onSwipeReply: () => messaging.setReplyingTo(message),
  onLongPress: () => _openContextMenu(context),
  child: ...
);
```

Remove `_showReactionOptions` and `showModalBottomSheet` block entirely.

- [ ] **Step 2: Mirror in `voice_message_content.dart`**

Same `MessageSwipeWrapper` changes: remove `onSwipeDelete`, use `openMessageContextMenu` on long-press (import overlay file).

- [ ] **Step 3: `ChatDetailScreen` — dismiss overlay on scroll and keyboard**

In `chat_detail_screen.dart` `_onScroll` or `NotificationListener` wrapping the `ListView`:

```dart
import '../widgets/message/message_context_menu_overlay.dart';

// Inside scroll notification handler:
if (notification is ScrollStartNotification) {
  dismissMessageContextMenu();
}
```

Add explicit keyboard dismiss: make `_ChatDetailScreenState` implement `WidgetsBindingObserver`, register in `initState` (`WidgetsBinding.instance.addObserver(this)`), remove in `dispose`, and in `didChangeMetrics` call `dismissMessageContextMenu()` when `MediaQuery.viewInsetsOf(context).bottom` changes (keyboard open/close). Do **not** assume an existing observer — wire it in this task.

- [ ] **Step 4: Run targeted tests + analyze**

Run: `cd frontend && flutter test test/widgets/message/ test/widgets/dialogs/message_delete_dialog_test.dart`  
Run: `cd frontend && flutter analyze`  
Expected: PASS / no new errors

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/widgets/message/chat_message_bubble.dart frontend/lib/widgets/message/voice_message_content.dart frontend/lib/screens/chat_detail_screen.dart
git commit -m "feat: wire context menu overlay on bubble and voice, remove swipe delete"
```

---

### Task 7: Phase 1a `CLAUDE.md` update

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update Frontend widgets / Delete actions**

Document:
- Swipe left → `setReplyingTo` only; swipe right → no action.
- Long-press → `MessageContextMenuOverlay` (reactions + panel); delete only via `MessageDeleteDialog`.
- Edit row greyed (`muted`) but tappable → `messageEditComingSoon` snackbar.

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: message actions Zangi panel UX in CLAUDE.md"
```

---

## Scroll-to-pinned spike (gate before Phase 1b banner)

**Do not ship `PinnedMessageBanner` until this section is complete and manually verified.**

### Task 8: `scroll_to_message_helper.dart` + unit tests

**Files:**
- Create: `frontend/lib/utils/scroll_to_message_helper.dart`
- Create: `frontend/test/utils/scroll_to_message_helper_test.dart`

**Scope:** Index math + pagination loop only. **Do not** create `GlobalKey` or call `Scrollable.ensureVisible` inside the helper — the caller (`ChatDetailScreen` itemBuilder) owns on-demand key assignment (see Task 9 spike + Task 19 production).

- [ ] **Step 1: Write failing index math tests**

```dart
import 'package:fireplace/utils/scroll_to_message_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('listIndexForMessageId oldest-first in reverse ListView', () {
    // messages oldest→newest: [m1, m2, m3]; reverse builder index 0 = m3
    expect(
      listIndexForMessageId(
        messageId: 2,
        messages: [
          _m(1),
          _m(2),
          _m(3),
        ],
      ),
      1,
    );
  });

  test('returns null when id not in list', () {
    expect(
      listIndexForMessageId(messageId: 99, messages: [_m(1)]),
      isNull,
    );
  });
}

// helper _m(id) => minimal stub with .id
```

- [ ] **Step 2: Implement helper**

```dart
import '../models/message_model.dart';

/// With [ListView.reverse: true], builder index 0 = newest (last in oldest-first list).
int? listIndexForMessageId({
  required int messageId,
  required List<MessageModel> messages,
}) {
  final msgIndex = messages.indexWhere((m) => m.id == messageId);
  if (msgIndex < 0) return null;
  return messages.length - 1 - msgIndex;
}

/// Paginate older pages until [messageId] appears in the loaded list, or give up.
/// Returns reverse-ListView builder index, or null if not found / no more pages.
/// Caller must assign [GlobalKey] to that index, rebuild, then call ensureVisible.
Future<int?> loadListIndexForMessageId({
  required int messageId,
  required List<MessageModel> Function() getMessages,
  required bool Function() hasMoreMessages,
  required Future<void> Function() loadOlderPage,
}) async {
  const maxPages = 40;
  for (var attempt = 0; attempt < maxPages; attempt++) {
    final listIndex = listIndexForMessageId(
      messageId: messageId,
      messages: getMessages(),
    );
    if (listIndex != null) return listIndex;
    if (!hasMoreMessages()) break;
    await loadOlderPage();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return null;
}
```

Document in file header:

```
// reverse:true → visual bottom = offset 0 = newest.
// msgIndex (oldest-first) → listIndex = messages.length - 1 - msgIndex.
// This file does NOT call Scrollable.ensureVisible — caller owns GlobalKey lifecycle.
```

- [ ] **Step 3: Run tests**

Run: `cd frontend && flutter test test/utils/scroll_to_message_helper_test.dart`  
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/utils/scroll_to_message_helper.dart frontend/test/utils/scroll_to_message_helper_test.dart
git commit -m "feat: scroll-to-message helper for reverse ListView"
```

---

### Task 9: Spike integration in `ChatDetailScreen`

**Files:**
- Modify: `frontend/lib/screens/chat_detail_screen.dart`

**Pattern:** Caller owns `_scrollTargetListIndex` / `_scrollTargetKey` state (same as Task 19). Helper returns index after pagination; screen sets key on target row, waits a frame, then `ensureVisible`.

- [ ] **Step 1: Add state fields + itemBuilder key hook**

On `_ChatDetailScreenState`:

```dart
int? _scrollTargetListIndex;
GlobalKey? _scrollTargetKey;

// In ListView itemBuilder (reverse list):
final listIndex = index;
final scrollKey = listIndex == _scrollTargetListIndex
    ? (_scrollTargetKey ??= GlobalKey())
    : null;
return KeyedSubtree(key: scrollKey, child: messageBubble);
```

- [ ] **Step 2: Add spike scroll method**

```dart
Future<void> _spikeScrollToMessageId(int messageId) async {
  final messaging = context.read<MessagingProvider>();
  final l10n = AppLocalizations.of(context)!;

  final listIndex = await loadListIndexForMessageId(
    messageId: messageId,
    getMessages: () => messaging.messages,
    hasMoreMessages: () => messaging.hasMoreMessages,
    loadOlderPage: () async {
      messaging.loadOlderMessages(widget.conversationId);
    },
  );

  if (listIndex == null) {
    if (mounted) {
      showTopSnackBar(context, l10n.snackbarPinnedMessageUnavailable);
    }
    return;
  }

  setState(() {
    _scrollTargetListIndex = listIndex;
    _scrollTargetKey = GlobalKey();
  });

  await WidgetsBinding.instance.endOfFrame;
  if (!mounted) return;

  final targetContext = _scrollTargetKey?.currentContext;
  if (targetContext != null) {
    await Scrollable.ensureVisible(
      targetContext,
      alignment: 0.5,
      duration: const Duration(milliseconds: 300),
    );
  }

  if (mounted) {
    setState(() {
      _scrollTargetListIndex = null;
      _scrollTargetKey = null;
    });
  }
}
```

Uses `snackbarPinnedMessageUnavailable` from Task 2 (no follow-up l10n deferral).

- [ ] **Step 3: Temporary dev trigger**

Wire a `debugOnly` long-press on AppBar title or use existing test message id from chat — **remove before release** or guard with `kDebugMode`.

- [ ] **Step 4: Manual gate checklist**

| Case | Pass? |
|------|-------|
| Target in first loaded page scrolls into view | |
| Target only on older page loads via pagination then scrolls | |
| Missing id shows snackbar, no infinite `loadOlderMessages` loop | |
| `ensureVisible` runs only after keyed row rebuild (not before) | |

- [ ] **Step 5: Commit spike**

```bash
git add frontend/lib/screens/chat_detail_screen.dart
git commit -m "spike: scroll-to-message in reverse chat ListView"
```

---

## Phase 1b — Pin message backend + banner + scroll

### Task 10: `Conversation` entity pin columns

**Files:**
- Modify: `backend/src/conversations/conversation.entity.ts`

- [ ] **Step 1: Add columns**

```typescript
@Column({ type: 'int', nullable: true, default: null })
pinnedMessageId: number | null;

@Column({ type: 'timestamp', nullable: true, default: null })
pinnedAt: Date | null;

@Column({ type: 'int', nullable: true, default: null })
pinnedByUserId: number | null;
```

- [ ] **Step 2: Document production SQL in `CLAUDE.md`**

```sql
ALTER TABLE conversations ADD COLUMN "pinnedMessageId" integer NULL;
ALTER TABLE conversations ADD COLUMN "pinnedAt" timestamp NULL;
ALTER TABLE conversations ADD COLUMN "pinnedByUserId" integer NULL;
```

- [ ] **Step 3: Commit**

```bash
git add backend/src/conversations/conversation.entity.ts CLAUDE.md
git commit -m "feat: conversation pin columns on entity"
```

---

### Task 11: `ConversationsService` pin methods

**Files:**
- Modify: `backend/src/conversations/conversations.service.ts`

**Note:** `ConversationsService` already injects `@InjectRepository(Message) messageRepo` (see existing constructor). Do **not** call `this.messagesService.findById` — that method does not exist on this service.

- [ ] **Step 1: Implement `setPinnedMessage`**

```typescript
async setPinnedMessage(
  conversationId: number,
  messageId: number,
  userId: number,
): Promise<Conversation> {
  const conv = await this.findById(conversationId);
  if (!conv) throw new Error('Conversation not found');
  // verify userId is userOne or userTwo
  const message = await this.messageRepo.findOne({
    where: { id: messageId },
    relations: ['conversation'],
  });
  if (!message || message.conversation.id !== conversationId) {
    throw new Error('Message not in conversation');
  }
  // optional: clear stale pin if current pinned message expired (lazy)
  conv.pinnedMessageId = messageId;
  conv.pinnedAt = new Date();
  conv.pinnedByUserId = userId;
  return this.convRepo.save(conv);
}

async clearPinnedMessage(conversationId: number): Promise<void> {
  await this.convRepo.update(conversationId, {
    pinnedMessageId: null,
    pinnedAt: null,
    pinnedByUserId: null,
  });
}
```

Alternative (also valid): inject `MessagesService` and use `findByIdWithConversation(messageId)` — match whichever pattern the handler layer already uses; prefer existing `messageRepo` in this service to avoid new module wiring.

- [ ] **Step 2: Commit**

```bash
git add backend/src/conversations/conversations.service.ts
git commit -m "feat: set and clear pinned message on conversation"
```

---

### Task 12: Pin DTOs + `ChatConversationService` handlers

**Files:**
- Create: `backend/src/chat/dto/pin-message.dto.ts`
- Modify: `backend/src/chat/services/chat-conversation.service.ts`

- [ ] **Step 1: DTOs**

```typescript
import { IsNumber, IsPositive } from 'class-validator';

export class PinMessageDto {
  @IsNumber()
  @IsPositive()
  conversationId: number;

  @IsNumber()
  @IsPositive()
  messageId: number;
}

export class UnpinMessageDto {
  @IsNumber()
  @IsPositive()
  conversationId: number;
}
```

- [ ] **Step 2: Handlers** (mirror `handleSetDisappearingTimer` emit-to-both pattern; **never bare throw to client**)

```typescript
import { isMessageExpired } from '../../messages/message-expiry.util';

async handlePinMessage(client, data, server, onlineUsers) {
  const userId = client.data.user?.id;
  if (!userId) {
    client.emit('error', { message: 'Unauthorized' });
    return;
  }
  let dto: PinMessageDto;
  try {
    dto = validateDto(PinMessageDto, data);
  } catch (error) {
    client.emit('error', { message: error.message });
    return;
  }

  const conversation = await this.conversationsService.findById(dto.conversationId);
  if (!conversation) {
    client.emit('error', { message: 'Conversation not found' });
    return;
  }
  const userBelongs =
    conversation.userOne.id === userId || conversation.userTwo.id === userId;
  if (!userBelongs) {
    client.emit('error', { message: 'Unauthorized' });
    return;
  }

  const message = await this.messagesService.findByIdWithConversation(dto.messageId);
  if (!message || message.conversation.id !== dto.conversationId) {
    client.emit('error', { message: 'Message not in conversation' });
    return;
  }
  if (isMessageExpired(message, new Date())) {
    client.emit('error', { message: 'Cannot pin expired message' });
    return;
  }

  const conv = await this.conversationsService.setPinnedMessage(
    dto.conversationId,
    dto.messageId,
    userId,
  );
  const snapshot = MessageMapper.toPayload(message, {
    conversationId: dto.conversationId,
  });
  const payload = {
    conversationId: dto.conversationId,
    pinnedMessageId: dto.messageId,
    pinnedMessage: snapshot,
    pinnedByUserId: userId,
    pinnedAt: conv.pinnedAt,
  };
  client.emit('messagePinned', payload);
  // emit to other participant socket (same pattern as handleSetDisappearingTimer)
}

async handleUnpinMessage(client, data, server, onlineUsers) {
  // validateDto(UnpinMessageDto); membership checks; client.emit('error', ...) on failure
  await this.conversationsService.clearPinnedMessage(conversationId);
  const payload = { conversationId };
  client.emit('messageUnpinned', payload);
  // emit to other participant
}
```

- [ ] **Step 3: Commit**

```bash
git add backend/src/chat/dto/pin-message.dto.ts backend/src/chat/services/chat-conversation.service.ts
git commit -m "feat: pin and unpin message WebSocket handlers"
```

---

### Task 13: Gateway + `ConversationMapper` snapshot

**Files:**
- Modify: `backend/src/chat/chat.gateway.ts`
- Modify: `backend/src/chat/mappers/conversation.mapper.ts`

- [ ] **Step 1: Gateway subscriptions**

```typescript
@SubscribeMessage('pinMessage')
@UseGuards(WsThrottlerGuard)
@Throttle({ default: { limit: 60, ttl: 900000 } })
async handlePinMessage(@ConnectedSocket() client: Socket, @MessageBody() data: any) {
  return this.chatConversationService.handlePinMessage(
    client, data, this.server, this.onlineUsers,
  );
}

@SubscribeMessage('unpinMessage')
@UseGuards(WsThrottlerGuard)
@Throttle({ default: { limit: 60, ttl: 900000 } })
async handleUnpinMessage(...) { ... }
```

- [ ] **Step 2: Mapper**

```typescript
// In toPayload return object, add:
pinnedMessageId: conversation.pinnedMessageId ?? null,
pinnedAt: conversation.pinnedAt ?? null,
pinnedByUserId: conversation.pinnedByUserId ?? null,
pinnedMessage: options?.pinnedMessage
  ? MessageMapper.toPayload(options.pinnedMessage, { conversationId: conversation.id })
  : null,
```

Update `conversationsWithUnread` / list builders to load pinned message row when `pinnedMessageId != null`.

- [ ] **Step 2b: Batch-load pinned messages for list snapshots** (mirror `getLastMessagesBatch` in `messages.service.ts`)

Add `getPinnedMessagesBatch(conversationIds: number[]): Promise<Map<number, Message | null>>` (or equivalent batch `findBy` on pinned ids) in `MessagesService`. In `conversationsWithUnread`, after `getLastMessagesBatch`, collect non-null `pinnedMessageId`s and batch-fetch pinned rows; pass each into `ConversationMapper.toPayload(conv, { ..., pinnedMessage: pinnedMap.get(convId) ?? null })`. Avoid N+1 per-conversation pin lookups.

- [ ] **Step 3: Commit**

```bash
git add backend/src/chat/chat.gateway.ts backend/src/chat/mappers/conversation.mapper.ts
git commit -m "feat: pin WS gateway and conversation payload snapshot"
```

---

### Task 14: Clear pin on delete-for-everyone

**Files:**
- Modify: `backend/src/chat/services/chat-message.service.ts`

- [ ] **Step 1: After successful hard delete**

```typescript
if (conv.pinnedMessageId === messageId) {
  await this.conversationsService.clearPinnedMessage(conversationId);
  const unpinPayload = { conversationId };
  client.emit('messageUnpinned', unpinPayload);
  const otherSocketId = onlineUsers.get(otherUserId);
  if (otherSocketId) {
    server.to(otherSocketId).emit('messageUnpinned', unpinPayload);
  }
}
```

Insert **before** or **after** `messageDeleted` emit — same handler, same transaction flow.

- [ ] **Step 2: Commit**

```bash
git add backend/src/chat/services/chat-message.service.ts
git commit -m "fix: clear conversation pin when pinned message deleted for everyone"
```

---

### Task 15: Backend unit tests

**Files:**
- Modify: `backend/src/chat/services/chat-conversation.service.spec.ts`
- Modify: `backend/src/chat/services/chat-message.service.spec.ts`

- [ ] **Step 1: Add tests in `chat-conversation.service.spec.ts`**

- Pin message A then pin B → `pinnedMessageId === B.id`
- Non-member pin → `client.emit('error', ...)` / no column update (mock `ConversationsService`)

- [ ] **Step 2: Add test in `chat-message.service.spec.ts`**

- Delete-for-everyone on pinned id → `clearPinnedMessage` called and `messageUnpinned` emitted (mock `ConversationsService`)

- [ ] **Step 3: Run backend tests**

Run: `cd backend && npm test -- chat-conversation.service.spec.ts`  
Run: `cd backend && npm test -- chat-message.service.spec.ts`  
Run: `cd backend && npm test`  
Expected: all suites PASS

- [ ] **Step 4: Commit**

```bash
git add backend/src/chat/services/chat-conversation.service.spec.ts backend/src/chat/services/chat-message.service.spec.ts
git commit -m "test: pin replace, auth, and delete clears pin"
```

---

### Task 16: Frontend `ConversationModel` + pin fields

**Files:**
- Modify: `frontend/lib/models/conversation_model.dart`

- [ ] **Step 1: Extend model**

```dart
final int? pinnedMessageId;
final MessageModel? pinnedMessagePreview;

// fromJson:
pinnedMessageId: json['pinnedMessageId'] as int?,
pinnedMessagePreview: json['pinnedMessage'] != null
    ? MessageModel.fromJson(json['pinnedMessage'] as Map<String, dynamic>)
    : null,
```

Follow `ConversationsProvider` pattern: **`ConversationModel` has no `copyWith`** — reconstruct manually with all fields when updating (see `onDisappearingTimerUpdated` handler in `conversations_provider.dart`).

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/models/conversation_model.dart
git commit -m "feat: conversation model pin id and preview snapshot"
```

---

### Task 17: Socket listeners + provider pin/unpin

**Files:**
- Modify: `frontend/lib/providers/connection_provider.dart`
- Modify: `frontend/lib/providers/conversations_provider.dart`
- Modify: `frontend/lib/providers/messaging_provider.dart`

- [ ] **Step 1: `ConnectionProvider` listeners**

```dart
_socketService.on('messagePinned', (data) {
  _conversationsProvider?.onMessagePinned(data);
});
_socketService.on('messageUnpinned', (data) {
  _conversationsProvider?.onMessageUnpinned(data);
});
```

- [ ] **Step 2: `ConversationsProvider` handlers**

Update matching conversation in `_conversations` with `pinnedMessageId` and `pinnedMessagePreview` from payload. Rebuild with `ConversationModel(...)` copying **all** existing fields (no `copyWith` on `ConversationModel`):

```dart
_conversations[index] = ConversationModel(
  id: oldConv.id,
  userOne: oldConv.userOne,
  userTwo: oldConv.userTwo,
  createdAt: oldConv.createdAt,
  disappearingTimer: oldConv.disappearingTimer,
  pinnedMessageId: payloadPinnedId,
  pinnedMessagePreview: preview,
);
```

- [ ] **Step 3: `MessagingProvider` emit methods**

```dart
void pinMessage(int conversationId, int messageId) {
  _emit?.call('pinMessage', {
    'conversationId': conversationId,
    'messageId': messageId,
  });
}

void unpinMessage(int conversationId) {
  _emit?.call('unpinMessage', {'conversationId': conversationId});
}
```

Wire `ChatMessageBubble` `onPin` to `pinMessage` when `message.id > 0`.

- [ ] **Step 4: Banner visibility rules** (client)

Hide banner when:
- `pinnedMessagePreview` null and id null
- pinned message expired (`isMessageExpired`)
- pinned message not in visible list (delete-for-me) — compare `MessagingProvider.messages`

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/providers/connection_provider.dart frontend/lib/providers/conversations_provider.dart frontend/lib/providers/messaging_provider.dart frontend/lib/widgets/message/chat_message_bubble.dart
git commit -m "feat: pin message state sync and provider emit"
```

---

### Task 18: `PinnedMessageBanner` + widget test

**Files:**
- Create: `frontend/lib/widgets/message/pinned_message_banner.dart`
- Create: `frontend/test/widgets/message/pinned_message_banner_test.dart`

- [ ] **Step 1: Widget test**

```dart
testWidgets('tap invokes onTap', (tester) async {
  var tapped = false;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: PinnedMessageBanner(
          previewText: 'Hello',
          senderLabel: 'alice',
          onTap: () => tapped = true,
          onUnpin: () {},
        ),
      ),
    ),
  );
  await tester.tap(find.byType(PinnedMessageBanner));
  expect(tapped, isTrue);
});
```

- [ ] **Step 2: Implement banner** — full-width Material bar under AppBar; `Icon(Icons.push_pin_outlined)`; truncated preview; `IconButton` close → `onUnpin` with `tooltip: l10n.pinnedMessageUnpinTooltip`; wrap in `Semantics(label: l10n.pinnedMessageBannerSemantics)`.

- [ ] **Step 3: Run test**

Run: `cd frontend && flutter test test/widgets/message/pinned_message_banner_test.dart`  
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/widgets/message/pinned_message_banner.dart frontend/test/widgets/message/pinned_message_banner_test.dart
git commit -m "feat: pinned message banner widget"
```

---

### Task 19: `ChatDetailScreen` banner + production scroll

**Files:**
- Modify: `frontend/lib/screens/chat_detail_screen.dart`

- [ ] **Step 1: Insert banner below AppBar** when `conv.pinnedMessageId != null` and visibility rules pass.

- [ ] **Step 2: `onTap`** → reuse Task 9 spike flow: `loadListIndexForMessageId` + on-demand `GlobalKey` on target list item (state already wired in Task 9):

```dart
int? _scrollTargetListIndex;
GlobalKey? _scrollTargetKey;

// In itemBuilder:
final listIndex = index;
final scrollKey = listIndex == _scrollTargetListIndex
    ? (_scrollTargetKey ??= GlobalKey())
    : null;
return KeyedSubtree(key: scrollKey, child: messageBubble);
```

Extract shared `_scrollToMessageId(int messageId)` from spike method if needed; production banner `onTap` calls it.

- [ ] **Step 3: Remove debug spike trigger** from Task 9.

- [ ] **Step 4: Manual + automated verification**

Run: `cd frontend && flutter test`  
Run: `cd frontend && flutter analyze`

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/screens/chat_detail_screen.dart
git commit -m "feat: pinned message banner with scroll-to-pinned"
```

---

### Task 20: Phase 1b `CLAUDE.md`

- [ ] Document pin WS events, entity columns, banner, scroll gate, delete-for-me banner hide, production SQL.

```bash
git add CLAUDE.md
git commit -m "docs: pinned message in chat CLAUDE.md"
```

---

## Phase 1c — Reply preview + media reply

### Task 21: `reply_preview_helper.dart` (**required before Task 23**)

**Files:**
- Create: `frontend/lib/utils/reply_preview_helper.dart`

- [ ] **Step 1: Implement context-free core + widget wrapper**

```dart
import '../l10n/app_localizations.dart';
import '../models/message_model.dart';
import '../providers/encryption_provider.dart';

/// Context-free helper for provider/tests — **required** for Task 23 media sends.
String replyPreviewForMessageModel(
  MessageModel message, {
  EncryptionProvider? encryption,
  required String encryptedMessageLabel,
  required String voiceMessageLabel,
  required String imageLabel,
  required String gifLabel,
  required String documentLabel,
  required String pingLabel,
}) {
  if (message.content == '[encrypted]') {
    final decrypted = encryption?.getDecryptedContent(message.id);
    if (decrypted != null && decrypted.isNotEmpty && decrypted != '[encrypted]') {
      return decrypted.length > 150
          ? '${decrypted.substring(0, 150)}...'
          : decrypted;
    }
    return encryptedMessageLabel;
  }
  if (message.content.isNotEmpty) {
    return message.content.length > 150
        ? '${message.content.substring(0, 150)}...'
        : message.content;
  }
  switch (message.messageType) {
    case MessageType.voice:
      return voiceMessageLabel;
    case MessageType.image:
      return imageLabel;
    case MessageType.gif:
      return gifLabel;
    case MessageType.file:
      return message.content.isNotEmpty ? message.content : documentLabel;
    case MessageType.ping:
      return pingLabel;
    default:
      return message.content;
  }
}

String replyPreviewForMessage(
  AppLocalizations l10n,
  MessageModel message, {
  EncryptionProvider? encryption,
}) =>
    replyPreviewForMessageModel(
      message,
      encryption: encryption,
      encryptedMessageLabel: l10n.encryptedMessage,
      voiceMessageLabel: l10n.voiceMessage,
      imageLabel: l10n.image,
      gifLabel: l10n.actionTileGif,
      documentLabel: l10n.attachmentOptionDocument,
      pingLabel: l10n.ping,
    );
```

Use existing l10n keys: `actionTileGif`, `attachmentOptionDocument` (not `document` or hardcoded `'GIF'`).

- [ ] **Step 2: Refactor `chat_message_bubble.dart`** `_replyDisplayContent` to call helper (pass `AppLocalizations.of(context)!`).

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/utils/reply_preview_helper.dart frontend/lib/widgets/message/chat_message_bubble.dart
git commit -m "refactor: shared reply preview helper"
```

---

### Task 22: Fix `ReplyPreviewBar`

**Files:**
- Modify: `frontend/lib/widgets/input/reply_preview_bar.dart`
- Create: `frontend/test/widgets/input/reply_preview_bar_test.dart`

- [ ] **Step 1: Test — no raw `[encrypted]`**

```dart
testWidgets('encrypted content shows Encrypted message l10n', (tester) async {
  await tester.pumpWidget(/* MaterialApp + l10n + ReplyPreviewBar with content: '[encrypted]' */);
  expect(find.text('Encrypted message'), findsOneWidget);
  expect(find.text('[encrypted]'), findsNothing);
});
```

- [ ] **Step 2: Use `replyPreviewForMessage` in bar** with `context.read<EncryptionProvider>()` and `AppLocalizations.of(context)!`.

- [ ] **Step 3: Run test**

Run: `cd frontend && flutter test test/widgets/input/reply_preview_bar_test.dart`  
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/widgets/input/reply_preview_bar.dart frontend/test/widgets/input/reply_preview_bar_test.dart
git commit -m "fix: E2E-aware localized reply preview bar"
```

---

### Task 23: Media sends with `replyToMessageId`

**Files:**
- Modify: `frontend/lib/providers/messaging_provider.dart`
- Create: `frontend/test/providers/messaging_provider_reply_media_test.dart`

- [ ] **Step 1: Failing provider test** (mock `_emit`)

Assert `sendImageMessage` path includes `replyToMessageId` in `_encryptAndSend` emit when `_replyingToMessage` set — follow patterns from existing provider tests; capture last emit payload map.

- [ ] **Step 2: Thread reply through `sendImageMessage`, `sendVoiceMessage`, `sendGif`, `sendFileMessage`**

**Prerequisite:** Task 21 `replyPreviewForMessageModel` must exist (not optional).

For each method, before creating optimistic message:

```dart
final effectiveReplyToId = _replyingToMessage?.id;
ReplyToPreview? replyPreview;
if (_replyingToMessage != null) {
  final rt = _replyingToMessage!;
  replyPreview = ReplyToPreview(
    id: rt.id,
    content: replyPreviewForMessageModel(
      rt,
      encryption: _encryptionProvider,
      encryptedMessageLabel: 'Encrypted message', // or inject l10n strings once at provider init
      voiceMessageLabel: 'Voice message',
      imageLabel: 'Image',
      gifLabel: 'GIF',
      documentLabel: 'Document',
      pingLabel: 'Ping',
    ),
    senderUsername: rt.senderUsername,
    messageType: rt.messageType,
  );
}
// MessageModel(..., replyToMessageId: effectiveReplyToId, replyTo: replyPreview)
// _encryptAndSend(..., effectiveReplyToId: effectiveReplyToId)
// After starting send: _replyingToMessage = null; notifyListeners();
```

Prefer passing localized label strings from a single provider-level lookup (default locale) or constants matching ARB defaults — **do not** duplicate preview logic inline; always call `replyPreviewForMessageModel`.

- [ ] **Step 3: Run tests**

Run: `cd frontend && flutter test test/providers/messaging_provider_reply_media_test.dart`  
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/providers/messaging_provider.dart frontend/test/providers/messaging_provider_reply_media_test.dart frontend/lib/utils/reply_preview_helper.dart
git commit -m "fix: include replyToMessageId on image voice gif file sends"
```

---

### Task 23b: Incoming quote enrichment (spec Phase 1c #5)

**Files:**
- Modify: `frontend/lib/providers/messaging_provider.dart`
- Modify: `frontend/lib/widgets/message/chat_message_bubble.dart` (if enrichment applied at display layer instead)
- Create: `frontend/test/providers/messaging_provider_reply_quote_enrichment_test.dart`

**Problem:** Server sends `replyTo.content: "Encrypted message"` (or `"[encrypted]"` placeholder) for E2E replies. After local decrypt, bubble/history quotes should show decrypted text or type labels — mirror `_replyDisplayContent` + `EncryptionProvider.getDecryptedContent`.

- [ ] **Step 1: Add enrichment helper** (in `reply_preview_helper.dart` or `messaging_provider.dart`)

```dart
ReplyToPreview enrichReplyToPreview(
  ReplyToPreview replyTo, {
  required EncryptionProvider? encryption,
  required String encryptedMessageLabel,
  // ... same label params as replyPreviewForMessageModel
}) {
  if (replyTo.content != '[encrypted]' &&
      replyTo.content != encryptedMessageLabel) {
    return replyTo;
  }
  final decrypted = encryption?.getDecryptedContent(replyTo.id);
  if (decrypted != null && decrypted.isNotEmpty && decrypted != '[encrypted]') {
    return ReplyToPreview(
      id: replyTo.id,
      content: decrypted.length > 150 ? '${decrypted.substring(0, 150)}...' : decrypted,
      senderUsername: replyTo.senderUsername,
      messageType: replyTo.messageType,
    );
  }
  // Fall back to type label for media when content is encrypted placeholder
  return ReplyToPreview(
    id: replyTo.id,
    content: replyTypeLabel(replyTo.messageType, ...),
    senderUsername: replyTo.senderUsername,
    messageType: replyTo.messageType,
  );
}
```

- [ ] **Step 2: Apply on incoming/history paths**

In `MessagingProvider`, after parsing `newMessage` / merging `messageHistory` rows that have `replyTo`, call enrichment before `_addMessageToState` / list merge (when `EncryptionProvider` available). Re-run enrichment after history decrypt pass completes (`_finishHistoryDecryptPass` or equivalent) so quotes update when cache fills.

- [ ] **Step 3: Widget display fallback**

In `chat_message_bubble.dart` `_replyDisplayContent`, when `replyTo.content == l10n.encryptedMessage`, also attempt `encryption.getDecryptedContent(replyTo.id)` before showing label (belt-and-suspenders for rows missed by provider pass).

- [ ] **Step 4: Provider test**

Assert incoming message with `replyTo.content == 'Encrypted message'` and mocked decrypt cache returns updated preview text in stored `MessageModel`.

- [ ] **Step 5: Run tests**

Run: `cd frontend && flutter test test/providers/messaging_provider_reply_quote_enrichment_test.dart`  
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/providers/messaging_provider.dart frontend/lib/utils/reply_preview_helper.dart frontend/lib/widgets/message/chat_message_bubble.dart frontend/test/providers/messaging_provider_reply_quote_enrichment_test.dart
git commit -m "fix: enrich reply quotes from local E2E decrypt cache"
```

---

### Task 24: Phase 1c docs + full verification + version bump

- [ ] Update `CLAUDE.md` — media reply paths, `ReplyPreviewBar`, helper, incoming quote enrichment (Task 23b).

- [ ] Run full suite:

```bash
cd backend && npm test
cd frontend && flutter analyze
cd frontend && flutter test
```

- [ ] Bump version `frontend/pubspec.yaml`: `0.0.2` → `0.0.3`

- [ ] Commit:

```bash
git add CLAUDE.md frontend/pubspec.yaml
git commit -m "release: message actions and pin v0.0.3"
```

---

## Phase 2 — Edit (E2E) — out of scope

Full **edit message** (WS `editMessage`, re-encrypt ciphertext, edited label, history update) requires a **separate spec** — not in this plan. Phase 1 ships only the greyed-but-tappable **Edit** row and `messageEditComingSoon` snackbar from Tasks 3/5/6.

---

## Self-review

### Spec coverage checklist

| Spec requirement | Plan task |
|------------------|-----------|
| Swipe left reply | Task 1 |
| Swipe right nothing | Task 1 |
| Long-press Zangi overlay | Tasks 5–6 |
| Emoji row replaces bottom sheet | Tasks 5–6 |
| Delete dialog for_me / for_everyone rules | Task 4 |
| Edit greyed + tappable snackbar | Tasks 2, 3, 5 |
| Pin backend + WS + snapshot | Tasks 10–15 |
| Pin banner + scroll | Tasks 8–9, 18–19 |
| Batch pinned snapshot load | Task 13 |
| Delete-for-everyone clears pin | Tasks 14–15 |
| Delete-for-me hides banner (client) | Task 17 |
| Media reply + E2E preview | Tasks 21–23 |
| Incoming quote enrichment (1c #5) | Task 23b |
| Scroll spike gate before 1b | Tasks 8–9 before 18–19 |
| Optimistic id pin/delete restrictions | Tasks 4, 5 |
| Overlay dismiss on scroll/keyboard | Task 6 |
| CLAUDE.md updates | Tasks 7, 20, 24 |
| Version bump | Task 24 |

### Placeholder scan result

- No unresolved `TODO` or “implement later” in Phase 1 task steps.
- Phase 2 edit time limit intentionally deferred to separate spec (not a Phase 1 blocker).
- Every test step includes runnable `flutter test` / `npm test` commands.
- All file paths are absolute to repo root under `frontend/` or `backend/`.
- Pin `onPin` in Task 6 notes 1b wiring — Task 17 completes it (no ambiguous end state).
- Scroll helper does not call `ensureVisible` before caller assigns `GlobalKey` (Tasks 8–9 / 19).

### Type / name consistency

- WS events: `pinMessage`, `unpinMessage`, `messagePinned`, `messageUnpinned` (spec-aligned).
- Delete modes: `for_me`, `for_everyone` (matches `DeleteMessageDto` and `MessagingProvider.deleteMessage`).
- `MessageSwipeWrapper` no longer exposes `onSwipeDelete` after Task 1 — Tasks 6+ must not reference it.

---

## Execution handoff

**Plan complete and saved to `docs/superpowers/plans/2026-05-23-message-actions-zangi-panel.md`.**

**Start here:** Phase 1a **Task 1** — refactor `MessageSwipeWrapper` and add `message_swipe_wrapper_test.dart`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task; review between tasks (use superpowers:subagent-driven-development).
2. **Inline Execution** — run tasks sequentially in one session (use superpowers:executing-plans with checkpoints after Phase 1a, after scroll spike, after 1b).

**Which approach?**

---

## External Plan Review

**Date:** 2026-05-23

External review findings applied to this plan:

1. **Edit row (Tasks 3, 5, 7):** Greyed (`muted`) but always tappable → `messageEditComingSoon` snackbar; removed `enabled: false` / `onTap: null` pattern.
2. **Scroll spike (Tasks 8–9, 19):** Removed broken internal `GlobalKey` + premature `ensureVisible`; helper is index math + pagination only; caller owns key assignment.
3. **Backend pin API (Tasks 11–13, 15):** Use existing `messageRepo.findOne` (not `messagesService.findById`); WS handlers emit `client.emit('error', …)`; Task 12 rejects expired pins via `isMessageExpired`; batch pinned load in Task 13; delete-clears-pin test moved to `chat-message.service.spec.ts`.
4. **Quote enrichment (Task 23b):** Added spec Phase 1c #5 — enrich incoming/history `replyTo` from local decrypt cache.
5. **l10n consolidation (Task 2, 18, 21):** Added `snackbarPinnedMessageUnavailable`, pinned banner strings; fixed helper to use `actionTileGif` / `attachmentOptionDocument`; Task 21 context-free helper required before Task 23.

Also: Task 6 explicit `WidgetsBindingObserver`; Task 16/17 note `ConversationModel` has no `copyWith`; self-review placeholder scan corrected.
