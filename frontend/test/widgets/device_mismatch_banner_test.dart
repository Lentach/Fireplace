// Amendment (lxiv) clause 2 — the mismatch state must REACH THE USER.
//
// The provider refusing E2E duty is proven in
// test/providers/device_material_mismatch_test.dart against the real engine.
// This file pins the surface: the banner renders exactly when
// `deviceMaterialMismatch` is set, names the way out (re-linking), and stays
// out of the tree otherwise. The provider getter is faked HERE ONLY because
// the join (real state -> real getter) is covered by the provider file — the
// same split as identity_banners_test.dart.

import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/widgets/device_mismatch_banner.dart';
import 'package:fireplace/widgets/identity_alert_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _FakeEncryptionProvider extends EncryptionProvider {
  _FakeEncryptionProvider(this.mismatch);
  final bool mismatch;

  @override
  bool get deviceMaterialMismatch => mismatch;
}

Widget _host(EncryptionProvider provider) =>
    ChangeNotifierProvider<EncryptionProvider>.value(
      value: provider,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: DeviceMismatchBanner()),
      ),
    );

void main() {
  testWidgets('renders the alert with the re-link action while mismatched', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_FakeEncryptionProvider(true)));
    await tester.pumpAndSettle();

    expect(find.byType(IdentityAlertBanner), findsOneWidget);
    expect(
      find.text('This device was removed from the account'),
      findsOneWidget,
    );
    // The way out must never be behind a disclosure: a warning without a
    // reachable repair is the D1 dead-end shape this programme already paid for.
    expect(find.text('Link this device'), findsOneWidget);
  });

  testWidgets('stays out of the tree when the install is healthy', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_FakeEncryptionProvider(false)));
    await tester.pumpAndSettle();

    expect(find.byType(IdentityAlertBanner), findsNothing);
  });
}
