import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/chat_background_preference.dart';
import '../providers/settings_provider.dart';
import '../theme/rpg_theme.dart';
import '../widgets/appearance_preview.dart';
import '../widgets/hex_avatar.dart';
import '../widgets/glass/glass_top_bar.dart';
import '../widgets/settings_console.dart';

class AppearanceScreen extends StatelessWidget {
  final int userId;

  const AppearanceScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final media = MediaQuery.paddingOf(context);
    final themes = _themeChoices(l10n);
    final backgrounds = _backgroundChoices(l10n, settings);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      extendBodyBehindAppBar: true,
      appBar: GlassTopBar(
        titleHorizontalInset: 74,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l10n.appearance,
          style: RpgTheme.bodyFont(
            fontSize: 16,
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Stack(
        children: [
          ListView(
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              0,
              media.top + GlassTopBar.capsuleHeight + 6,
              0,
              media.bottom + 24,
            ),
            children: [
              SettingsSectionCaption(label: l10n.appearanceColorTheme),
              for (final choice in themes) ...[
                _AppearanceChoiceCard(
                  key: ValueKey('appearance-theme-${choice.value}'),
                  selected: settings.themePreference == choice.value,
                  preview: AppearancePreview(
                    themeData: choice.themeData,
                    background: resolveChatBackground(
                      preference: ChatBackgroundPreference.themeDefault,
                      isCosmicTheme: choice.value == 'cosmic',
                    ),
                  ),
                  title: choice.name,
                  subtitle: choice.description,
                  onTap: () => settings.setThemePreference(choice.value),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 16),
              SettingsSectionCaption(label: l10n.appearanceChatBackground),
              for (final choice in backgrounds) ...[
                _AppearanceChoiceCard(
                  key: ValueKey(
                    'appearance-background-${choice.preference.name}',
                  ),
                  selected: settings.chatBackground == choice.preference,
                  preview: AppearancePreview(
                    themeData: settings.themeData,
                    background: choice.layer,
                  ),
                  title: choice.name,
                  subtitle: choice.description,
                  onTap: () =>
                      settings.setChatBackground(userId, choice.preference),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: media.top + GlassTopBar.capsuleHeight + 14,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      theme.scaffoldBackgroundColor,
                      theme.scaffoldBackgroundColor.withValues(alpha: 0.96),
                      theme.scaffoldBackgroundColor.withValues(alpha: 0),
                    ],
                    stops: const [0, 0.72, 1],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<_ThemeChoice> _themeChoices(AppLocalizations l10n) => [
    _ThemeChoice(
      value: 'light',
      name: l10n.appearanceThemeLight,
      description: l10n.themeOptionLight,
      themeData: RpgTheme.themeDataLight,
    ),
    _ThemeChoice(
      value: 'teal',
      name: l10n.appearanceThemeTeal,
      description: l10n.themeOptionTealStone,
      themeData: RpgTheme.themeDataTealStone,
    ),
    _ThemeChoice(
      value: 'dark',
      name: l10n.appearanceThemeDark,
      description: l10n.themeOptionDark,
      themeData: RpgTheme.themeDataDarkGray,
    ),
    _ThemeChoice(
      value: 'blue',
      name: l10n.appearanceThemeBlue,
      description: l10n.themeOptionBlue,
      themeData: RpgTheme.themeDataBlue,
    ),
    _ThemeChoice(
      value: 'cosmic',
      name: l10n.appearanceThemeCosmic,
      description: l10n.themeOptionCosmic,
      themeData: RpgTheme.themeDataCosmic,
    ),
  ];

  List<_BackgroundChoice> _backgroundChoices(
    AppLocalizations l10n,
    SettingsProvider settings,
  ) => [
    _BackgroundChoice(
      preference: ChatBackgroundPreference.themeDefault,
      layer: settings.themePreference == 'cosmic'
          ? ChatBackgroundLayer.starfield
          : ChatBackgroundLayer.plain,
      name: l10n.appearanceBackgroundThemeDefault,
      description: settings.themePreference == 'cosmic'
          ? l10n.appearanceBackgroundThemeDefaultCosmicSubtitle
          : l10n.appearanceBackgroundThemeDefaultSubtitle,
    ),
    _BackgroundChoice(
      preference: ChatBackgroundPreference.plain,
      layer: ChatBackgroundLayer.plain,
      name: l10n.appearanceBackgroundPlain,
      description: l10n.appearanceBackgroundPlainSubtitle,
    ),
    _BackgroundChoice(
      preference: ChatBackgroundPreference.glyphs,
      layer: ChatBackgroundLayer.glyphs,
      name: l10n.appearanceBackgroundGlyphs,
      description: l10n.appearanceBackgroundGlyphsSubtitle,
    ),
  ];
}

class _HexSelectionMark extends StatelessWidget {
  const _HexSelectionMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 26,
      height: 30,
      child: CustomPaint(
        painter: _HexSelectionMarkPainter(
          selected: selected,
          primary: colorScheme.primary,
          onPrimary: colorScheme.onPrimary,
          outline: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _HexSelectionMarkPainter extends CustomPainter {
  const _HexSelectionMarkPainter({
    required this.selected,
    required this.primary,
    required this.onPrimary,
    required this.outline,
  });

  final bool selected;
  final Color primary;
  final Color onPrimary;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final hex = hexPath(
      Offset(size.width / 2, size.height / 2),
      size.height / 2 - 0.75,
    );
    final outlinePaint = Paint()
      ..color = selected ? primary : outline.withValues(alpha: 0.64)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeJoin = StrokeJoin.round;

    if (selected) {
      canvas.drawPath(
        hex,
        Paint()
          ..color = primary
          ..style = PaintingStyle.fill,
      );
    }
    canvas.drawPath(hex, outlinePaint);

    if (selected) {
      final check = Path()
        ..moveTo(size.width * 0.28, size.height * 0.52)
        ..lineTo(size.width * 0.45, size.height * 0.68)
        ..lineTo(size.width * 0.73, size.height * 0.35);
      canvas.drawPath(
        check,
        Paint()
          ..color = onPrimary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HexSelectionMarkPainter oldDelegate) =>
      oldDelegate.selected != selected ||
      oldDelegate.primary != primary ||
      oldDelegate.onPrimary != onPrimary ||
      oldDelegate.outline != outline;
}

class _AppearanceChoiceCard extends StatelessWidget {
  final bool selected;
  final Widget preview;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AppearanceChoiceCard({
    super.key,
    required this.selected,
    required this.preview,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Semantics(
        selected: selected,
        button: true,
        child: Stack(
          children: [
            Material(
              color: scheme.surfaceContainerHighest,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      preview,
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: RpgTheme.bodyFont(
                                fontSize: 14,
                                color: scheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: RpgTheme.bodyFont(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ).copyWith(height: 1.25),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      _HexSelectionMark(selected: selected),
                    ],
                  ),
                ),
              ),
            ),
            if (selected)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: scheme.primary, width: 2),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ThemeChoice {
  final String value;
  final String name;
  final String description;
  final ThemeData themeData;

  const _ThemeChoice({
    required this.value,
    required this.name,
    required this.description,
    required this.themeData,
  });
}

class _BackgroundChoice {
  final ChatBackgroundPreference preference;
  final ChatBackgroundLayer layer;
  final String name;
  final String description;

  const _BackgroundChoice({
    required this.preference,
    required this.layer,
    required this.name,
    required this.description,
  });
}
