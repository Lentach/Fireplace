import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/glass/glass_bottom_nav.dart';
import 'package:fireplace/widgets/icon_selection.dart';

Widget _host({required int index, required ValueChanged<int> onTap}) {
  return MaterialApp(
    theme: RpgTheme.themeDataDarkGray,
    home: Scaffold(
      bottomNavigationBar: GlassBottomNav(
        currentIndex: index,
        onTap: onTap,
        destinations: const [
          GlassNavDestination(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Chat',
          ),
          GlassNavDestination(
            icon: Icon(Icons.people_outline),
            label: 'Contacts',
          ),
          GlassNavDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('tapping a destination reports its index', (tester) async {
    int? tapped;
    await tester.pumpWidget(_host(index: 0, onTap: (i) => tapped = i));

    await tester.tap(find.text('Contacts'));
    expect(tapped, 1);

    await tester.tap(find.text('Settings'));
    expect(tapped, 2);
  });

  testWidgets('exactly one destination is marked selected for semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(index: 1, onTap: (_) {}));

    expect(
      tester.getSemantics(find.bySemanticsLabel('Contacts')),
      matchesSemantics(
        label: 'Contacts',
        isSelected: true,
        isButton: true,
        hasSelectedState: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Chat')),
      matchesSemantics(
        label: 'Chat',
        isSelected: false,
        isButton: true,
        hasSelectedState: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('semantics tap action activates the destination', (tester) async {
    int? tapped;
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(index: 0, onTap: (i) => tapped = i));

    final node = tester.getSemantics(find.bySemanticsLabel('Settings'));
    node.owner!.performAction(node.id, SemanticsAction.tap);
    expect(tapped, 2);
    handle.dispose();
  });

  testWidgets('keyboard focus + Enter activates a destination', (tester) async {
    int? tapped;
    await tester.pumpWidget(_host(index: 0, onTap: (i) => tapped = i));

    // Tab into the first destination's InkWell, then activate with Enter.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.context?.widget, isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(tapped, 0, reason: 'Enter on the focused destination must tap it');
  });

  testWidgets('every destination hit target is at least 48x48', (tester) async {
    await tester.pumpWidget(_host(index: 0, onTap: (_) {}));
    for (final label in ['Chat', 'Contacts', 'Settings']) {
      final size = tester.getSize(
        find.ancestor(of: find.text(label), matching: find.byType(InkWell)),
      );
      expect(size.height, greaterThanOrEqualTo(48), reason: label);
      expect(size.width, greaterThanOrEqualTo(48), reason: label);
    }
  });

  group('the selection entrance', () {
    testWidgets('runs on the newly selected destination and completes', (
      tester,
    ) async {
      await tester.pumpWidget(const _SwitchableHost());

      expect(
        _selectionOf(tester, 'Contacts').progress,
        0,
        reason: 'a destination at rest shows none of the active mark',
      );
      expect(
        _selectionOf(tester, 'Chat').progress,
        1,
        reason: 'the selected destination shows all of it',
      );

      await tester.tap(find.text('Contacts'));
      await tester.pump();

      // Sample the whole window: the contract is "it starts undrawn, is
      // partway through at some point, and finishes", not a value at one
      // frame, which would only pin the test to the current frame cadence.
      var sawPartial = false;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        final p = _selectionOf(tester, 'Contacts').progress;
        if (p > 0 && p < 1) sawPartial = true;
      }
      expect(
        sawPartial,
        isTrue,
        reason: 'the selected glyph must visibly draw on',
      );

      await tester.pumpAndSettle();
      expect(_selectionOf(tester, 'Contacts').progress, 1);
    });

    testWidgets('the outgoing destination retracts rather than snapping', (
      tester,
    ) async {
      await tester.pumpWidget(const _SwitchableHost());

      await tester.tap(find.text('Contacts'));
      await tester.pumpAndSettle();
      expect(_selectionOf(tester, 'Contacts').progress, 1);

      // Both halves of the handoff animate: leaving Contacts must sweep its
      // active mark back off, not cut to the resting state in one frame.
      await tester.tap(find.text('Settings'));
      await tester.pump();
      var sawPartial = false;
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        final p = _selectionOf(tester, 'Contacts').progress;
        if (p > 0 && p < 1) sawPartial = true;
      }
      expect(
        sawPartial,
        isTrue,
        reason: 'the tab you left must retract, not snap',
      );

      await tester.pumpAndSettle();
      expect(_selectionOf(tester, 'Contacts').progress, 0);
      expect(_selectionOf(tester, 'Settings').progress, 1);
    });

    testWidgets('the lens delivers it — the incoming tab waits', (
      tester,
    ) async {
      await tester.pumpWidget(const _SwitchableHost());

      await tester.tap(find.text('Contacts'));
      await tester.pump();

      // 100ms in: short of the gate at kDrawOnStart of a 400ms entrance, and
      // far enough from it that a frame either way cannot cross it.
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        _selectionOf(tester, 'Contacts').progress,
        0,
        reason: 'the tab you chose stays dark until the lens is nearly there',
      );
      expect(
        _lensX(tester),
        greaterThan(_slotX(tester, 'Chat') + 1),
        reason:
            'the lens is already travelling — the wait is a handoff, not '
            'a stalled first beat',
      );
      expect(
        _selectionOf(tester, 'Chat').progress,
        lessThan(1),
        reason:
            'and the tab you left clears immediately, which is what keeps '
            'the tap acknowledged while the incoming one waits',
      );

      // Past the gate it draws, and it is whole by the end of the entrance.
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        _selectionOf(tester, 'Contacts').progress,
        greaterThan(0),
        reason: 'once the lens has arrived the tab lights up',
      );
      await tester.pumpAndSettle();
      expect(_selectionOf(tester, 'Contacts').progress, 1);
    });

    testWidgets('reduce motion skips the transition entirely', (tester) async {
      await tester.pumpWidget(const _SwitchableHost(disableAnimations: true));

      await tester.tap(find.text('Contacts'));
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        expect(
          _selectionOf(tester, 'Contacts').progress,
          1,
          reason: 'the new tab is immediately whole under reduce-motion',
        );
        expect(
          _selectionOf(tester, 'Chat').progress,
          0,
          reason: 'and the old one is immediately at rest',
        );
      }
    });
  });

  group('the travelling lens', () {
    testWidgets('docks on the selected slot', (tester) async {
      await tester.pumpWidget(const _SwitchableHost());
      expect(_lensX(tester), closeTo(_slotX(tester, 'Chat'), 0.5));

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(_lensX(tester), closeTo(_slotX(tester, 'Settings'), 0.5));
    });

    testWidgets('travels through the slot it skips', (tester) async {
      await tester.pumpWidget(const _SwitchableHost());
      final middle = _slotX(tester, 'Contacts');
      final start = _slotX(tester, 'Chat');
      final end = _slotX(tester, 'Settings');

      // Chats -> Settings skips Contacts. The lens must sweep over it rather
      // than jump, which is the whole reason this reads as travel.
      //
      // Asserted as samples landing on BOTH sides of the skipped slot, not as
      // a sample near it: the sweep covers ~50px per frame at peak, so any
      // narrow window around the midpoint is jumped straight over and the
      // test would fail on a perfectly good animation.
      await tester.tap(find.text('Settings'));
      await tester.pump();
      var before = false;
      var after = false;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        final x = _lensX(tester);
        if (x > start + 1 && x < middle) before = true;
        if (x > middle && x < end - 1) after = true;
      }
      expect(
        before && after,
        isTrue,
        reason: 'the lens must sweep across the skipped slot, not jump to it',
      );

      await tester.pumpAndSettle();
      expect(_lensX(tester), closeTo(end, 0.5));
    });

    testWidgets('elongates while it travels and settles back to its slot', (
      tester,
    ) async {
      await tester.pumpWidget(const _SwitchableHost());
      final resting = _lensSize(tester);

      await tester.tap(find.text('Contacts'));
      await tester.pump();
      await tester.pump(GlassBottomNav.kTravelDuration ~/ 2);
      final moving = _lensSize(tester);
      expect(
        moving.width,
        greaterThan(resting.width + 1),
        reason: 'the pool stretches out at the fast part of the journey',
      );
      expect(
        moving.height,
        lessThan(resting.height - 1),
        reason:
            'and flattens as it does, so it reads as liquid holding its '
            'volume rather than a box being resized',
      );

      await tester.pumpAndSettle();
      final settled = _lensSize(tester);
      expect(settled.width, closeTo(resting.width, 0.5));
      expect(settled.height, closeTo(resting.height, 0.5));
    });

    testWidgets('reduce motion docks it instantly', (tester) async {
      await tester.pumpWidget(const _SwitchableHost(disableAnimations: true));
      await tester.tap(find.text('Settings'));
      await tester.pump();
      expect(
        _lensX(tester),
        closeTo(_slotX(tester, 'Settings'), 0.5),
        reason: 'no travel frames under reduce-motion',
      );
    });
  });
}

/// Where the travelling lens actually rendered.
double _lensX(WidgetTester tester) =>
    tester.getCenter(find.byKey(GlassBottomNav.activeLensKey)).dx;

/// How big the travelling lens actually rendered.
Size _lensSize(WidgetTester tester) =>
    tester.getSize(find.byKey(GlassBottomNav.activeLensKey));

/// The horizontal centre of one destination's slot.
double _slotX(WidgetTester tester, String label) => tester
    .getCenter(
      find.ancestor(of: find.text(label), matching: find.byType(InkWell)),
    )
    .dx;

/// The entrance published to one destination's icon.
IconSelection _selectionOf(WidgetTester tester, String label) {
  final column = find
      .ancestor(of: find.text(label), matching: find.byType(Column))
      .first;
  return tester.widget<IconSelection>(
    find.descendant(of: column, matching: find.byType(IconSelection)).first,
  );
}

/// Selection has to really change for the entrance to fire, so these tests
/// need a host that owns the index rather than the fixed-index `_host`.
class _SwitchableHost extends StatefulWidget {
  const _SwitchableHost({this.disableAnimations = false});

  final bool disableAnimations;

  @override
  State<_SwitchableHost> createState() => _SwitchableHostState();
}

class _SwitchableHostState extends State<_SwitchableHost> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: RpgTheme.themeDataDarkGray,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: widget.disableAnimations),
          child: Scaffold(
            bottomNavigationBar: GlassBottomNav(
              currentIndex: _index,
              onTap: (i) => setState(() => _index = i),
              destinations: const [
                GlassNavDestination(
                  icon: Icon(Icons.chat_bubble_outline),
                  label: 'Chat',
                ),
                GlassNavDestination(
                  icon: Icon(Icons.people_outline),
                  label: 'Contacts',
                ),
                GlassNavDestination(
                  icon: Icon(Icons.settings_outlined),
                  label: 'Settings',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
