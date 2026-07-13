import 'package:flutter/material.dart';
import 'package:fireplace/l10n/app_localizations.dart';

import 'package:fireplace/screens/user_card_screen.dart';
import 'package:fireplace/theme/rpg_theme.dart';

void main() {
  runApp(const _UserCardPreviewApp());
}

class _UserCardPreviewApp extends StatefulWidget {
  const _UserCardPreviewApp();

  @override
  State<_UserCardPreviewApp> createState() => _UserCardPreviewAppState();
}

class _UserCardPreviewAppState extends State<_UserCardPreviewApp> {
  var _fixtureIndex = 0;
  var _lightTheme = false;

  static const _fixtures = [
    UserCardVisualData(
      username: 'ash',
      tag: '4821',
      about: 'Keeps a quiet fire and a shorter contact list.',
      isSelf: false,
      hasConversation: false,
    ),
    UserCardVisualData(
      username: 'mira',
      tag: '0317',
      about: 'Collecting small rituals, old maps, and perfect rainy afternoons.',
      isSelf: false,
      hasConversation: true,
      wallpaper: UserCardWallpaper.glyphs,
      mute: UserCardMute.eightHours,
      photos: [
        UserCardPhoto(
          semanticLabel: 'Mira beside a warm stone fireplace',
          url: 'https://images.unsplash.com/photo-1484154218962-a197022b5858',
        ),
        UserCardPhoto(
          semanticLabel: 'Mira in a sunlit study',
          url: 'https://images.unsplash.com/photo-1513519245088-0e12902e5a38',
        ),
        UserCardPhoto(
          semanticLabel: 'Mira at a quiet table',
          url: 'https://images.unsplash.com/photo-1510798831971-661eb04b3739',
        ),
      ],
    ),
    UserCardVisualData(
      username: 'ember',
      tag: '7004',
      about: 'Building Fireplace one careful surface at a time.',
      isSelf: true,
      hasConversation: false,
      photos: [
        UserCardPhoto(
          semanticLabel: 'Primary profile photo: an orange reading chair',
          url: 'https://images.unsplash.com/photo-1505693416388-ac5ce068fe85',
        ),
        UserCardPhoto(
          semanticLabel: 'Second profile photo: warm lamp light',
          url: 'https://images.unsplash.com/photo-1513506003901-1e6a229e2d15',
        ),
      ],
    ),
  ];

  void _moveFixture(int delta) {
    setState(() {
      _fixtureIndex = (_fixtureIndex + delta) % _fixtures.length;
      if (_fixtureIndex < 0) _fixtureIndex += _fixtures.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final labels = ['No avatar', 'Contact + gallery', 'My Profile'];
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: _lightTheme ? RpgTheme.themeDataTealStone : RpgTheme.themeDataDarkGray,
      home: Scaffold(
        body: Stack(
          children: [
            UserCardScreen(data: _fixtures[_fixtureIndex]),
            Positioned(
              left: 16,
              right: 16,
              bottom: 20,
              child: SafeArea(
                top: false,
                child: Center(
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(99),
                    elevation: 12,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Previous preview state',
                            color: Colors.white,
                            onPressed: () => _moveFixture(-1),
                            icon: const Icon(Icons.arrow_back_ios_new),
                          ),
                          ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 144),
                            child: Text(
                              '${_fixtureIndex + 1}/3 · ${labels[_fixtureIndex]}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Next preview state',
                            color: Colors.white,
                            onPressed: () => _moveFixture(1),
                            icon: const Icon(Icons.arrow_forward_ios),
                          ),
                          const SizedBox(width: 2),
                          IconButton(
                            tooltip: _lightTheme ? 'Use dark theme' : 'Use light theme',
                            color: Colors.white,
                            onPressed: () => setState(() => _lightTheme = !_lightTheme),
                            icon: Icon(_lightTheme ? Icons.dark_mode_outlined : Icons.light_mode_outlined),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
