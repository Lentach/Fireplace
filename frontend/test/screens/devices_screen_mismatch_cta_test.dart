// Amendment (lxiv) clause 2 / (lxvii) clause 2 — the banner's promised recovery
// must be REACHABLE.
//
// Live QA (2026-08-31) found the dead end this file pins: a revoked device
// that signs back in is NOT keyless (its stale Signal material survived), so
// gating the device-side §5.1 CTA on `identityIncomplete` alone routed exactly
// the mismatched install — the one the banner sends here — to the PRIMARY-side
// "enter code" flow it can never complete (it holds no DAK). The 2026-09-02
// probe found the third shape: a keyless install that took "start fresh" holds
// an identity the registration lock refused, `identityIncomplete` clears, and
// the CTA vanished — leaving a 72 h reset as the only door. The screen must
// offer "link this device" for every shape of unusable material: none at all,
// (lxiv) stamped-for-another-device, and (lxvii) lock-refused.
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
import 'package:fireplace/services/device_link/link_ceremony_controller.dart';
import 'package:fireplace/services/device_list/device_list_canonical.dart';
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

  /// The screen's own controller, captured so a test can put it into an
  /// enrolled/chain-invalid state without a wire.
  LinkCeremonyController? sink;

  @override
  void registerProvisioningSink(ProvisioningEventSink sink) {
    this.sink = sink as LinkCeremonyController;
    super.registerProvisioningSink(sink);
  }
}

class _FakeEncryptionProvider extends EncryptionProvider {
  _FakeEncryptionProvider({
    required this.mismatch,
    required this.incomplete,
    this.locked = false,
  });

  final bool mismatch;
  final bool incomplete;
  final bool locked;

  @override
  bool get deviceMaterialMismatch => mismatch;

  @override
  bool get identityIncomplete => incomplete;

  @override
  bool get identityUploadLocked => locked;
}

_FakeConnectionProvider _connection = _FakeConnectionProvider();

Widget _host(EncryptionProvider encryption) {
  _connection = _FakeConnectionProvider();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => _FakeAuthProvider()),
      ChangeNotifierProvider<ConnectionProvider>.value(value: _connection),
      ChangeNotifierProvider<EncryptionProvider>.value(value: encryption),
    ],
    child: MaterialApp(
      theme: RpgTheme.themeDataDarkGray,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const DevicesScreen(),
    ),
  );
}

