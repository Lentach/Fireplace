import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fireplace/utils/web_focus_guard.dart';
import 'package:fireplace/widgets/input/focus_guard_area.dart';

void main() {
  setUp(() {
    // Force the active path on the VM, where kIsWeb / isIOSWebKit are false.
    FocusGuardArea.debugForceActiveForTest = true;
  });

  tearDown(() {
    FocusGuardArea.debugForceActiveForTest = false;
    resetFocusGuardHooksForTest();
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
}
