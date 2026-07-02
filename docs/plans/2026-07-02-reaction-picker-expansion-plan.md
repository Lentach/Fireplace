# In-Place Expanding Reaction Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the reaction bottom sheet with a Telegram-style chevron that expands the emoji picker in place inside the message context menu, and make system back close the menu instead of the chat.

**Architecture:** All changes live in `frontend/lib/widgets/message/message_context_menu_overlay.dart` (a pure layout function + overlay builder state) and its test file. The expanded panel reuses `FireplaceEmojiPicker` unchanged. Back handling uses a `PopEntry` registered on the chat's `ModalRoute` (same mechanism `PopScope` uses) — a `WidgetsBindingObserver` does NOT work because `WidgetsAppState.didPopRoute` registers earlier and pops the route first.

**Tech Stack:** Flutter widget layer only. No backend, no wire-contract, no l10n changes (the `messageReactionMoreEmoji` ARB key is reused). Spec: `docs/plans/2026-07-02-reaction-picker-expansion-design.md`.

**Worktree:** `C:/Users/Lentach/Desktop/Fireplace/.worktrees/feat-emoji-reactions` (branch `feat/emoji-reactions`). All commands run from `<worktree>/frontend` unless stated.

**Read first:** root `CLAUDE.md`, `frontend/CLAUDE.md` (mandatory per `AGENTS.md`), the spec, and the current `message_context_menu_overlay.dart` end to end (~550 lines).

**Known test constraint (probe-verified 2026-07-02):** `emoji_picker_flutter`'s grid renders NOTHING under the widget-test binding (async init never completes; `find.text('😀')` finds 0). Never write a widget test that taps the package grid. The tappable path in tests is the picker's suggested row (`ValueKey('emoji-picker-option-<emoji>')` from `_SuggestedEmojiRow` in `fireplace_emoji_picker.dart`), which is why the expanded panel keeps `showSuggestedRow: true`.

---

### Task 1: Pure layout function `computeExpandedReactionPickerLayout`

**Files:**
- Modify: `frontend/lib/widgets/message/message_context_menu_overlay.dart` (insert after `computePanelLeft`, which ends around line 242)
- Test: `frontend/test/widgets/message/message_context_menu_overlay_test.dart` (new `group` next to the existing `computeMessageContextMenuLayout` groups)

- [ ] **Step 1: Write the failing tests**

Add to `message_context_menu_overlay_test.dart`, alongside the existing pure-layout groups (top-level `main`, before the widget tests). `dart:math` is NOT yet imported there — add `import 'dart:math' as math;` at the top of the test file.

