// Visual preview for the Cosmic theme starfield — STATIC layout (no auto-scroll)
// so the twinkle/dimming is the only motion. Used for before/after screenshots
// and the dimming screen-recording.
//
// Web:    flutter run -d web-server --web-port 8098 -t tool/starfield_preview.dart
//         then open  http://localhost:8098/?theme=cosmic  (or ?theme=blue for before)
// Mobile: flutter run -d <android> -t tool/starfield_preview.dart
import 'package:flutter/material.dart';

import 'package:fireplace/theme/cosmic_theme.dart';
import 'package:fireplace/theme/glass_theme.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/chat_background_pattern.dart';

void main() => runApp(const _PreviewApp());

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    final q = Uri.base.queryParameters;
    var theme = switch (q['theme']) {
      'blue' => RpgTheme.themeDataBlue,
      'dark' => RpgTheme.themeDataDarkGray,
      _ => RpgTheme.themeDataCosmic,
    };
    // ?density=N overrides the starfield star count (for the owner density A/B).
    final d = int.tryParse(q['density'] ?? '');
    if (d != null && theme.extension<CosmicBackdrop>() != null) {
      theme = theme.copyWith(extensions: [
        theme.extension<FireplaceColors>()!,
        theme.extension<GlassTheme>()!,
        CosmicBackdrop.starfield.copyWith(density: d),
      ]);
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: _PreviewPage(label: d != null ? 'density $d' : null),
    );
  }
}

class _PreviewPage extends StatelessWidget {
  final String? label;
  const _PreviewPage({this.label});

  @override
  Widget build(BuildContext context) {
    final fc = FireplaceColors.of(context);
    final cs = Theme.of(context).colorScheme;
    Widget bubble(String text, bool mine) => Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            constraints: const BoxConstraints(maxWidth: 280),
            decoration: BoxDecoration(
              color: mine ? fc.mineMsgBg : fc.theirsMsgBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              text,
              style: TextStyle(
                color: mine ? Colors.white : const Color(0xFFCFE2F2),
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: Text(label == null ? 'Nova · Cosmic' : 'Cosmic · $label')),
      body: ChatBackgroundPattern(
        backgroundColor: fc.messagesAreaBg,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('Today',
                    style: TextStyle(color: cs.onSurface, fontSize: 12)),
              ),
            ),
            const Spacer(),
            bubble('the stars over here never stop moving ✨', false),
            bubble('that is the whole point — they breathe', true),
            bubble('sealed end to end, still pretty', false),
            bubble('routes everything, reads nothing', true),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
