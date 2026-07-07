import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/widgets/input/chat_composer_viewport.dart';
import 'package:fireplace/widgets/input/composer_keyboard_signals.dart';
import 'package:fireplace/utils/web_keyboard_inset.dart';

void main() {
  // Every global the viewport reads is a process-wide singleton; a leaked
  // value silently drives later tests. Reset all of them plus the shared-source
  // override after each test.
  tearDown(() {
    composerKeyboardCollapseGuard.value = false;
    composerBottomPanelPinned.value = false;
    setSharedKeyboardInsetSourceForTest(null);
  });

  testWidgets('applies list bottom padding at least composer height', (
    tester,
  ) async {
    double? capturedPadding;

    await tester.pumpWidget(
      MaterialApp(
        home: ChatComposerViewport(
          messageListBuilder: (bottom) {
            capturedPadding = bottom;
            return ListView(
              reverse: true,
              padding: EdgeInsets.only(bottom: bottom),
              children: const [Text('msg')],
            );
          },
          composer: const SizedBox(
            height: 48,
            child: ColoredBox(color: Colors.red),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(capturedPadding, isNotNull);
    expect(capturedPadding!, greaterThanOrEqualTo(48));
  });

  testWidgets('increases list bottom padding when composer grows', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _GrowingComposerHarness()));
    await tester.pumpAndSettle();

    final listViewBefore = tester.widget<ListView>(find.byType(ListView));
    final paddingBefore = listViewBefore.padding as EdgeInsets;
    expect(paddingBefore.bottom, greaterThanOrEqualTo(48));

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();

    final listViewAfter = tester.widget<ListView>(find.byType(ListView));
    final paddingAfter = listViewAfter.padding as EdgeInsets;
    expect(paddingAfter.bottom, greaterThan(paddingBefore.bottom));
  });

  testWidgets('genuine dismiss collapses the keyboard inset immediately', (
    tester,
  ) async {
    composerKeyboardCollapseGuard.value = false;
    var padding = 0.0;
    await tester.pumpWidget(_insetHarness(300, onPadding: (p) => padding = p));
    await tester.pumpAndSettle();
    expect(padding, greaterThanOrEqualTo(48 + 300));

    await tester.pumpWidget(_insetHarness(0, onPadding: (p) => padding = p));
    await tester.pump(); // no timer wait — collapse must be immediate
    expect(padding, lessThan(48 + 300));
    expect(padding, greaterThanOrEqualTo(48));
  });

  testWidgets('send bounce defers the collapse for the debounce window', (
    tester,
  ) async {
    composerKeyboardCollapseGuard.value = true;
    var padding = 0.0;
    await tester.pumpWidget(_insetHarness(300, onPadding: (p) => padding = p));
    await tester.pumpAndSettle();
    expect(padding, greaterThanOrEqualTo(48 + 300));

    await tester.pumpWidget(_insetHarness(0, onPadding: (p) => padding = p));
    await tester.pump(const Duration(milliseconds: 100));
    expect(padding, greaterThanOrEqualTo(48 + 300)); // deferred: no drop/flash

    await tester.pump(const Duration(milliseconds: 500));
    expect(padding, lessThan(48 + 300)); // collapsed after the 450ms debounce
  });

  testWidgets(
    'active shared source inset drives layout while MediaQuery inset stays 0',
    (tester) async {
      // iOS WebKit reports MediaQuery.viewInsets.bottom = 0 with the keyboard
      // up, so the composer must follow the visualViewport-derived shared
      // source instead (the max(flutterInset, sharedInset) branch).
      final fake = _FakeInsetSource(350);
      setSharedKeyboardInsetSourceForTest(fake);
      var padding = 0.0;
      await tester.pumpWidget(_insetHarness(0, onPadding: (p) => padding = p));
      await tester.pumpAndSettle();

      expect(_composerBottom(tester), moreOrLessEquals(350, epsilon: 0.01));
      // List clearance folds the same inset in on top of the composer height.
      expect(padding, greaterThanOrEqualTo(48 + 350 - 0.01));
    },
  );

  testWidgets(
    'bounce self-correct: a keyboard returning within the debounce window never drops the composer',
    (tester) async {
      composerKeyboardCollapseGuard.value = true;
      await tester.pumpWidget(_insetHarness(300, onPadding: (_) {}));
      await tester.pumpAndSettle();
      expect(_composerBottom(tester), moreOrLessEquals(300, epsilon: 0.01));

      // Keyboard blips down (iOS send-button bounce); guard armed -> deferred.
      await tester.pumpWidget(_insetHarness(0, onPadding: (_) {}));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_composerBottom(tester), moreOrLessEquals(300, epsilon: 0.01));

      // Keyboard returns before the 450ms window elapses.
      await tester.pumpWidget(_insetHarness(300, onPadding: (_) {}));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_composerBottom(tester), moreOrLessEquals(300, epsilon: 0.01));

      // The deferred collapse timer now fires, but the live inset re-grows in
      // the same build: the composer must never have dropped below 300.
      await tester.pump(const Duration(milliseconds: 500));
      expect(_composerBottom(tester), moreOrLessEquals(300, epsilon: 0.01));
    },
  );
}

class _GrowingComposerHarness extends StatefulWidget {
  const _GrowingComposerHarness();

  @override
  State<_GrowingComposerHarness> createState() =>
      _GrowingComposerHarnessState();
}

class _GrowingComposerHarnessState extends State<_GrowingComposerHarness> {
  double _composerHeight = 48;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ChatComposerViewport(
        messageListBuilder: (bottom) => ListView(
          reverse: true,
          padding: EdgeInsets.only(bottom: bottom),
          children: const [Text('msg')],
        ),
        composer: SizedBox(
          height: _composerHeight,
          child: const ColoredBox(color: Colors.red),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => setState(() => _composerHeight = 120),
        child: const Icon(Icons.expand_more),
      ),
    );
  }
}

Widget _insetHarness(double inset, {required ValueChanged<double> onPadding}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(viewInsets: EdgeInsets.only(bottom: inset)),
        child: Scaffold(
          // Production uses resizeToAvoidBottomInset:false so the composer
          // viewport owns the keyboard inset; default true would let Scaffold
          // consume the bottom inset before the viewport reads it.
          resizeToAvoidBottomInset: false,
          body: ChatComposerViewport(
            messageListBuilder: (bottom) {
              onPadding(bottom);
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

const _composerKey = Key('viewport-test-composer');

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

/// Fake iOS-WebKit shared inset source: [isActive] true with a caller-driven
/// inset, so the viewport's visualViewport branch is exercisable on the VM.
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
