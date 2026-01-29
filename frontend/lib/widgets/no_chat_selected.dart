import 'package:flutter/material.dart';
import '../theme/rpg_theme.dart';

class NoChatSelected extends StatelessWidget {
  const NoChatSelected({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Select a party member\nor start a new quest\n\n\u2694\uFE0F',
        textAlign: TextAlign.center,
        style: RpgTheme.pressStart2P(
          fontSize: 9,
          color: RpgTheme.tabBorder,
        ).copyWith(height: 2),
      ),
    );
  }
}
