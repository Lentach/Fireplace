import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'glass_theme.dart';

/// Theme-specific colors for chat UI. Use via `Theme.of(context).extension<FireplaceColors>()!`
class FireplaceColors extends ThemeExtension<FireplaceColors> {
  final Color inputBg;
  final Color convItemBorder;
  final Color convItemBg;
  final Color messagesAreaBg;
  final Color mineMsgBg;
  final Color theirsMsgBg;
  final Color settingsTileBg;
  final Color settingsTileBorder;
  final Color tabBorder;
  final Color borderColor;
  final Color mutedText;

  const FireplaceColors({
    required this.inputBg,
    required this.convItemBorder,
    required this.convItemBg,
    required this.messagesAreaBg,
    required this.mineMsgBg,
    required this.theirsMsgBg,
    required this.settingsTileBg,
    required this.settingsTileBorder,
    required this.tabBorder,
    required this.borderColor,
    required this.mutedText,
  });

  static FireplaceColors of(BuildContext context) =>
      Theme.of(context).extension<FireplaceColors>()!;

  @override
  ThemeExtension<FireplaceColors> copyWith() => this;

  @override
  ThemeExtension<FireplaceColors> lerp(
    covariant ThemeExtension<FireplaceColors>? other,
    double t,
  ) =>
      this;
}

class RpgTheme {
  static const Color background = Color(0xFF0A0A2E);
  static const Color boxBg = Color(0xFF0F0F3D);
  static const Color inputBg = Color(0xFF0A0A24);
  static const Color textColor = Color(0xFFE0E0E0);
  static const Color mutedText = Color(0xFF6A6AB0);
  static const Color errorColor = Color(0xFFFF4444);
  static const Color successColor = Color(0xFF44FF44);
  static const Color messagesAreaBg = Color(0xFF08081E);
  // Blue theme: red accent -> sent = dark red-brown, received = dark gray (legacy; blue theme now uses Telegram palette)
  static const Color mineMsgBg = Color(0xFF4A2A35);
  static const Color theirsMsgBg = Color(0xFF1E2028);

  // Telegram-style blue theme (default dark) – official Telegram colors
  // Background: #17212B, accent: #2AABEE, sent bubble: #2481CC, received: #2B2B2B
  static const Color backgroundBlue = Color(0xFF17212B);
  static const Color boxBgBlue = Color(0xFF1E2D3A);
  static const Color inputBgBlue = Color(0xFF1E2D3A);
  static const Color textColorBlue = Color(0xFFE4E4E4);
  static const Color mutedTextBlue = Color(0xFF8A8A8A);
  static const Color messagesAreaBgBlue = Color(0xFF17212B);
  static const Color mineMsgBgBlue = Color(0xFF2481CC); // sent bubble (Telegram blue, slightly darker for dark mode)
  static const Color theirsMsgBgBlue = Color(0xFF2B2B2B); // received bubble (dark gray)
  static const Color accentBlue = Color(0xFF2AABEE); // Telegram official blue
  static const Color accentBlueDark = Color(0xFF229ED9); // alternative/hover
  static const Color borderBlue = Color(0xFF3D5A6B);
  static const Color buttonBgBlue = Color(0xFF2AABEE);
  static const Color activeTabBgBlue = Color(0xFF1E3A4A);
  static const Color tabBorderBlue = Color(0xFF3D5A6B);
  static const Color convItemBorderBlue = Color(0xFF2B3B45);
  static const Color convItemBgBlue = Color(0xFF1E2D3A);
  static const Color timeColorBlue = Color(0xFF8A9BA8);
  static Color get settingsTileBgBlue => accentBlue.withValues(alpha: 0.12);
  static const Color settingsTileBorderBlue = Color(0xFF3D5A6B);

  // Dark mode – primary accent, borders, muted (Wire-style dark gray theme uses these)
  static const Color accentDark = Color(0xFFFF6666);
  static const Color borderDark = Color(0xFFCC5555);
  static const Color mutedDark = Color(0xFF9A8A8A);
  static const Color buttonBgDark = Color(0xFF8A3333);
  static const Color activeTabBgDark = Color(0xFF3D2525);
  static const Color tabBorderDark = Color(0xFF8A5555);
  static const Color convItemBorderDark = Color(0xFF5A3535);
  static const Color convItemBgDark = Color(0xFF1E1515);
  static const Color timeColorDark = Color(0xFF9A7A7A);
  static Color get settingsTileBgDark => accentDark.withValues(alpha: 0.1);
  static const Color settingsTileBorderDark = accentDark;

