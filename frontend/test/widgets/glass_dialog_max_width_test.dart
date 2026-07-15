import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/glass/glass_surface.dart';
import 'package:fireplace/widgets/glass/glass_dialog.dart';

void main() {
  Future<void> pumpDialog(WidgetTester tester, {double? maxWidth}) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: RpgTheme.themeDataLight,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => maxWidth == null
                  ? const GlassDialog(title: Text('t'))
                  : GlassDialog(maxWidth: maxWidth, title: const Text('t')),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder inDialog(Type type) =>
      find.descendant(of: find.byType(Dialog), matching: find.byType(type));

  testWidgets('explicit maxWidth caps the glass surface on wide layouts', (
    tester,
  ) async {
    await pumpDialog(tester, maxWidth: 400);
    final width = tester.getSize(find.byType(GlassSurface)).width;
    expect(width, lessThanOrEqualTo(400));
  });

  testWidgets('default maxWidth caps at 560 instead of the inset width', (
    tester,
  ) async {
    await pumpDialog(tester);
    final width = tester.getSize(find.byType(GlassSurface)).width;
    expect(width, lessThanOrEqualTo(560));
  });

  testWidgets('entrance scale animation mounts by default', (tester) async {
    await pumpDialog(tester);
    expect(inDialog(TweenAnimationBuilder<double>), findsOneWidget);
  });

  testWidgets('reduce-motion skips the entrance animation', (tester) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );
    await pumpDialog(tester);
    expect(inDialog(TweenAnimationBuilder<double>), findsNothing);
  });
}
