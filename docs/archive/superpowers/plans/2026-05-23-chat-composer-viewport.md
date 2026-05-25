# Chat Composer Viewport Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix Android chat layout jump by owning keyboard/composer layout in `ChatComposerViewport` with `resizeToAvoidBottomInset: false` on native full-screen chat.

**Architecture:** Stack overlays composer on messages; list bottom padding = measured composer height + `viewInsets.bottom`. Reply preview height changes no longer shrink `Expanded` list.

**Tech Stack:** Flutter 3.x, widget tests (`flutter_test`)

**Spec:** `docs/superpowers/specs/2026-05-23-chat-composer-viewport-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `frontend/lib/widgets/input/chat_composer_viewport.dart` | Stack layout + composer measure + padding callback |
| `frontend/lib/screens/chat_detail_screen.dart` | Wire viewport, `resizeToAvoidBottomInset: false`, keyboard scroll via metrics |
| `frontend/lib/widgets/input/chat_input_bar.dart` | Remove `showSoftKeyboardIfHidden` calls |
| `frontend/lib/utils/soft_keyboard.dart` | Delete if unused |
| `frontend/test/widgets/input/chat_composer_viewport_test.dart` | Padding/measure behavior |
| `frontend/pubspec.yaml` | Version `0.0.8` |
| `CLAUDE.md` | Replace keyboard jump limitation with viewport note |

---

### Task 1: `ChatComposerViewport` widget

**Files:**
- Create: `frontend/lib/widgets/input/chat_composer_viewport.dart`
- Test: `frontend/test/widgets/input/chat_composer_viewport_test.dart`

- [ ] **Step 1: Write failing test**

```dart
testWidgets('increases list bottom padding when composer grows', (tester) async {
  final padding = ValueNotifier<double>(48);
  await tester.pumpWidget(
    MaterialApp(
      home: ChatComposerViewport(
        messageListBuilder: (bottom) {
          padding.value = bottom;
          return ListView(reverse: true, children: const [Text('msg')]);
        },
        composer: const SizedBox(height: 48, child: ColoredBox(color: Colors.red)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(padding.value, greaterThanOrEqualTo(48));

  // Replace with taller composer via StatefulBuilder in test harness
});
```

- [ ] **Step 2: Implement viewport**

```dart
typedef MessageListBuilder = Widget Function(double listBottomPadding);

class ChatComposerViewport extends StatefulWidget {
  const ChatComposerViewport({
    super.key,
    required this.messageListBuilder,
    required this.composer,
  });

  final MessageListBuilder messageListBuilder;
  final Widget composer;

  @override
  State<ChatComposerViewport> createState() => _ChatComposerViewportState();
}
```

Measure composer with `GlobalKey`, `setState` when height changes, `Stack` + `Positioned(bottom: viewInsets.bottom)`.

- [ ] **Step 3: Run test**

`cd frontend && flutter test test/widgets/input/chat_composer_viewport_test.dart`

---

### Task 2: Integrate `ChatDetailScreen`

**Files:**
- Modify: `frontend/lib/screens/chat_detail_screen.dart`

- [ ] **Step 1:** Extract message list into builder using `listBottomPadding` on `ListView.padding.bottom`.
- [ ] **Step 2:** Wrap list+composer in `ChatComposerViewport` for `!widget.isEmbedded` body branch.
- [ ] **Step 3:** Set `resizeToAvoidBottomInset: false` on non-embedded `Scaffold`.
- [ ] **Step 4:** Remove keyboard auto-scroll from `build()`; implement in `didChangeMetrics`:

```dart
@override
void didChangeMetrics() {
  super.didChangeMetrics();
  final bottom = View.of(context).viewInsets.bottom;
  if (bottom > 0 && _lastKeyboardHeight == 0 && _messaging.messages.isNotEmpty) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      });
    });
  }
  _lastKeyboardHeight = bottom;
}
```

- [ ] **Step 5:** Run `flutter test test/screens/chat_detail_pinned_banner_test.dart`

---

### Task 3: Remove soft keyboard workaround

**Files:**
- Modify: `frontend/lib/widgets/input/chat_input_bar.dart`
- Delete: `frontend/lib/utils/soft_keyboard.dart`
- Delete: `frontend/test/utils/soft_keyboard_test.dart`

- [ ] Remove import and three `showSoftKeyboardIfHidden` call sites; keep `requestFocus` on reply.
- [ ] Delete files; run full `flutter test`.

---

### Task 4: Docs and version

- [ ] `frontend/pubspec.yaml` → `version: 0.0.8`
- [ ] `CLAUDE.md` §1 Frontend + §9 Known Limitations — document viewport fix and Android QA
- [ ] `graphify update .`
- [ ] Session summary `2026-05-23-session-chat-composer-viewport.md` + `LATEST.md`

---

### Task 5: Verification

```bash
cd frontend && flutter test test/widgets/input/chat_composer_viewport_test.dart test/screens/chat_detail_pinned_banner_test.dart
cd frontend && flutter analyze lib/widgets/input/chat_composer_viewport.dart lib/screens/chat_detail_screen.dart lib/widgets/input/chat_input_bar.dart
```

Expected: all tests pass, no analyze issues on touched files.

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| `resizeToAvoidBottomInset: false` | Task 2 |
| Stack + positioned composer | Task 1 |
| List padding = composer + inset | Task 1–2 |
| Reply inside composer, measured | Task 1–2 |
| No build() keyboard side effects | Task 2 |
| Remove soft_keyboard | Task 3 |
| Version 0.0.8 | Task 4 |
| Native non-embedded only | Task 2 (embedded unchanged) |