```dart
group('computeExpandedReactionPickerLayout', () {
  const viewSize = Size(400, 800);
  const wideViewSize = Size(800, 800);
  const viewPadding = EdgeInsets.only(top: 40, bottom: 20);
  const gap = kMessageContextMenuOverlayGap;

  ({double left, double top, double width, double height, bool below})
  layoutFor({
    Rect bubbleRect = const Rect.fromLTWH(120, 200, 240, 48),
    Size size = viewSize,
    double keyboardBottom = 0,
    bool isMine = true,
    double? bubbleHighlightTop,
    double? previewHeight,
  }) => computeExpandedReactionPickerLayout(
    bubbleRect: bubbleRect,
    viewPadding: viewPadding,
    viewSize: size,
    keyboardBottom: keyboardBottom,
    isMine: isMine,
    bubbleHighlightTop: bubbleHighlightTop ?? bubbleRect.top,
    previewHeight: previewHeight ?? bubbleRect.height,
  );

  test('prefers the larger region below a high bubble and caps at 420', () {
    final l = layoutFor();
    expect(l.below, isTrue);
    final highlightBottom = bubbleHighlightVisualBottom(
      bubbleHighlightTop: 200,
      layoutBubbleHeight: 48,
    );
    expect(l.top, closeTo(highlightBottom + gap, 0.001));
    expect(l.height, kExpandedReactionPickerMaxHeight);
    expect(
      l.top + l.height,
      lessThanOrEqualTo(800 - 20 - kExpandedReactionPickerMargin),
    );
  });

  test('places above when the bubble sits near the screen bottom', () {
    final l = layoutFor(bubbleRect: const Rect.fromLTWH(120, 680, 240, 48));
    expect(l.below, isFalse);
    final highlightTop = bubbleHighlightVisualTop(
      bubbleHighlightTop: 680,
      layoutBubbleHeight: 48,
    );
    expect(l.top + l.height, closeTo(highlightTop - gap, 0.001));
    expect(l.top, greaterThanOrEqualTo(viewPadding.top + 8));
  });

  test('keyboard inset shrinks the below region', () {
    final noKb = layoutFor();
    final withKb = layoutFor(keyboardBottom: 300);
    expect(withKb.height, lessThan(noKb.height));
    expect(
      withKb.top + withKb.height,
      lessThanOrEqualTo(800 - 300 - kExpandedReactionPickerMargin),
    );
  });

  test('width caps at 360 and respects 16px margins on narrow screens', () {
    final l = layoutFor();
    expect(l.width, math.min(400 - 32, kExpandedReactionPickerMaxWidth));
    expect(l.left, greaterThanOrEqualTo(kExpandedReactionPickerMargin));
    expect(
      l.left + l.width,
      lessThanOrEqualTo(400 - kExpandedReactionPickerMargin),
    );
  });

  test('own message right-aligns panel to the bubble right edge', () {
    final l = layoutFor(
      size: wideViewSize,
      bubbleRect: const Rect.fromLTWH(300, 200, 240, 48),
    );
    expect(l.width, kExpandedReactionPickerMaxWidth);
    expect(l.left + l.width, closeTo(540, 0.001)); // bubbleRect.right
  });

  test('received message left-aligns panel to the bubble left edge', () {
    final l = layoutFor(
      size: wideViewSize,
      isMine: false,
      bubbleRect: const Rect.fromLTWH(300, 200, 240, 48),
    );
    expect(l.left, closeTo(300, 0.001)); // bubbleRect.left
  });

  test('huge-message clamped previewHeight drives the free regions', () {
    // Raw bubble is 700px tall but the overlay shows a clamped 400px preview
    // starting at highlight top 150; free space is measured from the preview.
    final l = layoutFor(
      bubbleRect: const Rect.fromLTWH(20, 100, 300, 700),
      bubbleHighlightTop: 150,
      previewHeight: 400,
    );
    final highlightBottom = bubbleHighlightVisualBottom(
      bubbleHighlightTop: 150,
      layoutBubbleHeight: 400,
    );
    expect(l.below, isTrue);
    expect(l.top, closeTo(highlightBottom + gap, 0.001));
  });
});
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/widgets/message/message_context_menu_overlay_test.dart`
Expected: COMPILE ERROR — `computeExpandedReactionPickerLayout`, `kExpandedReactionPickerMaxHeight`, `kExpandedReactionPickerMaxWidth`, `kExpandedReactionPickerMargin` undefined.

- [ ] **Step 3: Implement the layout function**

In `message_context_menu_overlay.dart`, insert immediately after the closing brace of `computePanelLeft` (currently ends ~line 242):