  // Dark gray theme (Wire-style) – neutral grays
  static const Color backgroundDarkGray = Color(0xFF17181A);
  static const Color boxBgDarkGray = Color(0xFF25262B);
  static const Color inputBgDarkGray = Color(0xFF1E1F23);
  static const Color textColorDarkGray = Color(0xFFF5F5F5);
  static const Color accentDarkGray = Color(0xFF5C9EAD);
  static const Color mutedDarkGray = Color(0xFF949798);
  static const Color convItemBorderDarkGray = Color(0xFF34383B);
  static const Color convItemBgDarkGray = Color(0xFF1E1F23);
  static const Color tabBorderDarkGray = Color(0xFF34383B);
  static const Color messagesAreaBgDarkGray = Color(0xFF17181A);
  static const Color mineMsgBgDarkGray = Color(0xFF2A4A5A);
  static const Color theirsMsgBgDarkGray = Color(0xFF25262B);
  static const Color activeTabBgDarkGray = Color(0xFF2C2E33);
  static const Color timeColorDarkGray = Color(0xFF949798);
  static const Color settingsTileBorderDarkGray = Color(0xFF5C9EAD);

  // Light theme — warm paper neutrals + ember accent (Fireplace brand, not Slack purple)
  static const Color primaryLight = Color(0xFFC2410C); // orange-700, white onPrimary
  static const Color primaryLightHover = Color(0xFF9A3412); // orange-800
  static const Color backgroundLight = Color(0xFFF7F4F0);
  static const Color boxBgLight = Color(0xFFFFFFFF);
  static const Color chatAreaBgLight = Color(0xFFFAF8F5);
  static const Color textColorLight = Color(0xFF1C1917); // warm near-black
  static const Color textSecondaryLight = Color(0xFF57534E); // stone-600
  static const Color mutedTextLight = Color(0xFF78716C); // stone-500
  static const Color labelTextLight = Color(0xFF57534E);
  static const Color inputBgLight = Color(0xFFF5F0EB);
  static const Color tabBorderLight = Color(0xFFE8E3DC);
  static const Color activeTabBgLight = Color(0xFFF0E8E0);
  static const Color buttonBgLight = primaryLight;
  static const Color convItemBgLight = Color(0xFFFAF6F2);
  static const Color convItemBorderLight = Color(0xFFE8E3DC);
  static const Color messagesAreaBgLight = Color(0xFFFAF8F5);
  // Sent = warm tint (not solid primary): dark text + delivery ticks stay visible.
  // Received = neutral warm gray (no purple tint).
  static const Color mineMsgBgLight = Color(0xFFFFE4D6); // orange-100
  static const Color theirsMsgBgLight = Color(0xFFE7E5E4);
  static const Color timeColorLight = Color(0xFF57534E);

