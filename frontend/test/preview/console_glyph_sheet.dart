// Glyph comparison poster (not part of `flutter test`).
//
// Run: flutter run -d web-server --web-port 8098 \
//        -t test/preview/console_glyph_sheet.dart
// Params: ?theme=cosmic|blue|dark|light|teal
//
// Renders both drawings of the Settings console glyph set side by side.
//
// The big grid is for JUDGING SHAPES. The strip at the bottom is the same
// glyphs at the size they actually ship at, and that strip is the honest
// view: a blow-up flatters the schematic set exactly where it fails on a
// phone (thin traces, small gaps, hex inside hex). This project already
// shipped one design that passed three themes in render and was wrong in the
// owner's hand, so the device still decides.
import 'package:flutter/material.dart';

import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/console_glyphs.dart';
import 'package:fireplace/widgets/settings_console.dart';

void main() => runApp(const GlyphSheetApp());

ThemeData _theme(String name) => switch (name) {
  'cosmic' => RpgTheme.themeDataCosmic,
  'blue' => RpgTheme.themeDataBlue,
  'light' => RpgTheme.themeDataLight,
  'teal' => RpgTheme.themeDataTealStone,
  _ => RpgTheme.themeDataDarkGray,
};

/// Rows the owner actually sees, so the set is judged in context and not as
/// an isolated art object.
const _contextRows = <(ConsoleGlyph, String, String?, ConsoleRowEdge)>[
  (ConsoleGlyph.privacy, 'Privacy & Safety', null, ConsoleRowEdge.none),
  (ConsoleGlyph.blocked, 'Blocked', null, ConsoleRowEdge.none),
  (ConsoleGlyph.devices, 'Devices', 'Web Browser', ConsoleRowEdge.none),
  (ConsoleGlyph.password, 'Reset password', null, ConsoleRowEdge.none),
  (ConsoleGlyph.deleteNode, 'Delete account', null, ConsoleRowEdge.danger),
  (ConsoleGlyph.logout, 'Log out', null, ConsoleRowEdge.accent),
];

class GlyphSheetApp extends StatelessWidget {
  const GlyphSheetApp({super.key});

  @override
  Widget build(BuildContext context) {
    final query = Uri.base.queryParameters;
    final themeName = query['theme'] ?? 'cosmic';

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(themeName),
      home: _Poster(themeName: themeName),
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.themeName});

  final String themeName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SETTINGS CONSOLE GLYPHS — ${themeName.toUpperCase()}',
              style: RpgTheme.bodyFont(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ).copyWith(letterSpacing: 2),
            ),
            const SizedBox(height: 24),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _Block(
                    title: 'A — INSTRUMENT',
                    blurb:
                        'Conventional silhouette, rebuilt on the keyline grid.',
                    set: ConsoleGlyphSet.instrument,
                  ),
                ),
                const SizedBox(width: 40),
                Expanded(
                  child: _Block(
                    title: 'B — SCHEMATIC',
                    blurb:
                        'Node diagrams where that is literally true. '
                        'Dimmed = no node meaning, keeps the A drawing.',
                    set: ConsoleGlyphSet.schematic,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 40),
            Text(
              'TRUE SIZE — HOW IT ACTUALLY SHIPS',
              style: RpgTheme.bodyFont(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurfaceVariant,
              ).copyWith(letterSpacing: 1.6),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 390, child: _ContextRows()),
                const SizedBox(width: 40),
                SizedBox(
                  width: 390,
                  child: _ContextRows(set: ConsoleGlyphSet.schematic),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.title, required this.blurb, required this.set});

  final String title;
  final String blurb;
  final ConsoleGlyphSet set;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: RpgTheme.bodyFont(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: colorScheme.primary,
          ).copyWith(letterSpacing: 1.4),
        ),
        const SizedBox(height: 4),
        Text(
          blurb,
          style: RpgTheme.bodyFont(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 18,
          children: [
            for (final glyph in ConsoleGlyph.values)
              _Cell(glyph: glyph, set: set),
          ],
        ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.glyph, required this.set});

  final ConsoleGlyph glyph;
  final ConsoleGlyphSet set;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final drawn =
        set == ConsoleGlyphSet.instrument || consoleGlyphHasSchematic(glyph);

    return SizedBox(
      width: 128,
      child: Column(
        children: [
          Opacity(
            opacity: drawn ? 1 : 0.25,
            child: ConsoleHexIcon(glyph: glyph, set: set, height: 96),
          ),
          const SizedBox(height: 8),
          Text(
            glyph.name,
            textAlign: TextAlign.center,
            style: RpgTheme.bodyFont(
              fontSize: 12,
              color: drawn
                  ? colorScheme.onSurfaceVariant
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextRows extends StatelessWidget {
  const _ContextRows({this.set = ConsoleGlyphSet.instrument});

  final ConsoleGlyphSet set;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final row in _contextRows)
        SettingsConsoleRow(
          glyph: row.$1,
          title: row.$2,
          subtitle: row.$3,
          edge: row.$4,
          set: set,
          onTap: () {},
        ),
    ],
  );
}