```dart
/// Max size and screen margin of the in-place expanded reaction picker.
const kExpandedReactionPickerMaxHeight = 420.0;
const kExpandedReactionPickerMaxWidth = 360.0;
const kExpandedReactionPickerMargin = 16.0;

/// Telegram-style in-place expansion: the panel replaces the emoji row and
/// action panel in the larger free region above or below the (possibly
/// clamped) bubble highlight. It never covers the bubble, never crosses the
/// 16px screen margins, and never sits under the keyboard or home indicator.
///
/// [bubbleHighlightTop] and [previewHeight] come from
/// [computeMessageContextMenuLayout] so huge-message clamped previews are
/// respected. [below] is also the entrance-animation anchor side.
@visibleForTesting
({double left, double top, double width, double height, bool below})
computeExpandedReactionPickerLayout({
  required Rect bubbleRect,
  required EdgeInsets viewPadding,
  required Size viewSize,
  required double keyboardBottom,
  required bool isMine,
  required double bubbleHighlightTop,
  required double previewHeight,
}) {
  const gap = kMessageContextMenuOverlayGap;
  const margin = kExpandedReactionPickerMargin;
  final minTop = viewPadding.top + 8;
  final maxBottom =
      viewSize.height - math.max(keyboardBottom, viewPadding.bottom) - margin;
  final highlightTop = bubbleHighlightVisualTop(
    bubbleHighlightTop: bubbleHighlightTop,
    layoutBubbleHeight: previewHeight,
  );
  final highlightBottom = bubbleHighlightVisualBottom(
    bubbleHighlightTop: bubbleHighlightTop,
    layoutBubbleHeight: previewHeight,
  );
  final above = highlightTop - gap - minTop;
  final below = maxBottom - (highlightBottom + gap);
  final placeBelow = below >= above;
  final region = math.max(placeBelow ? below : above, 0.0);
  final height = math.min(kExpandedReactionPickerMaxHeight, region);
  final top = placeBelow ? highlightBottom + gap : highlightTop - gap - height;
  final width = math.min(
    viewSize.width - 2 * margin,
    kExpandedReactionPickerMaxWidth,
  );
  final leftRaw = isMine ? bubbleRect.right - width : bubbleRect.left;
  final left = math.min(
    math.max(leftRaw, margin),
    viewSize.width - margin - width,
  );
  return (
    left: left,
    top: top,
    width: width,
    height: height,
    below: placeBelow,
  );
}
```

`dart:math` is already imported in this file as `math`.

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/widgets/message/message_context_menu_overlay_test.dart`
Expected: PASS (all groups; the 7 new tests green).

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/widgets/message/message_context_menu_overlay.dart frontend/test/widgets/message/message_context_menu_overlay_test.dart
git commit -m "feat(reactions): expanded picker layout function"
```

---

### Task 2: Chevron affordance on the reaction row

**Files:**
- Modify: `frontend/lib/widgets/message/message_context_menu_overlay.dart` (`_ContextMenuReactionEmojiBar`, currently ~lines 463–552, and its callsite ~line 382)
- Modify: `frontend/test/widgets/message/message_context_menu_overlay_test.dart` (one finder in the bottom-sheet inset test — keeps the suite green until Task 3 deletes that test)

- [ ] **Step 1: Rename the callback and swap the icon**

In `_ContextMenuReactionEmojiBar`: rename the field/parameter `onMoreEmoji` → `onExpand` (constructor, field declaration, usage). Replace the trailing IconButton block (the `Semantics`+`Tooltip`+`IconButton` after the `..._kReactionEmojis.map(...)` spread) with:

```dart
              Semantics(
                button: true,
                label: l10n.messageReactionMoreEmoji,
                excludeSemantics: true,
                child: Tooltip(
                  message: l10n.messageReactionMoreEmoji,
                  child: IconButton(
                    key: const ValueKey('context-menu-expand-reactions'),
                    onPressed: onExpand,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    padding: EdgeInsets.zero,
                    iconSize: 22,
                    icon: const Icon(Icons.keyboard_arrow_down),
                  ),
                ),
              ),
```

At the callsite inside `openMessageContextMenu`'s `Stack` (the `_ContextMenuReactionEmojiBar(...)` under the `context-menu-emoji-bar` `Positioned`), rename the argument:

```dart
                  onExpand: () => setOverlayState(() {
                    pickerOpen = true;
                  }),
```

- [ ] **Step 2: Fix the one key-based finder so the suite stays green**

In `message_context_menu_overlay_test.dart`, the test `'reaction emoji picker sheet is lifted above the keyboard inset'` taps `ValueKey('context-menu-more-emoji-reactions')`. Change that line to:

```dart
      await tester.tap(
        find.byKey(const ValueKey('context-menu-expand-reactions')),
      );
```

(The semantics-label finders `'More emoji reactions'` in the other two tests are unaffected — the label is reused.)

- [ ] **Step 3: Run to verify pass**

Run: `flutter test test/widgets/message/message_context_menu_overlay_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/widgets/message/message_context_menu_overlay.dart frontend/test/widgets/message/message_context_menu_overlay_test.dart
git commit -m "feat(reactions): chevron expand affordance on reaction row"
```

---

### Task 3: In-place expanded panel replaces the bottom sheet

