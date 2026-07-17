import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/theme/glass_theme.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/starfield_background.dart';

// --- WCAG contrast helpers (sRGB) ---------------------------------------------
double _lin(double c) {
  c /= 255.0;
  return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double _lum(Color c) =>
    0.2126 * _lin((c.r * 255).roundToDouble()) +
    0.7152 * _lin((c.g * 255).roundToDouble()) +
    0.0722 * _lin((c.b * 255).roundToDouble());

double _contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// Composite [fg] at [alpha] over opaque [bg] in sRGB (how the canvas paints).
Color _over(Color fg, double alpha, Color bg) => Color.fromARGB(
      255,
      ((fg.r * 255) * alpha + (bg.r * 255) * (1 - alpha)).round(),
      ((fg.g * 255) * alpha + (bg.g * 255) * (1 - alpha)).round(),
      ((fg.b * 255) * alpha + (bg.b * 255) * (1 - alpha)).round(),
    );

void main() {
  const base = RpgTheme.messagesAreaBgCosmic; // #04060C starfield base
  const starTint = Color(0xFFBEDCF0); // 190,220,240
  // Twinkle alpha range from drawStars: 0.22 (dimmest) .. 0.67 (brightest).
  const dimStar = 0.22, brightStar = 0.67;

  group('cosmic starfield contrast (darkest AND brightest moments)', () {
    test('opaque bubbles hold ≥4.5:1 regardless of stars', () {
      // Bubbles are opaque content painted ON TOP of the field, so star
      // brightness cannot affect them — but assert the palette anyway.
      expect(_contrast(Colors.white, RpgTheme.mineMsgBgCosmic),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(const Color(0xFFCFE2F2), RpgTheme.theirsMsgBgCosmic),
          greaterThanOrEqualTo(4.5));
    });

    test('glass chrome text holds ≥4.5:1 over a full-bright star', () {
      // Worst case: a max-alpha star fully behind glass text, then the glass
      // fill composited over it. (Blur would only average this DOWN.)
      for (final starAlpha in [dimStar, brightStar]) {
        final backdrop = _over(starTint, starAlpha, base);
        final glass = GlassTheme.cosmic;
        final glassPixel = _over(glass.fill, glass.fill.a, backdrop);
        expect(_contrast(glass.onGlassMuted, glassPixel),
            greaterThanOrEqualTo(4.5),
            reason: 'onGlassMuted over star=$starAlpha');
        expect(_contrast(glass.onGlassAccent, glassPixel),
            greaterThanOrEqualTo(4.5),
            reason: 'onGlassAccent over star=$starAlpha');
      }
    });

    test('date pill text holds ≥4.5:1 over a full-bright star', () {
      final glass = GlassTheme.cosmic;
      final backdrop = _over(starTint, brightStar, base);
      final pill = _over(glass.datePillBg, glass.datePillBg.a, backdrop);
      expect(_contrast(glass.datePillText, pill), greaterThanOrEqualTo(4.5));
    });
  });

  group('StarfieldBackground motion gating', () {
    Widget wrap({required bool reduceMotion}) => MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: StarfieldBackground(starColor: starTint, density: 40),
          ),
        );

    testWidgets('animates when reduced-motion is OFF', (tester) async {
      await tester.pumpWidget(wrap(reduceMotion: false));
      await tester.pump();
      // A running Ticker keeps requesting frames.
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pumpWidget(const SizedBox()); // dispose ticker
    });

    testWidgets('is STATIC when reduced-motion is ON', (tester) async {
      await tester.pumpWidget(wrap(reduceMotion: true));
      await tester.pump();
      // No ticker started -> no continuously scheduled frames.
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });
}
