import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/services/encryption_service.dart';

/// Provider-level contract of the 0.1.10 identity guard: when the server
/// cannot be asked whether this account already has a key bundle, E2E stays
/// DOWN for the session — no keys minted, no "damaged identity" surface, and
/// the next initializeE2E retries because the ready flag never flipped.
/// Treating UNKNOWN as "no bundle" would re-mint an identity on every flaky
/// boot, which is the exact silent-history-loss bug this release fixes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('no socket -> UNKNOWN -> E2E down, not damaged, retry succeeds',
      () async {
    final provider = EncryptionProvider(service: EncryptionService());

    // No emit callback wired: the bundle check cannot even be sent.
    await provider.initializeE2E(7);

    expect(provider.isE2EReady, isFalse);
    expect(
      provider.identityIncomplete,
      isFalse,
      reason: 'UNKNOWN must not offer the destructive recovery dialog',
    );

    // Next connect: the server now answers "no bundle" synchronously.
    provider.setEmitCallback((event, data) {
      if (event == 'checkOwnKeyBundle') {
        provider.onOwnKeyBundleStatus({'exists': false});
      }
    });
    await provider.initializeE2E(7);

    expect(provider.isE2EReady, isTrue);
    expect(provider.identityIncomplete, isFalse);
  });

  test('server "bundle exists" -> damaged surface, no silent re-mint',
      () async {
    final provider = EncryptionProvider(service: EncryptionService());
    provider.setEmitCallback((event, data) {
      if (event == 'checkOwnKeyBundle') {
        provider.onOwnKeyBundleStatus({'exists': true});
      }
    });

    await provider.initializeE2E(8);

    expect(provider.isE2EReady, isFalse);
    expect(provider.identityIncomplete, isTrue);
  });

  test('a malformed status payload is UNKNOWN, never "no bundle"', () async {
    final provider = EncryptionProvider(service: EncryptionService());
    provider.setEmitCallback((event, data) {
      if (event == 'checkOwnKeyBundle') {
        provider.onOwnKeyBundleStatus({'exists': 'yes'});
      }
    });

    await provider.initializeE2E(9);

    expect(provider.isE2EReady, isFalse);
    expect(provider.identityIncomplete, isFalse);
  });

  test('concurrent initializeE2E calls share one run (no double init)',
      () async {
    final provider = EncryptionProvider(service: EncryptionService());
    var uploads = 0;
    provider.setEmitCallback((event, data) {
      if (event == 'checkOwnKeyBundle') {
        // Answer asynchronously so both calls overlap inside the check
        // window — the exact reconnect race from the review finding.
        Future<void>.delayed(const Duration(milliseconds: 20), () {
          provider.onOwnKeyBundleStatus({'exists': false});
        });
      }
      if (event == 'uploadKeyBundle') uploads++;
    });

    await Future.wait([provider.initializeE2E(5), provider.initializeE2E(5)]);

    expect(provider.isE2EReady, isTrue);
    expect(
      uploads,
      1,
      reason: 'a reconnect during init must not re-run key generation '
          'or double-upload the bundle',
    );
  });
}
