import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/glass/glass_bottom_nav.dart';

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

  group('the selection pulse', () {
    testWidgets('plays on the newly selected glyph and settles back to 1', (
      tester,
    ) async {
      await tester.pumpWidget(const _SwitchableHost());

      expect(_glyphScale(tester, 'Contacts'), closeTo(1, 0.001));

      await tester.tap(find.text('Contacts'));
      await tester.pump();

      // Sample the whole pulse window rather than one frame: the contract is
      // "it visibly moves and then settles", not "it is at 0.94 at t=60ms",
      // which would only pin this test to the current frame cadence.
      var peakDeviation = 0.0;
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        final d = (_glyphScale(tester, 'Contacts') - 1).abs();
        if (d > peakDeviation) peakDeviation = d;
      }
      expect(
        peakDeviation,
        greaterThan(0.02),
        reason: 'the selected glyph must visibly pulse',
      );

      await tester.pumpAndSettle();
      expect(
        _glyphScale(tester, 'Contacts'),
        closeTo(1, 0.001),
        reason: 'the pulse must land on exactly 1.0, with no residual spring',
      );
    });

    testWidgets('a glyph deselected mid-pulse resets instead of animating', (
      tester,
    ) async {
      await tester.pumpWidget(const _SwitchableHost());

      await tester.tap(find.text('Contacts'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));

      // Leave for another tab while Contacts is still mid-pulse. Sample the
      // remainder of its window: a single frame lands in a dead spot where an
      // un-reset controller happens to read 1.0 anyway.
      await tester.tap(find.text('Settings'));
      await tester.pump();
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        expect(
          _glyphScale(tester, 'Contacts'),
          closeTo(1, 0.001),
          reason: 'a muted glyph must not keep animating',
        );
      }
    });

    testWidgets('reduce motion skips the pulse entirely', (tester) async {
      await tester.pumpWidget(const _SwitchableHost(disableAnimations: true));

      await tester.tap(find.text('Contacts'));
      await tester.pump();
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        expect(
          _glyphScale(tester, 'Contacts'),
          closeTo(1, 0.001),
          reason: 'no frame may scale the glyph under reduce-motion',
        );
      }
    });
  });
}

/// Scale currently applied to one destination's glyph by the pulse.
double _glyphScale(WidgetTester tester, String label) {
  final column = find
      .ancestor(of: find.text(label), matching: find.byType(Column))
      .first;
  final transform = tester.widget<Transform>(
    find.descendant(of: column, matching: find.byType(Transform)).first,
  );
  return transform.transform.getMaxScaleOnAxis();
}

/// Selection has to really change for the pulse to fire, so these tests need
/// a host that owns the index rather than the fixed-index `_host`.
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
