import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/theme/glass_theme.dart';

/// Golden lock for the four RpgTheme ThemeData builders. Captures every resolved
/// field the themeDataBlue/DarkGray/Light/TealStone builders produce today, so a
/// factory refactor (or any future edit) that mis-routes a color to the wrong
/// slot in ONE theme fails loudly. Values are asserted against the public
/// RpgTheme color constants — the source of truth both the builders and the
/// factory draw from. Themes are captured through a MaterialApp (the app's real
/// usage + the repo's working pattern for GoogleFonts-based themes).
void main() {
  Color elevBg(ThemeData t) =>
      t.elevatedButtonTheme.style!.backgroundColor!.resolve(const {})!;
  Color elevSide(ThemeData t) =>
      t.elevatedButtonTheme.style!.shape!.resolve(const {})!.side.color;
  Color textBtnFg(ThemeData t) =>
      t.textButtonTheme.style!.foregroundColor!.resolve(const {})!;
  Color elevFg(ThemeData t) =>
      t.elevatedButtonTheme.style!.foregroundColor!.resolve(const {})!;

  Future<ThemeData> capture(WidgetTester tester, ThemeData theme) async {
    late ThemeData captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Builder(
          builder: (ctx) {
            captured = Theme.of(ctx);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return captured;
  }

  void checkTheme(
    ThemeData t, {
    required Brightness brightness,
    required Color primary,
    required Color secondary,
    required Color surface,
    required Color onPrimary,
    required Color onSecondary,
    required Color onSurface,
    required Color appBarBg,
    required Color appBarTitle,
    required Color inputFill,
    required Color inputHint,
    required Color inputLabel,
    required Color inputFocused,
    required Color elevatedBg,
    required Color elevatedSide,
    required Color elevatedFg,
    required Color textButtonFg,
    required Color fab,
    required Color fabFg,
    required Color selectedTile,
    required Color divider,
    required Color titleLarge,
    required Color bodyMedium,
    required Color bodySmall,
    required FireplaceColors fc,
    required GlassTheme glass,
  }) {
    expect(t.brightness, brightness);
    expect(t.colorScheme.primary, primary);
    expect(t.colorScheme.secondary, secondary);
    expect(t.colorScheme.surface, surface);
    expect(t.colorScheme.onPrimary, onPrimary);
    expect(t.colorScheme.onSecondary, onSecondary);
    expect(t.colorScheme.onSurface, onSurface);
    expect(
      t.colorScheme.error,
      brightness == Brightness.dark
          ? RpgTheme.errorColor
          : RpgTheme.errorColorLight,
    );

    expect(t.appBarTheme.backgroundColor, appBarBg);
    expect(t.appBarTheme.titleTextStyle!.color, appBarTitle);

    expect(t.inputDecorationTheme.fillColor, inputFill);
    expect(t.inputDecorationTheme.hintStyle!.color, inputHint);
    expect(t.inputDecorationTheme.labelStyle!.color, inputLabel);
    expect(
      (t.inputDecorationTheme.focusedBorder as OutlineInputBorder)
          .borderSide
          .color,
      inputFocused,
    );

    expect(elevBg(t), elevatedBg);
    expect(elevSide(t), elevatedSide);
    expect(elevFg(t), elevatedFg);
    expect(textBtnFg(t), textButtonFg);
    expect(t.floatingActionButtonTheme.backgroundColor, fab);
    expect(t.floatingActionButtonTheme.foregroundColor, fabFg);
    expect(t.listTileTheme.selectedTileColor, selectedTile);
    expect(t.dividerTheme.color, divider);

    expect(t.textTheme.titleLarge!.color, titleLarge);
    expect(t.textTheme.bodyMedium!.color, bodyMedium);
    expect(t.textTheme.bodySmall!.color, bodySmall);

    final f = t.extension<FireplaceColors>()!;
    expect(f.inputBg, fc.inputBg);
    expect(f.convItemBorder, fc.convItemBorder);
    expect(f.convItemBg, fc.convItemBg);
    expect(f.messagesAreaBg, fc.messagesAreaBg);
    expect(f.mineMsgBg, fc.mineMsgBg);
    expect(f.theirsMsgBg, fc.theirsMsgBg);
    expect(f.settingsTileBg, fc.settingsTileBg);
    expect(f.settingsTileBorder, fc.settingsTileBorder);
    expect(f.tabBorder, fc.tabBorder);
    expect(f.borderColor, fc.borderColor);
    expect(f.mutedText, fc.mutedText);

    expect(t.extension<GlassTheme>(), same(glass));
  }

  testWidgets('themeDataBlue golden', (tester) async {
    checkTheme(
      await capture(tester, RpgTheme.themeDataBlue),
      brightness: Brightness.dark,
      primary: RpgTheme.accentBlue,
      secondary: RpgTheme.accentBlueDark,
      surface: RpgTheme.boxBgBlue,
      // Bright Telegram-blue accents: black foregrounds (white fails 4.5:1).
      onPrimary: Colors.black,
      onSecondary: Colors.black,
      onSurface: RpgTheme.textColorBlue,
      appBarBg: RpgTheme.boxBgBlue,
      appBarTitle: RpgTheme.accentBlue,
      inputFill: RpgTheme.inputBgBlue,
      inputHint: RpgTheme.mutedTextBlue,
      inputLabel: RpgTheme.mutedTextBlue,
      inputFocused: RpgTheme.accentBlue,
      elevatedBg: RpgTheme.buttonBgBlue,
      elevatedSide: RpgTheme.accentBlue,
      elevatedFg: Colors.black,
      textButtonFg: RpgTheme.accentBlue,
      fab: RpgTheme.accentBlue,
      fabFg: Colors.black,
      selectedTile: RpgTheme.activeTabBgBlue,
      divider: RpgTheme.convItemBorderBlue,
      titleLarge: RpgTheme.accentBlue,
      bodyMedium: RpgTheme.textColorBlue,
      bodySmall: RpgTheme.mutedTextBlue,
      fc: const FireplaceColors(
        inputBg: RpgTheme.inputBgBlue,
        convItemBorder: RpgTheme.convItemBorderBlue,
        convItemBg: RpgTheme.convItemBgBlue,
        messagesAreaBg: RpgTheme.messagesAreaBgBlue,
        mineMsgBg: RpgTheme.mineMsgBgBlue,
        theirsMsgBg: RpgTheme.theirsMsgBgBlue,
        settingsTileBg: RpgTheme.boxBgBlue,
        settingsTileBorder: RpgTheme.settingsTileBorderBlue,
        tabBorder: RpgTheme.tabBorderBlue,
        borderColor: RpgTheme.borderBlue,
        mutedText: RpgTheme.mutedTextBlue,
      ),
      glass: GlassTheme.blue,
    );
  });

  testWidgets('themeDataDarkGray golden', (tester) async {
    checkTheme(
      await capture(tester, RpgTheme.themeDataDarkGray),
      brightness: Brightness.dark,
      primary: RpgTheme.accentDarkGray,
      secondary: RpgTheme.accentDarkGray,
      surface: RpgTheme.boxBgDarkGray,
      onPrimary: RpgTheme.backgroundDarkGray,
      onSecondary: RpgTheme.backgroundDarkGray,
      onSurface: RpgTheme.textColorDarkGray,
      appBarBg: RpgTheme.boxBgDarkGray,
      appBarTitle: RpgTheme.accentDarkGray,
      inputFill: RpgTheme.inputBgDarkGray,
      inputHint: RpgTheme.mutedDarkGray,
      inputLabel: RpgTheme.mutedDarkGray,
      inputFocused: RpgTheme.accentDarkGray,
      elevatedBg: RpgTheme.accentDarkGray,
      elevatedSide: RpgTheme.accentDarkGray,
      elevatedFg: Colors.black,
      textButtonFg: RpgTheme.accentDarkGray,
      fab: RpgTheme.accentDarkGray,
      fabFg: Colors.black,
      selectedTile: RpgTheme.activeTabBgDarkGray,
      divider: RpgTheme.convItemBorderDarkGray,
      titleLarge: RpgTheme.accentDarkGray,
      bodyMedium: RpgTheme.textColorDarkGray,
      bodySmall: RpgTheme.mutedDarkGray,
      fc: const FireplaceColors(
        inputBg: RpgTheme.inputBgDarkGray,
        convItemBorder: RpgTheme.convItemBorderDarkGray,
        convItemBg: RpgTheme.convItemBgDarkGray,
        messagesAreaBg: RpgTheme.messagesAreaBgDarkGray,
        mineMsgBg: RpgTheme.mineMsgBgDarkGray,
        theirsMsgBg: RpgTheme.theirsMsgBgDarkGray,
        settingsTileBg: Color(0xFF25262B),
        settingsTileBorder: RpgTheme.settingsTileBorderDarkGray,
        tabBorder: RpgTheme.tabBorderDarkGray,
        borderColor: RpgTheme.accentDarkGray,
        mutedText: RpgTheme.mutedDarkGray,
      ),
      glass: GlassTheme.dark,
    );
  });

  testWidgets('themeDataLight golden', (tester) async {
    checkTheme(
      await capture(tester, RpgTheme.themeDataLight),
      brightness: Brightness.light,
      primary: RpgTheme.primaryLight,
      secondary: RpgTheme.primaryLightHover,
      surface: RpgTheme.boxBgLight,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: RpgTheme.textColorLight,
      appBarBg: RpgTheme.boxBgLight,
      appBarTitle: RpgTheme.primaryLight,
      inputFill: RpgTheme.inputBgLight,
      inputHint: RpgTheme.mutedTextLight,
      inputLabel: RpgTheme.labelTextLight,
      inputFocused: RpgTheme.primaryLight,
      elevatedBg: RpgTheme.primaryLight,
      elevatedSide: RpgTheme.primaryLight,
      elevatedFg: Colors.white,
      textButtonFg: RpgTheme.primaryLight,
      fab: RpgTheme.primaryLight,
      fabFg: Colors.white,
      selectedTile: RpgTheme.activeTabBgLight,
      divider: RpgTheme.convItemBorderLight,
      titleLarge: RpgTheme.primaryLight,
      bodyMedium: RpgTheme.textColorLight,
      bodySmall: RpgTheme.textSecondaryLight,
      fc: const FireplaceColors(
        inputBg: RpgTheme.inputBgLight,
        convItemBorder: RpgTheme.convItemBorderLight,
        convItemBg: RpgTheme.convItemBgLight,
        messagesAreaBg: RpgTheme.messagesAreaBgLight,
        mineMsgBg: RpgTheme.mineMsgBgLight,
        theirsMsgBg: RpgTheme.theirsMsgBgLight,
        settingsTileBg: RpgTheme.boxBgLight,
        settingsTileBorder: RpgTheme.convItemBorderLight,
        tabBorder: RpgTheme.tabBorderLight,
        borderColor: RpgTheme.primaryLight,
        mutedText: RpgTheme.textSecondaryLight,
      ),
      glass: GlassTheme.light,
    );
  });

  testWidgets('themeDataTealStone golden', (tester) async {
    checkTheme(
      await capture(tester, RpgTheme.themeDataTealStone),
      brightness: Brightness.light,
      primary: RpgTheme.primaryTealStone,
      secondary: RpgTheme.secondaryTealStone,
      surface: RpgTheme.surfaceTealStone,
      onPrimary: Colors.white,
      onSecondary: Colors.black,
      onSurface: RpgTheme.textColorTealStone,
      appBarBg: RpgTheme.surfaceTealStone,
      appBarTitle: RpgTheme.primaryTealStone,
      inputFill: RpgTheme.inputBgTealStone,
      inputHint: RpgTheme.mutedTealStone,
      inputLabel: RpgTheme.mutedTealStone,
      inputFocused: RpgTheme.primaryTealStone,
      elevatedBg: RpgTheme.secondaryTealStone,
      elevatedSide: RpgTheme.secondaryTealStone,
      elevatedFg: Colors.black,
      textButtonFg: RpgTheme.primaryTealStone,
      fab: RpgTheme.secondaryTealStone,
      fabFg: Colors.black,
      selectedTile: RpgTheme.activeTabBgTealStone,
      divider: RpgTheme.borderTealStone,
      titleLarge: RpgTheme.primaryTealStone,
      bodyMedium: RpgTheme.textColorTealStone,
      bodySmall: RpgTheme.mutedTealStone,
      fc: const FireplaceColors(
        inputBg: RpgTheme.inputBgTealStone,
        convItemBorder: RpgTheme.borderTealStone,
        convItemBg: RpgTheme.convItemBgTealStone,
        messagesAreaBg: RpgTheme.messagesAreaTealStone,
        mineMsgBg: RpgTheme.mineMsgBgTealStone,
        theirsMsgBg: RpgTheme.theirsMsgBgTealStone,
        settingsTileBg: RpgTheme.surfaceTealStone,
        settingsTileBorder: RpgTheme.settingsTileBorderTealStone,
        tabBorder: RpgTheme.borderTealStone,
        borderColor: RpgTheme.primaryTealStone,
        mutedText: RpgTheme.mutedTealStone,
      ),
      glass: GlassTheme.teal,
    );
  });
}
