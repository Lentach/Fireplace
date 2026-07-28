// Proves a peer can start a Signal session against an identity that was
// regenerated through the CONSENTED recovery path.
//
// Context: `regenerateIdentityAfterConfirmedLoss` mints a new identity and
// re-publishes the bundle with `_emit?.call(...)` — fire-and-forget, no retry,
// no error surfaced. "The banner went away" therefore proves nothing about
// whether peers can reach the account again. If the upload silently failed, or
// the published signed-prekey signature did not match the new identity key, the
// user would look recovered and be permanently unreachable.
//
// processPreKeyBundle is the exact check: libsignal verifies the signed pre-key
// signature against the identity key, so a mismatched or stale bundle fails
// here rather than silently producing an unusable session.
//
//   docker-compose up
//   cd frontend && flutter test test_e2e/recovered_identity_probe_test.dart \
//     --dart-define=RECOVERED_USER_ID=<id>
//
// Skipped unless RECOVERED_USER_ID is set, so the default e2e run is unaffected.

// Mock-store setup is legitimate here: this file is a test, but `test_e2e/` is
// a sibling of `test/` so the analyzer does not treat it as one.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/e2e_test_client.dart';

const _recoveredUserId = int.fromEnvironment(
  'RECOVERED_USER_ID',
  defaultValue: -1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  enableRealNetwork();

  final baseUrl = e2eBaseUrl();

  test(
    'a peer can build a session against the regenerated identity',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});

      final peer = E2eClient('peer', baseUrl);
      await peer.registerFresh();
      await peer.connectSocket();
      await peer.initializeAndUploadKeys();

      // Fetch the PUBLISHED bundle and run X3DH against it. buildSession
      // throws if the signed pre-key signature does not verify against the
      // identity key — i.e. if recovery published a stale or inconsistent
      // bundle, or never published at all.
      final bundle = await peer.fetchBundleFor(_recoveredUserId);
      expect(
        bundle['identityKey'] ?? bundle['identityPublicKey'],
        isNotNull,
        reason: 'the recovered account must have a bundle on the server',
      );
      await peer.encryption.buildSession(_recoveredUserId, bundle);

      final ciphertext = await peer.encryptText(
        _recoveredUserId,
        'session against a recovered identity',
      );

      expect(
        ciphertext,
        matches(RegExp(r'^3:[A-Za-z0-9+/]+=*$')),
        reason:
            'a first message to a re-keyed peer must be a PreKey (3:) wire, '
            'which means X3DH completed against the republished bundle',
      );

      peer.dispose();
    },
    skip: _recoveredUserId < 0 ? 'set --dart-define=RECOVERED_USER_ID' : false,
  );
}
