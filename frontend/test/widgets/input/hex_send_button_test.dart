import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/input/hex_send_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The send glyph must be derived from the accent, never hardcoded.
///
/// The circular predecessor painted `Colors.white` on `colorScheme.primary`,
/// which lands at 1.56:1 on `cosmic` (#8FD8FF), 2.57:1 on `blue` (#2AABEE)
/// and 3.02:1 on `dark` (#5C9EAD) — all below the 3:1 non-text gate, and on
/// cosmic effectively invisible. Re-hardcoding white turns these red.
Future<Color> _glyphColor(WidgetTester tester, ThemeData theme) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: const Scaffold(body: Center(child: HexSendButton())),
    ),
  );
  await tester.pump();
  return tester.widget<Icon>(find.byIcon(Icons.send_rounded)).color!;
}

void main() {
  testWidgets('pale accents get a dark glyph, not white', (tester) async {
    for (final theme in [
      RpgTheme.themeDataCosmic,
      RpgTheme.themeDataBlue,
      RpgTheme.themeDataDarkGray,
    ]) {
      final accent = theme.colorScheme.primary;
      expect(
        await _glyphColor(tester, theme),
        RpgTheme.readableOn(accent),
        reason: 'accent $accent needs the contrast-readable glyph',
      );
      expect(await _glyphColor(tester, theme), isNot(Colors.white));
    }
  });

  testWidgets('deep accents keep the white glyph', (tester) async {
    for (final theme in [
      RpgTheme.themeDataLight,
      RpgTheme.themeDataTealStone,
    ]) {
      expect(await _glyphColor(tester, theme), Colors.white);
    }
  });
}
