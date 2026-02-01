import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class RpgTheme {
  // Colors
  static const Color background = Color(0xFF0A0A2E);
  static const Color boxBg = Color(0xFF0F0F3D);
  static const Color gold = Color(0xFFFFCC00);
  static const Color purple = Color(0xFF7B7BF5);
  static const Color border = Color(0xFF4A4AE0);
  static const Color inputBg = Color(0xFF0A0A24);
  static const Color textColor = Color(0xFFE0E0E0);
  static const Color mutedText = Color(0xFF6A6AB0);
  static const Color labelText = Color(0xFF9999DD);
  static const Color tabBg = Color(0xFF1A1A4E);
  static const Color tabBorder = Color(0xFF3A3A8A);
  static const Color activeTabBg = Color(0xFF2A2A8E);
  static const Color buttonBg = Color(0xFF2A2A8E);
  static const Color buttonHoverBg = Color(0xFF3A3A9E);
  static const Color errorColor = Color(0xFFFF4444);
  static const Color successColor = Color(0xFF44FF44);
  static const Color headerGreen = Color(0xFF44FF44);
  static const Color logoutRed = Color(0xFFFF6666);
  static const Color convItemBg = Color(0xFF1A1A4E);
  static const Color convItemBorder = Color(0xFF2A2A6E);
  static const Color messagesAreaBg = Color(0xFF08081E);
  static const Color mineMsgBg = Color(0xFF1A1A50);
  static const Color theirsMsgBg = Color(0xFF121240);
  static const Color outerBorder = Color(0xFF2A2A7A);
  static const Color timeColor = Color(0xFF5555AA);

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
      isDark(context) ? gold : primaryLight;

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

  static ThemeData get themeData {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: gold,
        secondary: purple,
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
          color: gold,
        ),
        iconTheme: const IconThemeData(color: textColor),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderSide: const BorderSide(color: tabBorder, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: tabBorder, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: gold, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: errorColor, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        hintStyle: GoogleFonts.inter(color: mutedText, fontSize: 14),
        labelStyle: GoogleFonts.inter(color: labelText, fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonBg,
          foregroundColor: gold,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: gold, width: 2),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: purple,
          textStyle: GoogleFonts.inter(fontSize: 14),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: purple,
        foregroundColor: Colors.white,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        tileColor: Colors.transparent,
        selectedTileColor: activeTabBg,
      ),
      dividerTheme: const DividerThemeData(
        color: convItemBorder,
        thickness: 1,
      ),
      textTheme: TextTheme(
        bodyLarge: GoogleFonts.inter(color: textColor, fontSize: 16),
        bodyMedium: GoogleFonts.inter(color: textColor, fontSize: 14),
        bodySmall: GoogleFonts.inter(color: mutedText, fontSize: 12),
        titleLarge: GoogleFonts.pressStart2p(color: gold, fontSize: 16),
        titleMedium: GoogleFonts.inter(color: textColor, fontSize: 16, fontWeight: FontWeight.w600),
        titleSmall: GoogleFonts.inter(color: textColor, fontSize: 14, fontWeight: FontWeight.w600),
        labelLarge: GoogleFonts.inter(color: textColor, fontSize: 14, fontWeight: FontWeight.w500),
      ),
    );
  }

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
    );
  }

  static InputDecoration rpgInputDecoration({
    String? hintText,
    IconData? prefixIcon,
    BuildContext? context,
  }) {
    final iconColor = context != null
        ? (isDark(context) ? mutedText : textSecondaryLight)
        : mutedText;
    return InputDecoration(
      hintText: hintText,
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, color: iconColor, size: 20)
          : null,
    );
  }
}
