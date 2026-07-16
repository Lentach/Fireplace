// Throwaway visual harness for the user card rework (dev-only, NOT part of
// the test suite; run:
//   flutter run -d web-server -t test/preview/user_card_preview.dart
// ?theme=blue|dark|light|teal picks the theme; ?variant=self|other|noPhoto;
// ?style=panels|frosted|aurora picks the round-2 body style.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/providers/auth_provider.dart';
import 'package:fireplace/providers/friends_provider.dart';
import 'package:fireplace/screens/user_card_screen.dart';
import 'package:fireplace/theme/rpg_theme.dart';

void main() => runApp(const UserCardPreviewApp());

ThemeData _theme(String name) => switch (name) {
  'blue' => RpgTheme.themeDataBlue,
  'light' => RpgTheme.themeDataLight,
  'teal' => RpgTheme.themeDataTealStone,
  _ => RpgTheme.themeDataDarkGray,
};

class UserCardPreviewApp extends StatelessWidget {
  const UserCardPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    final params = Uri.base.queryParameters;
    final themeName = params['theme'] ?? 'dark';
    final variant = params['variant'] ?? 'self';
    final style = switch (params['style']) {
      'panels' => UserCardStyle.glassPanels,
      'aurora' => UserCardStyle.auroraTint,
      _ => UserCardStyle.frostedBackdrop,
    };

    // Deliberately mixed aspects: square, portrait, landscape — the round-3
    // adaptive hero must size itself to each without bars or crop.
    final photos = [
      const UserCardPhoto(
        id: 1,
        url: 'https://picsum.photos/seed/fireplace1/900/900',
        isPrimary: true,
        semanticLabel: 'bob208#9939',
      ),
      const UserCardPhoto(
        id: 2,
        url: 'https://picsum.photos/seed/fireplace2/800/1200',
        semanticLabel: 'bob208#9939',
      ),
      const UserCardPhoto(
        id: 3,
        url: 'https://picsum.photos/seed/fireplace3/1200/700',
        semanticLabel: 'bob208#9939',
      ),
    ];

    final data = switch (variant) {
      'other' => UserCardVisualData(
        userId: 2,
        username: 'maoi',
        tag: '3049',
        about: 'see you by the fire',
        isSelf: false,
        hasConversation: true,
        photos: photos,
      ),
      'noPhoto' => const UserCardVisualData(
        userId: 3,
        username: 'Princepolo',
        tag: '1422',
        isSelf: false,
        hasConversation: true,
      ),
      _ => UserCardVisualData(
        userId: 1,
        username: 'bob208',
        tag: '9939',
        about: 'just a random bob',
        isSelf: true,
        hasConversation: false,
        photos: photos,
      ),
    };

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => FriendsProvider()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(themeName),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: UserCardScreen(data: data, onMessage: () {}, style: style),
      ),
    );
  }
}
