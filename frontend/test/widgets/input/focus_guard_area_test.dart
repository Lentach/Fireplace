import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fireplace/utils/web_focus_guard.dart';
import 'package:fireplace/utils/web_keyboard_inset.dart';
import 'package:fireplace/widgets/input/focus_guard_area.dart';

void main() {
  setUp(() {
    // Force the active path on the VM, where kIsWeb / isIOSWebKit are false.
    FocusGuardArea.debugForceActiveForTest = true;
  });

  tearDown(() {
    FocusGuardArea.debugForceActiveForTest = false;
    resetFocusGuardHooksForTest();
    setSharedKeyboardInsetSourceForTest(null);
  });

  testWidgets('registers child rect on mount and unregisters on dispose',
      (tester) async {
    final registered = <String, Rect>{};
    final unregistered = <String>[];
    setFocusGuardHooksForTest(
      register: (id, rect) => registered[id] = rect,
      unregister: unregistered.add,
    );

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 48,
            height: 48,
            child: FocusGuardArea(
              id: 'composer_trailing',
              child: SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pump(); // flush the post-frame measurement

    expect(registered.containsKey('composer_trailing'), isTrue);
    expect(registered['composer_trailing']!.width, 48);
    expect(registered['composer_trailing']!.height, 48);

    // Remove the widget -> dispose -> unregister.
    await tester.pumpWidget(const SizedBox());
    expect(unregistered, contains('composer_trailing'));
  });

  testWidgets('re-registers when the child size changes', (tester) async {
    var lastRect = Rect.zero;
    setFocusGuardHooksForTest(
      register: (id, rect) => lastRect = rect,
      unregister: (_) {},
    );

    // Non-const so each pump produces a fresh FocusGuardArea that rebuilds and
    // re-measures — mirroring the composer rebuilding on every layout change.
    Widget build(double size) => Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: size,
              height: size,
              child: FocusGuardArea(
                id: 'composer_trailing',
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );

    await tester.pumpWidget(build(48));
    await tester.pump();
    expect(lastRect.width, 48);

    await tester.pumpWidget(build(64));
    await tester.pump();
    expect(lastRect.width, 64);
  });

  // P1 fix: the composer MOVES without this subtree rebuilding while the iOS
  // keyboard pans — ChatComposerViewport repositions its Positioned(bottom:)
  // per visualViewport event but reuses the same composer child instance, and
  // ChatInputBar's rebuild is gated on the inset BOOLEAN. So FocusGuardArea
  // must re-measure its rect off the shared-inset LISTENER, not off build().
  // Here the guarded child is a captured const instance: when the inset
  // changes only the Positioned wrapper rebuilds, FocusGuardArea.build is
  // skipped — any re-measure can only come from the inset listener.
  testWidgets(
    're-measures the guard rect on shared-inset events without an external rebuild',
    (tester) async {
      final source = _FakeInsetSource(0);
      setSharedKeyboardInsetSourceForTest(source);
      addTearDown(source.dispose);

      var lastRect = Rect.zero;
      var registerCalls = 0;
      setFocusGuardHooksForTest(
        register: (id, rect) {
          registerCalls++;
          lastRect = rect;
        },
        unregister: (_) {},
      );

      const guarded = FocusGuardArea(
        id: 'composer_trailing',
        child: SizedBox(width: 48, height: 48),
      );

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ValueListenableBuilder<double>(
            valueListenable: source.inset,
            child: guarded,
            builder: (context, inset, child) => Stack(
              children: [Positioned(left: 0, bottom: inset, child: child!)],
            ),
          ),
        ),
      );
      await tester.pump(); // flush the initial post-frame measurement

      expect(lastRect.width, 48);
      expect(lastRect.height, 48);
      final callsAfterMount = registerCalls;
      final initialTop = lastRect.top;

      // Push the inset WITHOUT pumping a new tree from outside. The Positioned
      // moves the child up by 300; the guard rect must follow.
      source.inset.value = 300;
      await tester.pump();

      // Re-measured off the listener (FocusGuardArea.build never re-ran).
      expect(registerCalls, greaterThan(callsAfterMount));
      expect(lastRect.top, initialTop - 300);
      expect(lastRect.height, 48);
    },
  );
}

/// Fake shared inset source backed by a mutable ValueNotifier so tests can
/// drive visualViewport-style inset events on the VM.
class _FakeInsetSource implements KeyboardInsetSource {
  _FakeInsetSource(double initial) : inset = ValueNotifier<double>(initial);

  @override
  final ValueNotifier<double> inset;

  @override
  bool get isActive => true;

  @override
  void dispose() => inset.dispose();
}
