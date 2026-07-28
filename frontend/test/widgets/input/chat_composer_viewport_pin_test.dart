import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/widgets/input/chat_composer_viewport.dart';
import 'package:fireplace/widgets/input/composer_keyboard_signals.dart';

// Key on the composer child so the composer's own Positioned can be located via
// find.ancestor (the message list's Positioned.fill is a sibling, not an
// ancestor, and the diagnostics overlay never mounts off iOS WebKit).
const _composerKey = Key('pin-test-composer');

void main() {
  // composerBottomPanelPinned is a process-global singleton shared by every
  // ChatComposerViewport. A leaked `true` would silently pin later composer
  // tests to bottom:0; always restore the default false after each test.
  tearDown(() => composerBottomPanelPinned.value = false);

  testWidgets(
      'unpinned composer sits at the keyboard inset; pinning drops it to bottom:0',
      (tester) async {
    composerBottomPanelPinned.value = false;
    await tester.pumpWidget(_pinHarness(300));
    await tester.pumpAndSettle();

    expect(_composerBottom(tester), moreOrLessEquals(300, epsilon: 0.01));

    composerBottomPanelPinned.value = true;
    await tester.pump();

    expect(_composerBottom(tester), moreOrLessEquals(0, epsilon: 0.01));
  });

  testWidgets(
      'pinning shrinks the list bottom padding by exactly the keyboard inset',
      (tester) async {
    composerBottomPanelPinned.value = false;
    var padding = 0.0;
    await tester.pumpWidget(_pinHarness(300, onPadding: (p) => padding = p));
    await tester.pumpAndSettle();
    final unpinnedPadding = padding;

    composerBottomPanelPinned.value = true;
    await tester.pump();
    final pinnedPadding = padding;

    // The pin removes the keyboard inset from the composer position, so the
    // clearance handed to the message list drops by exactly that inset (300),
    // independent of the measured composer height.
    expect(
      unpinnedPadding - pinnedPadding,
      moreOrLessEquals(300, epsilon: 0.01),
    );
  });

  testWidgets(
      'with no keyboard inset the composer stays at bottom:0 whether pinned or not',
      (tester) async {
    composerBottomPanelPinned.value = false;
    await tester.pumpWidget(_pinHarness(0));
    await tester.pumpAndSettle();
    expect(_composerBottom(tester), moreOrLessEquals(0, epsilon: 0.01));

    composerBottomPanelPinned.value = true;
    await tester.pump();
    expect(_composerBottom(tester), moreOrLessEquals(0, epsilon: 0.01));
  });
}

double _composerBottom(WidgetTester tester) {
  final positioned = tester.widget<Positioned>(
    find
        .ancestor(
          of: find.byKey(_composerKey),
          matching: find.byType(Positioned),
        )
        .first,
  );
  return positioned.bottom!;
}

Widget _pinHarness(double inset, {ValueChanged<double>? onPadding}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(viewInsets: EdgeInsets.only(bottom: inset)),
        child: Scaffold(
          // Production uses resizeToAvoidBottomInset:false so the composer
          // viewport owns the keyboard inset; default true would let Scaffold
          // consume the bottom inset before the viewport reads it.
          resizeToAvoidBottomInset: false,
          body: ChatComposerViewport(
            messageListBuilder: (bottom) {
              onPadding?.call(bottom);
              return ListView(
                reverse: true,
                padding: EdgeInsets.only(bottom: bottom),
                children: const [Text('m')],
              );
            },
            composer: const SizedBox(
              key: _composerKey,
              height: 48,
              child: ColoredBox(color: Color(0xFFFF0000)),
            ),
          ),
        ),
      ),
    ),
  );
}
