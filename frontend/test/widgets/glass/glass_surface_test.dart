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
    testWidgets('all five themes carry a GlassTheme extension',
        (tester) async {
      final themes = {
        'blue': (RpgTheme.themeDataBlue, GlassTheme.blue),
        'dark': (RpgTheme.themeDataDarkGray, GlassTheme.dark),
        'light': (RpgTheme.themeDataLight, GlassTheme.light),
        'teal': (RpgTheme.themeDataTealStone, GlassTheme.teal),
        'cosmic': (RpgTheme.themeDataCosmic, GlassTheme.cosmic),
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
    test('interpolates every field-wise at the midpoint', () {
      const a = GlassTheme.dark;
      const b = GlassTheme.light;
      final mid = a.lerp(b, 0.5);
      // Every Color field must be the field-wise midpoint. A field added to
      // GlassTheme but forgotten in lerp would diverge here.
      expect(mid.fill, Color.lerp(a.fill, b.fill, 0.5));
      expect(mid.border, Color.lerp(a.border, b.border, 0.5));
      expect(mid.highlight, Color.lerp(a.highlight, b.highlight, 0.5));
      expect(mid.activeCapsule, Color.lerp(a.activeCapsule, b.activeCapsule, 0.5));
      expect(mid.onGlassMuted, Color.lerp(a.onGlassMuted, b.onGlassMuted, 0.5));
      expect(mid.onGlassAccent, Color.lerp(a.onGlassAccent, b.onGlassAccent, 0.5));
      expect(mid.wallpaperTint, Color.lerp(a.wallpaperTint, b.wallpaperTint, 0.5));
      expect(mid.datePillBg, Color.lerp(a.datePillBg, b.datePillBg, 0.5));
      expect(mid.datePillText, Color.lerp(a.datePillText, b.datePillText, 0.5));
      expect(mid.opaqueFill, Color.lerp(a.opaqueFill, b.opaqueFill, 0.5));
      expect(mid.shadow, BoxShadow.lerp(a.shadow, b.shadow, 0.5));
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
