import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Theme-specific colors for chat UI. Use via Theme.of(context).extension<FireplaceColors>()!
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
  ThemeExtension<FireplaceColors> copyWith({/* unused */}) => this;

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
  static const Color mineMsgBg = Color(0xFF1A1A50);
  static const Color theirsMsgBg = Color(0xFF121240);

  // Dark mode – primary accent, borders, muted
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
  static const Color mineMsgBgDarkGray = Color(0xFF2C2E33);
  static const Color theirsMsgBgDarkGray = Color(0xFF25262B);
  static const Color activeTabBgDarkGray = Color(0xFF2C2E33);
  static const Color timeColorDarkGray = Color(0xFF949798);
  static const Color settingsTileBorderDarkGray = Color(0xFF5C9EAD);

  // Light theme palette - modern neutral (Slack-inspired)
  static const Color primaryLight = Color(0xFF4A154B);
  static const Color primaryLightHover = Color(0xFF611F69);
  static const Color backgroundLight = Color(0xFFF4F5F7);
  static const Color boxBgLight = Color(0xFFFFFFFF);
  static const Color chatAreaBgLight = Color(0xFFFAFBFC);
  static const Color textColorLight = Color(0xFF1D1C1D);
  static const Color textSecondaryLight = Color(0xFF616061);
  static const Color mutedTextLight = Color(0xFF8B8A8B);
  static const Color labelTextLight = Color(0xFF4A4A6A);
  static const Color inputBgLight = Color(0xFFEEEEF2);
  static const Color tabBorderLight = Color(0xFFE8EAED);
  static const Color activeTabBgLight = Color(0xFFE8E4EC);
  static const Color buttonBgLight = Color(0xFF4A154B);
  static const Color convItemBgLight = Color(0xFFF0F0F5);
  static const Color convItemBorderLight = Color(0xFFE8EAED);
  static const Color messagesAreaBgLight = Color(0xFFFAFBFC);
  static const Color mineMsgBgLight = Color(0xFF4A154B);
  static const Color theirsMsgBgLight = Color(0xFFE8E4EC);
  static const Color timeColorLight = Color(0xFF616061);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color primaryColor(BuildContext context) =>
      isDark(context) ? accentDark : primaryLight;

  static Color surfaceColor(BuildContext context) =>
      isDark(context) ? boxBg : boxBgLight;

  static TextStyle pressStart2P({double fontSize = 10, Color color = textColor}) {
    return GoogleFonts.pressStart2p(
      fontSize: fontSize,
      color: color,
    );
  }

  static TextStyle bodyFont({double fontSize = 14, Color color = textColor, FontWeight fontWeight = FontWeight.normal}) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      color: color,
      fontWeight: fontWeight,
    );
  }

  /// Blue theme – red accents (current default dark).
  static ThemeData get themeDataBlue {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: accentDark,
        secondary: borderDark,
        surface: boxBg,
        error: errorColor,
        onPrimary: Color(0xFF0A0A2E),
        onSecondary: Colors.white,
        onSurface: textColor,
        onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: boxBg,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.pressStart2p(
          fontSize: 14,
          color: accentDark,
        ),
        iconTheme: const IconThemeData(color: textColor),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderSide: const BorderSide(color: tabBorderDark, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: tabBorderDark, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: accentDark, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: errorColor, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        hintStyle: GoogleFonts.inter(color: mutedDark, fontSize: 14),
        labelStyle: GoogleFonts.inter(color: mutedDark, fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonBgDark,
          foregroundColor: accentDark,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: accentDark, width: 2),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: borderDark,
          textStyle: GoogleFonts.inter(fontSize: 14),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accentDark,
        foregroundColor: Colors.white,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        tileColor: Colors.transparent,
        selectedTileColor: activeTabBgDark,
      ),
      dividerTheme: const DividerThemeData(
        color: convItemBorderDark,
        thickness: 1,
      ),
      textTheme: TextTheme(
        bodyLarge: GoogleFonts.inter(color: textColor, fontSize: 16),
        bodyMedium: GoogleFonts.inter(color: textColor, fontSize: 14),
        bodySmall: GoogleFonts.inter(color: mutedDark, fontSize: 12),
        titleLarge: GoogleFonts.pressStart2p(color: accentDark, fontSize: 16),
        titleMedium: GoogleFonts.inter(color: textColor, fontSize: 16, fontWeight: FontWeight.w600),
        titleSmall: GoogleFonts.inter(color: textColor, fontSize: 14, fontWeight: FontWeight.w600),
        labelLarge: GoogleFonts.inter(color: textColor, fontSize: 14, fontWeight: FontWeight.w500),
      ),
      extensions: [
        const FireplaceColors(
          inputBg: inputBg,
          convItemBorder: convItemBorderDark,
          convItemBg: convItemBgDark,
          messagesAreaBg: messagesAreaBg,
          mineMsgBg: mineMsgBg,
          theirsMsgBg: theirsMsgBg,
          settingsTileBg: convItemBgDark,
          settingsTileBorder: settingsTileBorderDark,
          tabBorder: tabBorderDark,
          borderColor: borderDark,
          mutedText: mutedDark,
        ),
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
        titleTextStyle: GoogleFonts.pressStart2p(
          fontSize: 14,
          color: accentDarkGray,
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
        titleLarge: GoogleFonts.pressStart2p(color: accentDarkGray, fontSize: 16),
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
        titleTextStyle: GoogleFonts.pressStart2p(
          fontSize: 14,
          color: primaryLight,
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
        titleLarge: GoogleFonts.pressStart2p(color: primaryLight, fontSize: 16),
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
      ],
    );
  }

  static InputDecoration rpgInputDecoration({
    String? hintText,
    IconData? prefixIcon,
    BuildContext? context,
  }) {
    final iconColor = context != null
        ? (isDark(context) ? mutedDark : textSecondaryLight)
        : mutedText;
    return InputDecoration(
      hintText: hintText,
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, color: iconColor, size: 20)
          : null,
    );
  }
}
