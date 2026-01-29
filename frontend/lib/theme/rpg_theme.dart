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

  static TextStyle pressStart2P({double fontSize = 10, Color color = textColor}) {
    return GoogleFonts.pressStart2p(
      fontSize: fontSize,
      color: color,
    );
  }

  static BoxDecoration rpgBoxDecoration() {
    return BoxDecoration(
      color: boxBg,
      border: Border.all(color: border, width: 4),
      borderRadius: BorderRadius.circular(2),
      boxShadow: const [
        BoxShadow(color: Color(0x881A1A5E), blurRadius: 20),
      ],
    );
  }

  static BoxDecoration rpgOuterBorderDecoration() {
    return BoxDecoration(
      border: Border.all(color: outerBorder, width: 3),
      borderRadius: BorderRadius.circular(4),
    );
  }

  static InputDecoration rpgInputDecoration({String? hintText}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: pressStart2P(fontSize: 9, color: mutedText),
      filled: true,
      fillColor: inputBg,
      contentPadding: const EdgeInsets.all(10),
      border: OutlineInputBorder(
        borderSide: const BorderSide(color: tabBorder, width: 2),
        borderRadius: BorderRadius.zero,
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: tabBorder, width: 2),
        borderRadius: BorderRadius.zero,
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: gold, width: 2),
        borderRadius: BorderRadius.zero,
      ),
    );
  }
}
