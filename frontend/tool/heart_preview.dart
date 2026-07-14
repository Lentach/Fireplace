import 'package:flutter/material.dart';

import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/utils/jumbo_emoji.dart';
import 'package:fireplace/widgets/emoji/fireplace_emoji_picker.dart';

// Visual proof for the red-heart fix. Renders the REAL fixed render paths under
// the app's RpgTheme (ambient Inter) — the exact conditions that produced the
// white heart before the fix.
// Run/build: flutter build web --release -t tool/heart_preview.dart
void main() {
  runApp(const _HeartProofApp());
}

class _HeartProofApp extends StatelessWidget {
  const _HeartProofApp();

  @override
  Widget build(BuildContext context) {
    const heart = '\u2764\uFE0F';
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: RpgTheme.themeDataBlue,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('jumbo bubble (withEmojiFont):'),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: RichText(
                  text: TextSpan(
                    style: withEmojiFont(
                      RpgTheme.bodyFont(fontSize: 48, color: Colors.white),
                    ),
                    children: const [TextSpan(text: heart)],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('inline / preview (buildInlineEmojiSpans):'),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text.rich(
                  TextSpan(
                    children: buildInlineEmojiSpans(
                      'love it $heart and \u{1F525}',
                      textStyle: RpgTheme.bodyFont(
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('picker suggested row + grid (FireplaceEmojiPicker):'),
              ),
              Expanded(
                child: FireplaceEmojiPicker(
                  onEmojiSelected: (_) {},
                  onBackspacePressed: () {},
                  height: 320,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
