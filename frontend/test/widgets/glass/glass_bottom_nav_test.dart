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

    tester.binding.pipelineOwner.semanticsOwner!.performAction(
      tester.getSemantics(find.bySemanticsLabel('Settings')).id,
      SemanticsAction.tap,
    );
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
}