  // Teal + stone (modern light): same accent family as dark-gray #5C9EAD, deeper teal on UI chrome.
  static const Color primaryTealStone = Color(0xFF0F766E); // teal-700
  static const Color secondaryTealStone = Color(0xFF0D9488); // teal-600
  static const Color backgroundTealStone = Color(0xFFFAFAF9); // stone-50
  static const Color surfaceTealStone = Color(0xFFFFFFFF);
  static const Color textColorTealStone = Color(0xFF1C1917); // stone-900
  static const Color borderTealStone = Color(0xFFE7E5E4); // stone-200
  static const Color mutedTealStone = Color(0xFF78716C); // stone-500
  static const Color inputBgTealStone = Color(0xFFF5F5F4); // stone-100
  static const Color convItemBgTealStone = Color(0xFFFAFAF9);
  static const Color messagesAreaTealStone = Color(0xFFFAFAF9);
  static const Color mineMsgBgTealStone = secondaryTealStone;
  static const Color theirsMsgBgTealStone = borderTealStone;
  static const Color activeTabBgTealStone = Color(0xFFF0FDFA); // teal-50
  static const Color settingsTileBorderTealStone = borderTealStone;

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Clock label for message bubbles (server sends UTC; show device-local).
  static String formatMessageClock(DateTime dt) {
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  /// Time + disappearing-message countdown on bubbles.
  /// Blue (Telegram) theme only: light meta on sent bubbles; `mutedText` on received.
  /// Dark gray / light themes keep the legacy single meta color (unchanged).
  static Color messageBubbleMetaColor(
    BuildContext context, {
    required bool isMine,
    required String themePreference,
  }) {
    if (themePreference == 'blue' || themePreference == 'teal') {
      if (isMine) {
        return isDark(context)
            ? Colors.white.withValues(alpha: 0.86)
            : Colors.white.withValues(alpha: 0.9);
      }
      return FireplaceColors.of(context).mutedText;
    }
    final dark = isDark(context);
    return dark ? timeColorDark : textSecondaryLight;
  }

  /// Hearth Fade / disappearing-messages accent (composer banner, timer sheet hero,
  /// list arc). Light = ember orange; teal = [primaryTealStone]; dark/blue per theme.
  static Color ephemeralAccent(
    BuildContext context, {
    required String themePreference,
  }) {
    switch (themePreference) {
      case 'teal':
        return primaryTealStone;
      case 'light':
        return primaryLight;
      case 'blue':
        return accentBlue;
      case 'dark':
        return accentDarkGray;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  /// Delivery checkmarks: pale icons on dark sent bubbles (dark/blue + teal);
  /// light (ember) sent tint uses stone + ember read via [themePreference] `light`.
  static (Color pendingOrSent, Color read) messageBubbleDeliveryTickColors(
    BuildContext context, {
    required bool isMine,
    required String themePreference,
  }) {
    if (isMine &&
        themePreference == 'light' &&
        Theme.of(context).brightness == Brightness.light) {
      return (textSecondaryLight, primaryLight);
    }
    if (isMine && themePreference == 'teal') {
      return (
        Colors.white.withValues(alpha: 0.88),
        const Color(0xFFCCFBF1), // teal-100, read state on teal bubble
      );
    }
    return (
      const Color(0xFFE0E0E0),
      const Color(0xFF64B5F6),
    );
  }

  static Color primaryColor(BuildContext context) =>
      Theme.of(context).colorScheme.primary;

  static Color surfaceColor(BuildContext context) =>
      isDark(context) ? boxBg : boxBgLight;

  static TextStyle pressStart2P({double fontSize = 10, Color color = textColor}) {
    return GoogleFonts.pressStart2p(
      fontSize: fontSize,
      color: color,
    );
  }

  /// App chrome (AppBar, main tab headers): matches `bodyFont` / list typography (Inter).
  static TextStyle screenHeaderTitle({
    required Color color,
    double fontSize = 18,
    FontWeight fontWeight = FontWeight.w600,
  }) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: -0.25,
    );
  }

  static TextStyle bodyFont({double fontSize = 14, Color color = textColor, FontWeight fontWeight = FontWeight.normal}) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      color: color,
      fontWeight: fontWeight,
    );
  }

  /// Blue theme – Telegram-style (dark blue background, blue accent and sent bubbles).
  static ThemeData get themeDataBlue {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: backgroundBlue,
      colorScheme: const ColorScheme.dark(
        primary: accentBlue,
        secondary: accentBlueDark,
        surface: boxBgBlue,
        error: errorColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textColorBlue,
        onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: boxBgBlue,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: accentBlue,
          letterSpacing: -0.25,
        ),
        iconTheme: const IconThemeData(color: textColorBlue),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputBgBlue,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderSide: const BorderSide(color: tabBorderBlue, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: tabBorderBlue, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: accentBlue, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: errorColor, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        hintStyle: GoogleFonts.inter(color: mutedTextBlue, fontSize: 14),
        labelStyle: GoogleFonts.inter(color: mutedTextBlue, fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonBgBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: accentBlue, width: 2),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentBlue,
          textStyle: GoogleFonts.inter(fontSize: 14),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accentBlue,
        foregroundColor: Colors.white,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        tileColor: Colors.transparent,
        selectedTileColor: activeTabBgBlue,
      ),
      dividerTheme: const DividerThemeData(
        color: convItemBorderBlue,
        thickness: 1,
      ),
      textTheme: TextTheme(
        bodyLarge: GoogleFonts.inter(color: textColorBlue, fontSize: 16),
        bodyMedium: GoogleFonts.inter(color: textColorBlue, fontSize: 14),
        bodySmall: GoogleFonts.inter(color: mutedTextBlue, fontSize: 12),
        titleLarge: GoogleFonts.inter(
          color: accentBlue,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.25,
        ),
        titleMedium: GoogleFonts.inter(color: textColorBlue, fontSize: 16, fontWeight: FontWeight.w600),
        titleSmall: GoogleFonts.inter(color: textColorBlue, fontSize: 14, fontWeight: FontWeight.w600),
        labelLarge: GoogleFonts.inter(color: textColorBlue, fontSize: 14, fontWeight: FontWeight.w500),
      ),
      extensions: [
        const FireplaceColors(
          inputBg: inputBgBlue,
          convItemBorder: convItemBorderBlue,
          convItemBg: convItemBgBlue,
          messagesAreaBg: messagesAreaBgBlue,
          mineMsgBg: mineMsgBgBlue,
          theirsMsgBg: theirsMsgBgBlue,
          settingsTileBg: boxBgBlue,
          settingsTileBorder: settingsTileBorderBlue,
          tabBorder: tabBorderBlue,
          borderColor: borderBlue,
          mutedText: mutedTextBlue,
        ),
        GlassTheme.blue,
      ],
    );
  }

  /// Dark gray theme – Wire-style neutral.
  static ThemeData get themeDataDarkGray {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: backgroundDarkGray,
      colorScheme: const ColorScheme.dark(
        primary: accentDarkGray,
        secondary: accentDarkGray,
        surface: boxBgDarkGray,
        error: errorColor,
        onPrimary: backgroundDarkGray,
        onSecondary: textColorDarkGray,
        onSurface: textColorDarkGray,
        onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: boxBgDarkGray,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: accentDarkGray,
          letterSpacing: -0.25,
        ),
        iconTheme: const IconThemeData(color: textColorDarkGray),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputBgDarkGray,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderSide: const BorderSide(color: tabBorderDarkGray, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: tabBorderDarkGray, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: accentDarkGray, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: errorColor, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        hintStyle: GoogleFonts.inter(color: mutedDarkGray, fontSize: 14),
        labelStyle: GoogleFonts.inter(color: mutedDarkGray, fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentDarkGray,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: accentDarkGray, width: 2),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentDarkGray,
          textStyle: GoogleFonts.inter(fontSize: 14),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accentDarkGray,
        foregroundColor: Colors.white,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        tileColor: Colors.transparent,
        selectedTileColor: activeTabBgDarkGray,
      ),
      dividerTheme: const DividerThemeData(
        color: convItemBorderDarkGray,
        thickness: 1,
      ),
      textTheme: TextTheme(
        bodyLarge: GoogleFonts.inter(color: textColorDarkGray, fontSize: 16),
        bodyMedium: GoogleFonts.inter(color: textColorDarkGray, fontSize: 14),
        bodySmall: GoogleFonts.inter(color: mutedDarkGray, fontSize: 12),
        titleLarge: GoogleFonts.inter(
          color: accentDarkGray,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.25,
        ),
        titleMedium: GoogleFonts.inter(color: textColorDarkGray, fontSize: 16, fontWeight: FontWeight.w600),
        titleSmall: GoogleFonts.inter(color: textColorDarkGray, fontSize: 14, fontWeight: FontWeight.w600),
        labelLarge: GoogleFonts.inter(color: textColorDarkGray, fontSize: 14, fontWeight: FontWeight.w500),
      ),
      extensions: [
        const FireplaceColors(
          inputBg: inputBgDarkGray,
          convItemBorder: convItemBorderDarkGray,
          convItemBg: convItemBgDarkGray,
          messagesAreaBg: messagesAreaBgDarkGray,
          mineMsgBg: mineMsgBgDarkGray,
          theirsMsgBg: theirsMsgBgDarkGray,
          settingsTileBg: Color(0xFF25262B),
          settingsTileBorder: settingsTileBorderDarkGray,
          tabBorder: tabBorderDarkGray,
          borderColor: accentDarkGray,
          mutedText: mutedDarkGray,
        ),
        GlassTheme.dark,
      ],
    );
  }

  /// Backwards compatibility alias.
  static ThemeData get themeData => themeDataBlue;

  static ThemeData get themeDataLight {
    return ThemeData.light().copyWith(
      scaffoldBackgroundColor: backgroundLight,
      colorScheme: const ColorScheme.light(
        primary: primaryLight,
        secondary: primaryLightHover,
        surface: boxBgLight,
        error: errorColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textColorLight,
        onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: boxBgLight,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: primaryLight,
          letterSpacing: -0.25,
        ),
        iconTheme: const IconThemeData(color: textColorLight),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputBgLight,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderSide: const BorderSide(color: tabBorderLight, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: tabBorderLight, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: primaryLight, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: errorColor, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        hintStyle: GoogleFonts.inter(color: mutedTextLight, fontSize: 14),
        labelStyle: GoogleFonts.inter(color: labelTextLight, fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryLight,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: primaryLight, width: 2),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryLight,
          textStyle: GoogleFonts.inter(fontSize: 14),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryLight,
        foregroundColor: Colors.white,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        tileColor: Colors.transparent,
        selectedTileColor: activeTabBgLight,
      ),
      dividerTheme: const DividerThemeData(
        color: convItemBorderLight,
        thickness: 1,
      ),
      textTheme: TextTheme(
        bodyLarge: GoogleFonts.inter(color: textColorLight, fontSize: 16),
        bodyMedium: GoogleFonts.inter(color: textColorLight, fontSize: 14),
        bodySmall: GoogleFonts.inter(color: textSecondaryLight, fontSize: 12),
        titleLarge: GoogleFonts.inter(
          color: primaryLight,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.25,
        ),
        titleMedium: GoogleFonts.inter(color: textColorLight, fontSize: 16, fontWeight: FontWeight.w600),
        titleSmall: GoogleFonts.inter(color: textColorLight, fontSize: 14, fontWeight: FontWeight.w600),
        labelLarge: GoogleFonts.inter(color: textColorLight, fontSize: 14, fontWeight: FontWeight.w500),
      ),
      extensions: [
        const FireplaceColors(
          inputBg: inputBgLight,
          convItemBorder: convItemBorderLight,
          convItemBg: convItemBgLight,
          messagesAreaBg: messagesAreaBgLight,
          mineMsgBg: mineMsgBgLight,
          theirsMsgBg: theirsMsgBgLight,
          settingsTileBg: boxBgLight,
          settingsTileBorder: convItemBorderLight,
          tabBorder: tabBorderLight,
          borderColor: primaryLight,
          mutedText: textSecondaryLight,
        ),
        GlassTheme.light,
      ],
    );
  }

  /// Teal + stone — light modern messenger (stone neutrals, teal accent, solid teal sent bubble + white text).
  static ThemeData get themeDataTealStone {
    return ThemeData.light().copyWith(
      scaffoldBackgroundColor: backgroundTealStone,
      colorScheme: const ColorScheme.light(
        primary: primaryTealStone,
        secondary: secondaryTealStone,
        surface: surfaceTealStone,
        error: errorColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textColorTealStone,
        onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceTealStone,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: primaryTealStone,
          letterSpacing: -0.25,
        ),
        iconTheme: const IconThemeData(color: textColorTealStone),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputBgTealStone,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderSide: const BorderSide(color: borderTealStone, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: borderTealStone, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: primaryTealStone, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: errorColor, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        hintStyle: GoogleFonts.inter(color: mutedTealStone, fontSize: 14),
        labelStyle: GoogleFonts.inter(color: mutedTealStone, fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: secondaryTealStone,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: secondaryTealStone, width: 2),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryTealStone,
          textStyle: GoogleFonts.inter(fontSize: 14),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: secondaryTealStone,
        foregroundColor: Colors.white,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        tileColor: Colors.transparent,
        selectedTileColor: activeTabBgTealStone,
      ),
      dividerTheme: const DividerThemeData(
        color: borderTealStone,
        thickness: 1,
      ),
      textTheme: TextTheme(
        bodyLarge: GoogleFonts.inter(color: textColorTealStone, fontSize: 16),
        bodyMedium: GoogleFonts.inter(color: textColorTealStone, fontSize: 14),
        bodySmall: GoogleFonts.inter(color: mutedTealStone, fontSize: 12),
        titleLarge: GoogleFonts.inter(
          color: primaryTealStone,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.25,
        ),
        titleMedium: GoogleFonts.inter(
          color: textColorTealStone,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        titleSmall: GoogleFonts.inter(
          color: textColorTealStone,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        labelLarge: GoogleFonts.inter(
          color: textColorTealStone,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      extensions: [
        FireplaceColors(
          inputBg: inputBgTealStone,
          convItemBorder: borderTealStone,
          convItemBg: convItemBgTealStone,
          messagesAreaBg: messagesAreaTealStone,
          mineMsgBg: mineMsgBgTealStone,
          theirsMsgBg: theirsMsgBgTealStone,
          settingsTileBg: surfaceTealStone,
          settingsTileBorder: settingsTileBorderTealStone,
          tabBorder: borderTealStone,
          borderColor: primaryTealStone,
          mutedText: mutedTealStone,
        ),
        GlassTheme.teal,
      ],
    );
  }

  static InputDecoration rpgInputDecoration({
    String? hintText,
    IconData? prefixIcon,
    BuildContext? context,
  }) {
    final iconColor = context != null
        ? (Theme.of(context).extension<FireplaceColors>()?.mutedText ??
            (isDark(context) ? mutedDark : textSecondaryLight))
        : mutedText;
    return InputDecoration(
      hintText: hintText,
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, color: iconColor, size: 20)
          : null,
    );
  }
}
