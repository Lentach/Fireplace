import 'package:fireplace/config/app_version_info.dart';
import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/providers/auth_provider.dart';
import 'package:fireplace/providers/connection_provider.dart';
import 'package:fireplace/providers/passcode_provider.dart';
import 'package:fireplace/providers/settings_provider.dart';
import 'package:fireplace/screens/settings_screen.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../support/passcode_fakes.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    AppVersionInfo.debugResetForTest();
    PackageInfo.setMockInitialValues(
      appName: 'fireplace',
      packageName: 'com.fireplace.app',
      version: '0.0.2',
      buildNumber: '42',
      buildSignature: '',
    );
  });

  testWidgets('SettingsScreen shows app version footer line', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => ConnectionProvider()),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          // The SECURITY section carries the Passcode Lock row.
          ChangeNotifierProvider(
            create: (_) => PasscodeProvider(
              store: MemoryPasscodeStore(),
              kdf: FakePasscodeKdf(),
            ),
          ),
        ],
        child: MaterialApp(
          theme: RpgTheme.themeDataLight,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SettingsScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    final listView = find.byType(ListView);
    await tester.drag(listView, const Offset(0, -800));
    await tester.pumpAndSettle();

    expect(find.textContaining('0.0.2'), findsOneWidget);
    expect(find.textContaining('+'), findsNothing);
    expect(find.textContaining('dev'), findsOneWidget);
  });
}
