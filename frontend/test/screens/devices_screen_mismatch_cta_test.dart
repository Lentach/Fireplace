// Amendment (lxiv) clause 2 — the banner's promised recovery must be REACHABLE.
//
// Live QA (2026-08-31) found the dead end this file pins: a revoked device
// that signs back in is NOT keyless (its stale Signal material survived), so
// gating the device-side §5.1 CTA on `identityIncomplete` alone routed exactly
// the mismatched install — the one the banner sends here — to the PRIMARY-side
// "enter code" flow it can never complete (it holds no DAK). The screen must
// offer "link this device" for BOTH shapes of unusable material: none at all,
// and (lxiv) stamped-for-another-device.
//
// The provider getters are faked HERE ONLY; the real state -> getter join is
// covered by test/providers/device_material_mismatch_test.dart (same split as
// device_mismatch_banner_test.dart).

import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/models/user_model.dart';
import 'package:fireplace/providers/auth_provider.dart';
import 'package:fireplace/providers/connection_provider.dart';
import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/screens/devices_screen.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _FakeAuthProvider extends AuthProvider {
  @override
  UserModel? get currentUser => UserModel(id: 7, username: 'qa', tag: '0001');
}

class _FakeConnectionProvider extends ConnectionProvider {
  @override
  int? get currentUserId => 7;
}

class _FakeEncryptionProvider extends EncryptionProvider {
  _FakeEncryptionProvider({required this.mismatch, required this.incomplete});

  final bool mismatch;
  final bool incomplete;

  @override
  bool get deviceMaterialMismatch => mismatch;

  @override
  bool get identityIncomplete => incomplete;
}

Widget _host(EncryptionProvider encryption) => MultiProvider(
  providers: [
    ChangeNotifierProvider<AuthProvider>(create: (_) => _FakeAuthProvider()),
    ChangeNotifierProvider<ConnectionProvider>(
      create: (_) => _FakeConnectionProvider(),
    ),
    ChangeNotifierProvider<EncryptionProvider>.value(value: encryption),
  ],
  child: MaterialApp(
    theme: RpgTheme.themeDataDarkGray,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const DevicesScreen(),
  ),
);

void main() {
  testWidgets(
    'device-material mismatch offers the device-side ceremony, not the '
    'primary flow',
    (tester) async {
      await tester.pumpWidget(
        _host(_FakeEncryptionProvider(mismatch: true, incomplete: false)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('devices-link-this-device')), findsOneWidget);
      expect(find.byKey(const Key('devices-link-a-device')), findsNothing);
      expect(find.byKey(const Key('devices-enable-linking')), findsNothing);
    },
  );

  testWidgets('keyless install still gets the device-side ceremony', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_FakeEncryptionProvider(mismatch: false, incomplete: true)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('devices-link-this-device')), findsOneWidget);
    expect(find.byKey(const Key('devices-link-a-device')), findsNothing);
  });
}
