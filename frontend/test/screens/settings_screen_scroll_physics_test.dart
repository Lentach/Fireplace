import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/providers/auth_provider.dart';
import 'package:fireplace/providers/connection_provider.dart';
import 'package:fireplace/providers/settings_provider.dart';
import 'package:fireplace/screens/settings_screen.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/appearance_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _FakeUrlLauncher extends UrlLauncherPlatform {
  String? launchedUrl;
  LaunchOptions? launchOptions;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrl = url;
    launchOptions = options;
    return true;
  }
}

Widget _settingsApp({Locale locale = const Locale('en')}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider(create: (_) => ConnectionProvider()),
      ChangeNotifierProvider(create: (_) => SettingsProvider()),
    ],
    child: MaterialApp(
      theme: RpgTheme.themeDataLight,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const SettingsScreen(),
    ),
  );
}

void main() {
  testWidgets('SettingsScreen uses ClampingScrollPhysics for its ListView', (
    tester,
  ) async {
    await tester.pumpWidget(_settingsApp());

    await tester.pump();

    final listView = tester.widget<ListView>(find.byType(ListView).first);
    expect(listView.physics, isA<ClampingScrollPhysics>());
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.byType(AppearancePreview), findsOneWidget);
    expect(find.text('Theme'), findsNothing);
    expect(find.text('Chat background'), findsNothing);
    expect(find.text('Starfield background'), findsNothing);
  });

  testWidgets('SettingsScreen shows a compact localized About link', (
    tester,
  ) async {
    final previousLauncher = UrlLauncherPlatform.instance;
    final fakeLauncher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = fakeLauncher;
    addTearDown(() => UrlLauncherPlatform.instance = previousLauncher);

    await tester.pumpWidget(_settingsApp());
    await tester.pump();

    final link = find.byKey(const Key('settings-about-fireplace-link'));
    await tester.scrollUntilVisible(
      link,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -100));
    await tester.pump();

    expect(find.text('About'), findsOneWidget);
    expect(tester.widget<InkWell>(link).onTap, isNotNull);
    await tester.tap(link);
    await tester.pump();
    expect(
      fakeLauncher.launchedUrl,
      'https://fireplace.ignorelist.com/welcome/',
    );
    expect(
      fakeLauncher.launchOptions?.mode,
      PreferredLaunchMode.externalApplication,
    );
    expect(
      find.descendant(
        of: link,
        matching: find.byIcon(Icons.north_east_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: link, matching: find.byIcon(Icons.public)),
      findsNothing,
    );
    expect(
      find.descendant(of: link, matching: find.byIcon(Icons.palette)),
      findsNothing,
    );
    expect(
      find.descendant(of: link, matching: find.byIcon(Icons.auto_awesome)),
      findsNothing,
    );
    expect(
      find.descendant(of: link, matching: find.byIcon(Icons.star)),
      findsNothing,
    );

    await tester.pumpWidget(_settingsApp(locale: const Locale('pl')));
    await tester.pump();
    await tester.scrollUntilVisible(
      link,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('O projekcie'), findsOneWidget);
  });
}
