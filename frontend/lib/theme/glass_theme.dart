import 'package:flutter/material.dart';

/// Per-theme Liquid Glass values from the accepted design spec
/// (`docs/design/liquid-glass/SPEC.md` §3). Read via `GlassTheme.of(context)`.
///
/// Glass lives ONLY on floating chrome (top capsules, bottom nav pill,
/// composer pill, panels/sheets). Content (rows, bubbles) stays opaque and
/// never uses these values.
class GlassTheme extends ThemeExtension<GlassTheme> {
  /// Translucent fill painted over the blurred backdrop.
  final Color fill;

  /// 1px surface border.
  final Color border;

  /// Inner top highlight hairline.
  final Color highlight;

  /// Active-tab capsule fill (bottom nav) / active row tint.
  final Color activeCapsule;

  /// Secondary text/icons ON GLASS (nav labels, composer hint, inactive
  /// icons). Replaces the theme muted color there — contrast-gated ≥4.5:1
  /// against the worst-case blurred backdrop.
  final Color onGlassMuted;

  /// Accent ON GLASS (active nav item, status line). Replaces
  /// `colorScheme.primary` on glass where the accent is mid-luminance.
  final Color onGlassAccent;

  /// Wallpaper doodle stroke color; opacity is pre-baked into the color.
  final Color wallpaperTint;

  /// Chat date-separator mini-pill (solid content layer, not glass).
  final Color datePillBg;
  final Color datePillText;

  /// Drop shadow under floating glass chrome.
  final BoxShadow shadow;

  /// Opaque fallback fill (reduced transparency / low-end / NO-GO).
  final Color opaqueFill;

  const GlassTheme({
    required this.fill,
    required this.border,
    required this.highlight,
    required this.activeCapsule,
    required this.onGlassMuted,
    required this.onGlassAccent,
    required this.wallpaperTint,
    required this.datePillBg,
    required this.datePillText,
    required this.shadow,
    required this.opaqueFill,
  });

  static GlassTheme of(BuildContext context) =>
      Theme.of(context).extension<GlassTheme>()!;

  static const _shadowDark = BoxShadow(
    color: Color(0x73000000),
    blurRadius: 28,
    offset: Offset(0, 8),
  );

  /// `blue` theme — Nightfall dark.
  static const blue = GlassTheme(
    fill: Color(0x851A2632),
    border: Color(0x24AAD7FF),
    highlight: Color(0x12FFFFFF),
    activeCapsule: Color(0x3D2AABEE),
    onGlassMuted: Color(0xFFB9C6CF),
    onGlassAccent: Color(0xFF8FD0FF),
    wallpaperTint: Color(0x0D7FB8E8),
    datePillBg: Color(0xB80C141C),
    datePillText: Color(0xFF9FB4C4),
    shadow: _shadowDark,
    opaqueFill: Color(0xFF1E2D3A),
  );

  /// `dark` theme (Wire gray, default) — Teal Smoke dark.
  static const dark = GlassTheme(
    fill: Color(0x85202428),
    border: Color(0x21BEE1EB),
    highlight: Color(0x0FFFFFFF),
    activeCapsule: Color(0x3D6FB4C4),
    onGlassMuted: Color(0xFFB9C6CF),
    onGlassAccent: Color(0xFF6FB4C4),
    wallpaperTint: Color(0x0D8FC4D0),
    datePillBg: Color(0xB80C0D0F),
    datePillText: Color(0xFFA3ACB0),
    shadow: _shadowDark,
    opaqueFill: Color(0xFF25262B),
  );

  /// `light` theme (ember) — Hearthglow light.
  static const light = GlassTheme(
    fill: Color(0x8CFFFAF6),
    border: Color(0xBFFFFFFF),
    highlight: Color(0xE6FFFFFF),
    activeCapsule: Color(0x29C2410C),
    onGlassMuted: Color(0xFF5E5852),
    onGlassAccent: Color(0xFFC2410C),
    wallpaperTint: Color(0x13B0563A),
    datePillBg: Color(0xCCFFFCF9),
    datePillText: Color(0xFF8A6A58),
    shadow: BoxShadow(
      color: Color(0x29784628),
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
    opaqueFill: Color(0xFFFFFFFF),
  );

  /// `teal` theme — Teal Smoke light.
  static const teal = GlassTheme(
    fill: Color(0x8CFCFDFC),
    border: Color(0xBFFFFFFF),
    highlight: Color(0xE6FFFFFF),
    activeCapsule: Color(0x240F766E),
    onGlassMuted: Color(0xFF484440),
    onGlassAccent: Color(0xFF0A4F4A),
    wallpaperTint: Color(0x123E7A74),
    datePillBg: Color(0xCCFDFEFD),
    datePillText: Color(0xFF5C6B66),
    shadow: BoxShadow(
      color: Color(0x24285A50),
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
    opaqueFill: Color(0xFFFFFFFF),
  );

  @override
  ThemeExtension<GlassTheme> copyWith() => this;

  @override
  ThemeExtension<GlassTheme> lerp(
    covariant ThemeExtension<GlassTheme>? other,
    double t,
  ) =>
      this;
}