**Files:**
- Modify: `frontend/lib/widgets/message/message_context_menu_overlay.dart` (overlay `StatefulBuilder` body, ~lines 294–455)
- Modify: `frontend/test/widgets/message/message_context_menu_overlay_test.dart`

- [ ] **Step 1: Rewrite/replace the widget tests (failing first)**

In `message_context_menu_overlay_test.dart`:

**(a)** Replace the body of `'reaction row exposes more emoji affordance and keeps menu open while picker opens'` and rename it:

```dart
  testWidgets(
    'chevron expands picker in place, hiding row and action panel',
    (tester) async {
      await pumpDirectContextMenu(tester);

      final expand = find.byKey(
        const ValueKey('context-menu-expand-reactions'),
      );
      expect(expand, findsOneWidget);
      expect(find.text('Reply'), findsOneWidget);

      await tester.tap(expand);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('context-menu-expanded-reaction-picker')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Emoji picker'), findsOneWidget);
      // Telegram parity: row and action panel unmount while expanded.
      expect(find.byKey(const Key('context-menu-emoji-bar')), findsNothing);
      expect(find.text('Reply'), findsNothing);
      // Scrim (and the bubble underneath) stay.
      expect(find.byType(BackdropFilter), findsOneWidget);
    },
  );
```

**(b)** In `'emoji picker selection invokes reaction callback and dismisses menu'`, replace the semantics-label tap with the key finder (the mechanism is otherwise unchanged — the suggested row inside the expanded panel provides `emoji-picker-option-🧙`):

```dart
      await tester.tap(
        find.byKey(const ValueKey('context-menu-expand-reactions')),
      );
```

**(c)** Delete the whole `'reaction emoji picker sheet is lifted above the keyboard inset'` test (the sheet no longer exists; keyboard behavior is covered by the Task 1 layout test `'keyboard inset shrinks the below region'`). If `FireplaceEmojiPicker` is then unused in the test file, drop its import.

**(d)** Add two new tests after (a):

```dart
  testWidgets('expanded picker geometry matches the layout function', (
    tester,
  ) async {
    await pumpDirectContextMenu(tester);
    await tester.tap(
      find.byKey(const ValueKey('context-menu-expand-reactions')),
    );
    await tester.pumpAndSettle();

    final panel = find.byKey(
      const Key('context-menu-expanded-reaction-picker'),
    );
    final positioned = tester.widget<Positioned>(panel);
    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(positioned.width, math.min(screenWidth - 32, 360));
    expect(positioned.height, lessThanOrEqualTo(420));
    expect(
      positioned.left,
      greaterThanOrEqualTo(kExpandedReactionPickerMargin),
    );
  });

  testWidgets('outside tap dismisses the expanded picker overlay', (
    tester,
  ) async {
    await pumpDirectContextMenu(tester);
    await tester.tap(
      find.byKey(const ValueKey('context-menu-expand-reactions')),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('context-menu-expanded-reaction-picker')),
      findsNothing,
    );
    expect(find.byType(BackdropFilter), findsNothing);
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/widgets/message/message_context_menu_overlay_test.dart`
Expected: FAIL — `context-menu-expanded-reaction-picker` not found; `Reply` still present after expand.

- [ ] **Step 3: Implement the expanded panel**

In `openMessageContextMenu`'s `StatefulBuilder` (the `var pickerOpen = false;` declared above `_activeMessageContextMenu = OverlayEntry(...)`):

**(a)** Rename `pickerOpen` → `pickerExpanded` (declaration and both uses).

**(b)** Wrap the emoji-bar `Positioned` (key `context-menu-emoji-bar`) and the action-panel `Positioned` (key `context-menu-action-panel`) each with `if (!pickerExpanded)`:

```dart
              if (!pickerExpanded)
                Positioned(
                  key: const Key('context-menu-emoji-bar'),
                  ...unchanged...
                ),
              if (!pickerExpanded)
                Positioned(
                  key: const Key('context-menu-action-panel'),
                  ...unchanged...
                ),
```

**(c)** Replace the entire `if (pickerOpen) Positioned(left: 0, right: 0, bottom: MediaQuery.viewInsetsOf(ctx).bottom, child: Material(...FireplaceEmojiPicker(height: 360)...))` bottom-sheet block with:

```dart
              if (pickerExpanded)
                () {
                  final picker = computeExpandedReactionPickerLayout(
                    bubbleRect: layoutRect,
                    viewPadding: viewPadding,
                    viewSize: viewSize,
                    keyboardBottom: keyboardBottom,
                    isMine: isMine,
                    bubbleHighlightTop: layout.bubbleHighlightTop,
                    previewHeight: layout.previewHeight,
                  );
                  return Positioned(
                    key: const Key('context-menu-expanded-reaction-picker'),
                    left: picker.left,
                    top: picker.top,
                    width: picker.width,
                    height: picker.height,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOutCubic,
                      child: Material(
                        elevation: 16,
                        color: Theme.of(ctx).colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        clipBehavior: Clip.antiAlias,
                        child: FireplaceEmojiPicker(
                          onEmojiSelected: selectPickerEmoji,
                          onBackspacePressed: null,
                          height: picker.height,
                        ),
                      ),
                      builder: (context, t, child) => Opacity(
                        opacity: t,
                        child: Transform.scale(
                          scale: 0.95 + 0.05 * t,
                          alignment: picker.below
                              ? (isMine
                                    ? Alignment.topRight
                                    : Alignment.topLeft)
                              : (isMine
                                    ? Alignment.bottomRight
                                    : Alignment.bottomLeft),
                          child: child,
                        ),
                      ),
                    ),
                  );
                }(),
```

Notes for the implementer:
- `layout`, `layoutRect`, `viewPadding`, `viewSize`, `keyboardBottom`, `isMine`, `selectPickerEmoji` are all already in scope in that builder.
- `FireplaceEmojiPicker` keeps its default `showSuggestedRow: true` — deliberate; see the plan header's test constraint and the spec's amended decision 2.
- The immediately-invoked closure keeps the layout computation next to its single consumer; no new state.

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/widgets/message/message_context_menu_overlay_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/widgets/message/message_context_menu_overlay.dart frontend/test/widgets/message/message_context_menu_overlay_test.dart
git commit -m "feat(reactions): expand emoji picker in place, drop bottom sheet"
```

---

### Task 4: System back closes the menu, not the chat

**Files:**
- Modify: `frontend/lib/widgets/message/message_context_menu_overlay.dart` (top-level state ~line 12, `_dismissMessageContextMenu`, end of `openMessageContextMenu`)
- Test: `frontend/test/widgets/message/message_context_menu_overlay_test.dart`

**Why `PopEntry`, not `WidgetsBindingObserver`:** `WidgetsAppState` registers its own observer at app startup and `handlePopRoute` asks observers in registration order — the app's observer pops the chat route before a later-registered one is consulted. `PopEntry` registered on the chat's `ModalRoute` (the exact mechanism `PopScope` uses) flips the route's `popDisposition` to `doNotPop`, so back is consumed and our callback runs. This also covers Android predictive back.

- [ ] **Step 1: Write the failing tests**

```dart
  testWidgets('system back closes the context menu instead of the route', (
    tester,
  ) async {
    await pumpDirectContextMenu(tester);
    expect(find.text('Reply'), findsOneWidget);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    final handled = await navigator.maybePop();
    await tester.pumpAndSettle();

    expect(handled, isTrue); // consumed by the overlay's PopEntry
    expect(find.text('Reply'), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('bubble'), findsOneWidget); // chat screen intact
  });

  testWidgets('system back closes the expanded picker overlay too', (
    tester,
  ) async {
    await pumpDirectContextMenu(tester);
    await tester.tap(
      find.byKey(const ValueKey('context-menu-expand-reactions')),
    );
    await tester.pumpAndSettle();

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('context-menu-expanded-reaction-picker')),
      findsNothing,
    );
    expect(find.text('bubble'), findsOneWidget);
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/widgets/message/message_context_menu_overlay_test.dart`
Expected: FAIL — `handled` is false (root route has nothing to pop) and/or `Reply` still present.

- [ ] **Step 3: Implement the PopEntry**

**(a)** Below `OverlayEntry? _activeMessageContextMenu;` (top of file) add:

```dart
/// Consumes system back while the context menu is open (collapsed or
/// expanded): back closes the menu instead of popping the chat route.
/// Registered on the caller's [ModalRoute] — the same mechanism [PopScope]
/// uses — because a [WidgetsBindingObserver] would be consulted after
/// [WidgetsApp]'s own observer already popped the route.
class _ContextMenuPopEntry implements PopEntry<Object?> {
  final ValueNotifier<bool> _canPop = ValueNotifier<bool>(false);

