import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/providers/settings_provider.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/chat_action_tiles.dart';
import 'package:fireplace/widgets/emoji/fireplace_emoji_picker.dart';
import 'package:fireplace/widgets/input/chat_input_bar.dart';
import 'package:fireplace/widgets/input/composer_keyboard_signals.dart';
import 'package:fireplace/utils/web_keyboard_inset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget _providerScope({required Widget child}) => MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => ConversationsProvider()),
    ChangeNotifierProvider(create: (_) => MessagingProvider()),
    ChangeNotifierProvider(
      create: (_) => SettingsProvider(initialThemePreference: 'light'),
    ),
  ],
  child: child,
);

Future<ChatInputBarState> _pump(WidgetTester tester) async {
  final key = GlobalKey<ChatInputBarState>();
  await tester.pumpWidget(
    MaterialApp(
      theme: RpgTheme.themeDataLight,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: _providerScope(child: ChatInputBar(key: key)),
      ),
    ),
  );
  await tester.pump();
  return key.currentState!;
}

Future<ChatInputBarState> _pumpWithBottomInset(WidgetTester tester) async {
  final key = GlobalKey<ChatInputBarState>();
  await tester.pumpWidget(
    MaterialApp(
      theme: RpgTheme.themeDataLight,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Builder(
        // Simulate a home-indicator safe area so the ergonomic bottom buffer
        // would render while the keyboard is down.
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(bottom: 34),
            viewPadding: const EdgeInsets.only(bottom: 34),
          ),
          child: Scaffold(
            body: _providerScope(child: ChatInputBar(key: key)),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return key.currentState!;
}

Future<ChatInputBarState> _pumpWithChatSurface(WidgetTester tester) async {
  final key = GlobalKey<ChatInputBarState>();
  await tester.pumpWidget(
    MaterialApp(
      theme: RpgTheme.themeDataLight,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: _providerScope(
          child: Column(
            children: [
              Expanded(
                child: Listener(
                  key: const ValueKey('chat-surface'),
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (_) =>
                      key.currentState?.dismissForChatSurfaceTap(),
                  child: const SizedBox.expand(),
                ),
              ),
              ChatInputBar(key: key),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return key.currentState!;
}

Future<ChatInputBarState> _pumpWithPlainOutsideSurface(WidgetTester tester) async {
  final key = GlobalKey<ChatInputBarState>();
  await tester.pumpWidget(
    MaterialApp(
      theme: RpgTheme.themeDataLight,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: _providerScope(
          child: Column(
            children: [
              Expanded(
                child: Listener(
                  key: const ValueKey('plain-outside-surface'),
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox.expand(),
                ),
              ),
              ChatInputBar(key: key),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return key.currentState!;
}

Future<void> _openEmojiPanel(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('composer-emoji-toggle')));
  await tester.pumpAndSettle();
  expect(find.byType(FireplaceEmojiPicker), findsOneWidget);
}

void main() {
  setUp(() => composerKeyboardCollapseGuard.value = false);
  tearDown(() {
    composerKeyboardCollapseGuard.value = false;
    predictedComposerKeyboardInset.value = 0;
    composerBottomPanelPinned.value = false;
    setSharedKeyboardInsetSourceForTest(null);
  });

  // Boundary: the empty-text no-op must still precede any send side effect, so it
  // must NOT arm the collapse guard (the guard is armed only on a real send).
  testWidgets('empty send is a no-op and does not arm the collapse guard', (
    tester,
  ) async {
    final state = await _pump(tester);
    state.sendForTest();
    await tester.pump();
    expect(composerKeyboardCollapseGuard.value, isFalse);
  });

  // A real send routes through `_send()` (which dispatches to MessagingProvider)
  // and arms the keyboard collapse guard so the viewport keeps the flash guard.
  testWidgets('non-empty send arms the keyboard collapse guard', (
    tester,
  ) async {
    final state = await _pump(tester);
    await tester.enterText(find.byType(TextField), 'hello');
    state.sendForTest();
    await tester.pump();
    expect(composerKeyboardCollapseGuard.value, isTrue);
  });

  // Regression: the composer emoji picker must mutate the actual draft field,
  // not just render a detached picker.
  testWidgets('emoji picker opens and inserts a suggested emoji', (
    tester,
  ) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), 'Fire ');

    await tester.tap(find.byKey(const ValueKey('composer-emoji-toggle')));
    await tester.pumpAndSettle();

    final suggestedFire = find.byKey(const ValueKey('emoji-picker-option-🔥'));
    expect(suggestedFire, findsOneWidget);

    await tester.tap(suggestedFire);
    await tester.pump();

    expect(find.widgetWithText(TextField, 'Fire 🔥'), findsOneWidget);
  });

  // Telegram parity: focusing the text field swaps the emoji panel for the
  // keyboard — they must never be stacked at the same time.
  testWidgets('composer focus gain closes the emoji panel', (tester) async {
    await _pump(tester);
    await _openEmojiPanel(tester);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(find.byType(FireplaceEmojiPicker), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isTrue,
    );
  });

  // Android/desktop web parity: tapping the chat surface outside the composer
  // should hide the keyboard. The old blanket no-op was only meant for iOS
  // WebKit send-button bounce, but it blocked Android PWA dismissal too.
  testWidgets('tap outside unfocuses the composer outside iOS WebKit', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.byType(TextField));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasFocus, isTrue);

    field.onTapOutside!(const PointerDownEvent(position: Offset(1, 1)));
    await tester.pump();

    expect(field.focusNode!.hasFocus, isFalse);
  });

  testWidgets(
    'send button tap stays inside composer tap region and keeps focus',
    (tester) async {
      await _pump(tester);
      await tester.enterText(find.byType(TextField), 'send from button');
      await tester.tap(find.byType(TextField));
      await tester.pump();

      final fieldBefore = tester.widget<TextField>(find.byType(TextField));
      expect(fieldBefore.focusNode!.hasFocus, isTrue);

      await tester.tap(find.byKey(const ValueKey('composer_text_send_layer')));
      await tester.pump();

      final fieldAfter = tester.widget<TextField>(find.byType(TextField));
      expect(fieldAfter.focusNode!.hasFocus, isTrue);
      expect(fieldAfter.controller!.text, isEmpty);
    },
  );

  testWidgets(
    'action panel tap stays inside composer tap region and keeps focus',
    (tester) async {
      await _pump(tester);
      await tester.enterText(find.byType(TextField), 'keep keyboard');
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
      await tester.pumpAndSettle();

      expect(find.byType(ChatActionTiles), findsOneWidget);
      final fieldBefore = tester.widget<TextField>(find.byType(TextField));
      expect(fieldBefore.focusNode!.hasFocus, isTrue);

      final actionPanelTopLeft = tester.getTopLeft(
        find.byType(ChatActionTiles),
      );
      await tester.tapAt(actionPanelTopLeft + const Offset(4, 4));
      await tester.pump();

      final fieldAfter = tester.widget<TextField>(find.byType(TextField));
      expect(fieldAfter.focusNode!.hasFocus, isTrue);
    },
  );

  testWidgets(
    'emoji toggle keeps the lower action panel visible when opening emoji',
    (tester) async {
      final state = await _pump(tester);
      await tester.enterText(find.byType(TextField), 'stack panels');
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
      await tester.pumpAndSettle();

      expect(state.isActionPanelOpenForTest, isTrue);
      expect(find.byType(ChatActionTiles), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('composer-emoji-toggle')));
      await tester.pumpAndSettle();

      expect(state.isActionPanelOpenForTest, isTrue);
      expect(find.byType(ChatActionTiles), findsOneWidget);
      expect(find.byType(FireplaceEmojiPicker), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isFalse,
      );
    },
  );

  testWidgets(
    'action panel toggle keeps the emoji panel visible when opening actions',
    (tester) async {
      final state = await _pump(tester);
      await _openEmojiPanel(tester);

      await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
      await tester.pumpAndSettle();

      expect(state.isActionPanelOpenForTest, isTrue);
      expect(find.byType(ChatActionTiles), findsOneWidget);
      expect(find.byType(FireplaceEmojiPicker), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isFalse,
      );
    },
  );

  testWidgets(
    'plain outside tap closes the action panel and unfocuses composer',
    (tester) async {
      final state = await _pumpWithPlainOutsideSurface(tester);
      await tester.enterText(find.byType(TextField), 'outside dismisses');
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
      await tester.pumpAndSettle();

      expect(state.isActionPanelOpenForTest, isTrue);
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue,
      );

      await tester.tap(find.byKey(const ValueKey('plain-outside-surface')));
      await tester.pumpAndSettle();

      expect(state.isActionPanelOpenForTest, isFalse);
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isFalse,
      );
    },
  );

  // 2026-07-07 ruling: a chat-surface tap with the lower action panel open now
  // ALWAYS dismisses the keyboard, while the panel itself survives (only the
  // panel is exempt from the tap). The unfocus is gated to non-iOS-WebKit; on
  // the VM isIOSWebKit() is false, so this exercises the Android/desktop path.
  testWidgets(
    'chat surface tap keeps the action panel but dismisses the keyboard (non-iOS)',
    (tester) async {
      final state = await _pumpWithChatSurface(tester);
      await tester.enterText(find.byType(TextField), 'keep lower panel stable');
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
      await tester.pumpAndSettle();

      expect(state.isActionPanelOpenForTest, isTrue);
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('chat-surface')));
      await tester.pumpAndSettle();

      // Panel survives the tap; the keyboard is dismissed (field unfocused).
      expect(state.isActionPanelOpenForTest, isTrue);
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isFalse,
      );
    },
  );

  testWidgets(
    'chat surface tap closes emoji while keeping the action panel visible',
    (tester) async {
      final state = await _pumpWithChatSurface(tester);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-emoji-toggle')));
      await tester.pumpAndSettle();

      expect(state.isActionPanelOpenForTest, isTrue);
      expect(find.byType(ChatActionTiles), findsOneWidget);
      expect(find.byType(FireplaceEmojiPicker), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('chat-surface')));
      await tester.pumpAndSettle();

      expect(state.isActionPanelOpenForTest, isTrue);
      expect(find.byType(ChatActionTiles), findsOneWidget);
      expect(find.byType(FireplaceEmojiPicker), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isFalse,
      );
    },
  );

  // System back with the panel open must be consumed by the panel
  // (Telegram/Signal parity); only the next back leaves the chat route.
  testWidgets('system back closes the emoji panel before popping the route', (
    tester,
  ) async {
    final key = GlobalKey<ChatInputBarState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: RpgTheme.themeDataLight,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const Scaffold(body: Center(child: Text('conversations-root'))),
      ),
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: _providerScope(child: ChatInputBar(key: key)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openEmojiPanel(tester);

    // First back: consumed by the panel — the chat route must survive.
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(find.byType(FireplaceEmojiPicker), findsNothing);
    expect(find.byType(ChatInputBar), findsOneWidget);

    // Second back: nothing left to close, the route pops normally.
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(find.byType(ChatInputBar), findsNothing);
    expect(find.text('conversations-root'), findsOneWidget);
  });

  // Sending from the emoji panel keeps the panel up and the keyboard down:
  // no refocus may sneak in (a refocus would also close the panel via the
  // focus-gain listener).
  testWidgets('send with the emoji panel open keeps it open and unfocused', (
    tester,
  ) async {
    final state = await _pump(tester);
    await tester.enterText(find.byType(TextField), 'from the panel');
    await _openEmojiPanel(tester);

    state.sendForTest();
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(find.byType(FireplaceEmojiPicker), findsOneWidget);
    expect(field.focusNode!.hasFocus, isFalse);
    // Draft consumed proves the send actually ran (not an early no-op return).
    expect(field.controller!.text, isEmpty);
  });

  testWidgets(
    'chat surface tap closes emoji panel and leaves composer unfocused',
    (tester) async {
      await _pumpWithChatSurface(tester);
      await _openEmojiPanel(tester);

      await tester.tap(find.byKey(const ValueKey('chat-surface')));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(find.byType(FireplaceEmojiPicker), findsNothing);
      expect(field.focusNode!.hasFocus, isFalse);
    },
  );

  // Recording replaces the composer row; a stacked emoji panel must drop
  // with it (mic tap dismisses the panel, Telegram parity).
  testWidgets('starting voice recording closes the emoji panel', (
    tester,
  ) async {
    final state = await _pump(tester);
    await _openEmojiPanel(tester);

    state.setRecordingForTest(true);
    await tester.pump();

    expect(find.byType(FireplaceEmojiPicker), findsNothing);
  });

  // D2 fix: MediaQuery.viewInsets reads 0 on iOS WebKit with the keyboard up,
  // so keyboardVisible folds in the shared visualViewport inset. The ergonomic
  // bottom buffer (driven by bottomInteractivePadding, which also sizes the
  // always-mounted ChatActionTiles) must collapse to 0 when that inset is up,
  // otherwise the filler renders underneath the raised keyboard.
  testWidgets('a raised web keyboard inset removes the ergonomic bottom buffer', (
    tester,
  ) async {
    double buffer() => tester
        .widget<ChatActionTiles>(find.byType(ChatActionTiles))
        .bottomPadding;

    // Keyboard down, bottom safe-area inset present -> ergonomic buffer applied.
    await _pumpWithBottomInset(tester);
    expect(buffer(), greaterThan(0));

    // Same layout, but the shared source reports a keyboard while viewInsets
    // still reads 0: the buffer must be suppressed.
    setSharedKeyboardInsetSourceForTest(_FakeInsetSource(300));
    await _pumpWithBottomInset(tester);
    expect(buffer(), 0);
  });
}

/// Fake iOS-WebKit shared inset source (isActive true) with a fixed inset, so
/// the keyboardVisible fold-in can be exercised on the VM.
class _FakeInsetSource implements KeyboardInsetSource {
  _FakeInsetSource(double initial) : _inset = ValueNotifier<double>(initial);

  final ValueNotifier<double> _inset;

  @override
  ValueNotifier<double> get inset => _inset;

  @override
  bool get isActive => true;

  @override
  void dispose() {}
}