const _enrolledList = DeviceList(
  userId: 7,
  version: 3,
  devices: [
    DeviceListEntry(deviceId: 1, platform: 'android', addedAtMs: 1000),
    DeviceListEntry(deviceId: 6, platform: 'web', addedAtMs: 2000),
  ],
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

  testWidgets(
    'a lock-refused identity offers the device-side ceremony, not the '
    'primary flow',
    (tester) async {
      await tester.pumpWidget(
        _host(
          _FakeEncryptionProvider(
            mismatch: false,
            incomplete: false,
            locked: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('devices-link-this-device')), findsOneWidget);
      expect(find.byKey(const Key('devices-link-a-device')), findsNothing);
      expect(find.byKey(const Key('devices-enable-linking')), findsNothing);
    },
  );

  // Amendment (lxviii) clause 3 — a keyless install is not shown a chain
  // failure above the CTA that is its whole message.
  testWidgets('keyless: the chain-invalid line is NOT rendered', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_FakeEncryptionProvider(mismatch: false, incomplete: true)),
    );
    await tester.pumpAndSettle();
    final controller = _connection.sink!;
    controller.listState = DeviceListState.chainInvalid;
    controller.listFailureReason = 'no_local_identity';
    controller.notifyListeners();
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    expect(find.text(l10n.devicesChainInvalid), findsNothing);
    expect(find.text(l10n.devicesThisDeviceKeyless), findsOneWidget);
    expect(find.byKey(const Key('devices-link-this-device')), findsOneWidget);
  });

  testWidgets('healthy: a genuine chain failure IS still rendered', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_FakeEncryptionProvider(mismatch: false, incomplete: false)),
    );
    await tester.pumpAndSettle();
    final controller = _connection.sink!;
    controller.listState = DeviceListState.chainInvalid;
    controller.listFailureReason = 'bad_signature';
    controller.notifyListeners();
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    expect(find.text(l10n.devicesChainInvalid), findsOneWidget);
  });

  // Amendment (lxviii) clause 2 — only the DAK holder is offered the primary
  // flow; a linked device is told where linking happens.
  group('enrolled', () {
    Future<LinkCeremonyController> pumpEnrolled(
      WidgetTester tester, {
      required bool? holdsDak,
    }) async {
      await tester.pumpWidget(
        _host(_FakeEncryptionProvider(mismatch: false, incomplete: false)),
      );
      await tester.pumpAndSettle();
      final controller = _connection.sink!;
      controller.listState = DeviceListState.enrolled;
      controller.verifiedList = _enrolledList;
      controller.holdsDak = holdsDak;
      controller.notifyListeners();
      await tester.pumpAndSettle();
      return controller;
    }

    testWidgets('the primary (DAK holder) is offered "link a device"', (
      tester,
    ) async {
      await pumpEnrolled(tester, holdsDak: true);
      expect(find.byKey(const Key('devices-link-a-device')), findsOneWidget);
      expect(find.byKey(const Key('devices-linked-device-note')), findsNothing);
    });

    testWidgets('a linked device (no DAK) gets the note, not the flow', (
      tester,
    ) async {
      await pumpEnrolled(tester, holdsDak: false);
      expect(find.byKey(const Key('devices-link-a-device')), findsNothing);
      expect(
        find.byKey(const Key('devices-linked-device-note')),
        findsOneWidget,
      );
      // Neither the device-side CTA: this install is linked and healthy.
      expect(find.byKey(const Key('devices-link-this-device')), findsNothing);
    });

    testWidgets('unresolved DAK presence offers nothing yet', (tester) async {
      await pumpEnrolled(tester, holdsDak: null);
      expect(find.byKey(const Key('devices-link-a-device')), findsNothing);
      expect(find.byKey(const Key('devices-linked-device-note')), findsNothing);
    });

    // Amendment (lxix) — tombstones are permanent in the signed bytes (§3:
    // ids are never reused), so the SCREEN collapses them: live rows lead,
    // revoked rows sit behind one disclosure, and the ordering is by liveness
    // first, never by id alone.
    group('revoked tombstones', () {
      const withTombstones = DeviceList(
        userId: 7,
        version: 9,
        devices: [
          DeviceListEntry(deviceId: 1, platform: 'android', addedAtMs: 1000),
          DeviceListEntry(
            deviceId: 2,
            platform: 'web',
            addedAtMs: 2000,
            revokedAtMs: 2500,
          ),
          DeviceListEntry(
            deviceId: 3,
            platform: 'web',
            addedAtMs: 3000,
            revokedAtMs: 3500,
          ),
          DeviceListEntry(deviceId: 4, platform: 'web', addedAtMs: 4000),
        ],
      );

      Future<void> pumpTombstones(WidgetTester tester) async {
        await tester.pumpWidget(
          _host(_FakeEncryptionProvider(mismatch: false, incomplete: false)),
        );
        await tester.pumpAndSettle();
        final controller = _connection.sink!;
        controller.listState = DeviceListState.enrolled;
        controller.verifiedList = withTombstones;
        controller.holdsDak = true;
        controller.notifyListeners();
        await tester.pumpAndSettle();
      }

      testWidgets('collapsed by default: live rows only, counted toggle', (
        tester,
      ) async {
        await pumpTombstones(tester);
        expect(find.byKey(const Key('device-row-1')), findsOneWidget);
        expect(find.byKey(const Key('device-row-4')), findsOneWidget);
        expect(find.byKey(const Key('device-row-2')), findsNothing);
        expect(find.byKey(const Key('device-row-3')), findsNothing);
        expect(find.text('Revoked devices (2)'), findsOneWidget);
        // The live #4 sits ABOVE the toggle — never below a graveyard.
        final row4 = tester.getTopLeft(find.byKey(const Key('device-row-4')));
        final toggle = tester.getTopLeft(
          find.byKey(const Key('devices-revoked-toggle')),
        );
        expect(row4.dy, lessThan(toggle.dy));
      });

      testWidgets('the toggle reveals the tombstones, and hides them again', (
        tester,
      ) async {
        await pumpTombstones(tester);
        await tester.tap(find.byKey(const Key('devices-revoked-toggle')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('device-row-2')), findsOneWidget);
        expect(find.byKey(const Key('device-row-3')), findsOneWidget);
        await tester.tap(find.byKey(const Key('devices-revoked-toggle')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('device-row-2')), findsNothing);
      });

      testWidgets('no tombstones: no toggle at all', (tester) async {
        await pumpEnrolled(tester, holdsDak: true);
        expect(find.byKey(const Key('devices-revoked-toggle')), findsNothing);
      });

      // The tombstone is the user's confirmation that the revoke took; a
      // collapsed section would make the row simply vanish.
      testWidgets('confirming a revoke opens the section', (tester) async {
        await pumpTombstones(tester);
        expect(find.byKey(const Key('device-row-2')), findsNothing);
        await tester.tap(find.byKey(const Key('device-revoke-4')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remove device').last);
        // The revoke is in flight against a fake that never answers, so the
        // busy indicator animates forever: pump a frame, do not settle.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byKey(const Key('device-row-2')), findsOneWidget);
      });
    });
  });
}