  @override
  ValueListenable<bool> get canPopNotifier => _canPop;

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (!didPop) _dismissMessageContextMenu();
  }

  void dispose() => _canPop.dispose();
}

_ContextMenuPopEntry? _contextMenuPopEntry;
ModalRoute<Object?>? _contextMenuPopRoute;
```

Add `import 'package:flutter/foundation.dart' show ValueListenable;` if the analyzer asks for it (`ValueNotifier` comes with material). If the project's Flutter version still declares the deprecated `PopEntry.onPopInvoked`, add `@override void onPopInvoked(bool didPop) {}` as a no-op.

**(b)** Replace `_dismissMessageContextMenu`:

```dart
void _dismissMessageContextMenu() {
  final entry = _contextMenuPopEntry;
  if (entry != null) {
    _contextMenuPopRoute?.unregisterPopEntry(entry);
    entry.dispose();
    _contextMenuPopEntry = null;
    _contextMenuPopRoute = null;
  }
  _activeMessageContextMenu?.remove();
  _activeMessageContextMenu = null;
}
```

**(c)** At the end of `openMessageContextMenu`, after `overlay.insert(_activeMessageContextMenu!);`:

```dart
  final route = ModalRoute.of(context);
  if (route != null) {
    _contextMenuPopEntry = _ContextMenuPopEntry();
    _contextMenuPopRoute = route;
    route.registerPopEntry(_contextMenuPopEntry!);
  }
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/widgets/message/message_context_menu_overlay_test.dart`
Expected: PASS (every test in the file).

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/widgets/message/message_context_menu_overlay.dart frontend/test/widgets/message/message_context_menu_overlay_test.dart
git commit -m "fix(reactions): system back closes context menu, not the chat"
```

---

### Task 5: Docs, verification, push

**Files:**
- Modify: `frontend/CLAUDE.md` (§6 reactions bullet)
- Modify: `.cursor/session-summaries/` (new file + `LATEST.md`) — gitignored, write only
- No version bump: the branch already carries the unreleased 0.0.76→0.0.77 bump.

- [ ] **Step 1: Update `frontend/CLAUDE.md` §6**

Replace the reactions bullet with:

```markdown
- Reactions: context-menu quick row calls `MessagingActions.addReaction/removeReaction`; the chevron (`context-menu-expand-reactions`) expands `FireplaceEmojiPicker` in place via `computeExpandedReactionPickerLayout` (row + action panel unmount, bubble stays; never covers bubble/keyboard). System back closes the menu via a `PopEntry` on the chat route. `emoji_picker_flutter`'s grid renders nothing under the widget-test binding — test emoji selection through the suggested row keys only. Composer emoji insertion/backspace must use `composer_emoji_text_editing.dart` so emoji sequences stay grapheme-safe.
```

- [ ] **Step 2: Format and analyze**

Run: `dart format lib/widgets/message/message_context_menu_overlay.dart test/widgets/message/message_context_menu_overlay_test.dart` then `flutter analyze --no-fatal-infos`
Expected: no issues.

- [ ] **Step 3: Full verification run**

Run: `flutter test test/widgets/message/message_context_menu_overlay_test.dart test/widgets/input/chat_input_bar_send_test.dart`
Expected: all green (composer-panel tests from the previous feature must not regress).

- [ ] **Step 4: Graph + session summary**

Run from repo root: `graphify update .`
Write `.cursor/session-summaries/2026-07-02-session-reaction-picker-expansion.md` (What was done / Key files / Verification / Notes) and prepend to `LATEST.md` per `AGENTS.md` format.

- [ ] **Step 5: Commit and push**

```bash
git add frontend/CLAUDE.md
git commit -m "docs: reaction picker expansion memory"
git push origin feat/emoji-reactions
```

Then notify the user: branch ready for on-device VM verification (deploy the branch per `AGENTS.md` before any master merge; never merge without explicit user OK).
