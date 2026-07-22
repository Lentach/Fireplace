import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/chat_background_preference.dart';
import '../providers/settings_provider.dart';
import '../theme/rpg_theme.dart';
import '../widgets/appearance_preview.dart';
import '../widgets/glass/glass_surface.dart';
import '../widgets/glass/glass_top_bar.dart';

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
              13,
              media.top + GlassTopBar.capsuleHeight + 24,
              13,
              media.bottom + 24,
            ),
            children: [
              _SectionLabel(l10n.appearanceColorTheme),
              const SizedBox(height: 8),
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
              _SectionLabel(l10n.appearanceChatBackground),
              const SizedBox(height: 8),
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

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        style: RpgTheme.bodyFont(
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ).copyWith(letterSpacing: 1.1),
      ),
    );
  }
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
    final borderRadius = BorderRadius.circular(16);

    return Semantics(
      selected: selected,
      button: true,
      child: Stack(
        children: [
          GlassSurface(
            width: double.infinity,
            borderRadius: borderRadius,
            blur: false,
            shadow: false,
            child: Material(
              type: MaterialType.transparency,
              clipBehavior: Clip.antiAlias,
              borderRadius: borderRadius,
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
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: selected ? scheme.primary : Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                        child: selected
                            ? Icon(
                                Icons.check_rounded,
                                size: 18,
                                color: scheme.onPrimary,
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (selected)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: borderRadius,
                    border: Border.all(color: scheme.primary, width: 2),
                  ),
                ),
              ),
            ),
        ],
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
