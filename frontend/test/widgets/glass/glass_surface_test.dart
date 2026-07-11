import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fireplace/theme/glass_theme.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/glass/glass_surface.dart';

Widget _host(Widget child, {bool highContrast = false, ThemeData? theme}) {
  return MaterialApp(
    theme: theme ?? RpgTheme.themeDataDarkGray,
    home: MediaQuery(
      data: MediaQueryData(highContrast: highContrast),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  group('GlassTheme wiring', () {
    testWidgets('all four ThemeDatas carry a GlassTheme extension',
        (tester) async {
      final themes = {
        'blue': (RpgTheme.themeDataBlue, GlassTheme.blue),
        'dark': (RpgTheme.themeDataDarkGray, GlassTheme.dark),
        'light': (RpgTheme.themeDataLight, GlassTheme.light),
        'teal': (RpgTheme.themeDataTealStone, GlassTheme.teal),
      };
      for (final entry in themes.entries) {
        final (themeData, expected) = entry.value;
        await tester.pumpWidget(MaterialApp(
          theme: themeData,
          home: const SizedBox(),
        ));
        // Let the animated theme transition finish; lerp holds the previous
        // theme's extension mid-flight.
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(SizedBox));
        final resolved = GlassTheme.of(context);
        expect(resolved.fill, expected.fill,
            reason: 'theme ${entry.key} must expose its GlassTheme');
        expect(resolved.opaqueFill, expected.opaqueFill);
      }
    });
  });

  group('GlassTheme.lerp', () {
    test('interpolates colors field-wise at the midpoint', () {
      final mid = GlassTheme.dark.lerp(GlassTheme.light, 0.5);
      expect(mid.fill,
          Color.lerp(GlassTheme.dark.fill, GlassTheme.light.fill, 0.5));
      expect(
          mid.onGlassMuted,
          Color.lerp(GlassTheme.dark.onGlassMuted,
              GlassTheme.light.onGlassMuted, 0.5));
      expect(
          mid.shadow,
          BoxShadow.lerp(
              GlassTheme.dark.shadow, GlassTheme.light.shadow, 0.5));
    });
  });

  group('GlassSurface', () {
    testWidgets('renders a backdrop blur with translucent fill by default',
        (tester) async {
      await tester.pumpWidget(_host(
        const GlassPill(height: 66, child: SizedBox(width: 200)),
      ));

      expect(find.byType(BackdropFilter), findsOneWidget);
      final container = tester.widget<Container>(find.descendant(
        of: find.byType(GlassSurface),
        matching: find.byType(Container),
      ));
      final deco = container.decoration! as BoxDecoration;
      expect(deco.color, GlassTheme.dark.fill);
      expect(deco.color!.a, lessThan(1.0),
          reason: 'glass fill must be translucent');
    });

    testWidgets('high-contrast media query forces the opaque fallback',
        (tester) async {
      await tester.pumpWidget(_host(
        const GlassPill(height: 66, child: SizedBox(width: 200)),
        highContrast: true,
      ));

      expect(find.byType(BackdropFilter), findsNothing);
      final container = tester.widget<Container>(find.descendant(
        of: find.byType(GlassSurface),
        matching: find.byType(Container),
      ));
      final deco = container.decoration! as BoxDecoration;
      expect(deco.color, GlassTheme.dark.opaqueFill);
      expect(deco.color!.a, 1.0, reason: 'fallback fill must be opaque');
    });

    testWidgets('geometry is identical between glass and fallback modes',
        (tester) async {
      await tester.pumpWidget(_host(
        const GlassPill(height: 66, width: 220),
      ));
      final glassSize = tester.getSize(find.byType(GlassSurface));

      await tester.pumpWidget(_host(
        const GlassPill(height: 66, width: 220),
        highContrast: true,
      ));
      expect(tester.getSize(find.byType(GlassSurface)), glassSize,
          reason: 'glass is paint, not layout: fallback must not resize');
    });

    testWidgets('blur sigma matches the accepted spec', (tester) async {
      await tester.pumpWidget(_host(
        const GlassCircle(size: 52),
      ));
      final filterWidget =
          tester.widget<BackdropFilter>(find.byType(BackdropFilter));
      // toString is repr-dependent but the only window into a composed
      // ImageFilter's sigma; breaks loudly if the recipe drifts from σ22.
      expect(filterWidget.filter.toString(), contains('blur(22.0, 22.0'));
    });
  });
}
