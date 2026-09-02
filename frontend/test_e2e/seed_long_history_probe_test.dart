// Seeds a real, Signal-encrypted conversation of N messages INTO a browser
// account, so the chat-entry flicker/jank can be observed in a real PWA rather
// than inferred from a synthetic probe.
//
// Why it is shaped like this: the receiving device must be the BROWSER, because
// the plaintext cache and Signal session live in that origin's localStorage. So
// this harness never touches the target's Signal keys — it logs into the target
// account only to accept the friend request over WS, and does all key work as
// the SENDER.
//
//   docker-compose up
//   cd frontend && flutter test test_e2e/seed_long_history_probe_test.dart \
//     --dart-define=TARGET_LOGIN=webprobe01#1234 \
//     --dart-define=TARGET_PASSWORD=ProbePass123 \
//     --dart-define=TARGET_USER_ID=7 \
//     --dart-define=SEED_COUNT=300
//
// Skipped unless TARGET_USER_ID is set, so the default e2e run is unaffected.

// Mock-store setup is legitimate here: this file is a test, but `test_e2e/` is
// a sibling of `test/` so the analyzer does not treat it as one.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/e2e_test_client.dart';

const _targetLogin = String.fromEnvironment('TARGET_LOGIN');
const _targetPassword = String.fromEnvironment('TARGET_PASSWORD');
const _targetUserId = int.fromEnvironment('TARGET_USER_ID', defaultValue: -1);
const _seedCount = int.fromEnvironment('SEED_COUNT', defaultValue: 300);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  enableRealNetwork();

  final baseUrl = e2eBaseUrl();

  test(
    'seeds a long encrypted history into the browser account',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});

      final sender = E2eClient('seeder', baseUrl);
      await sender.registerFresh();
      await sender.connectSocket();
      await sender.initializeAndUploadKeys();

      // Log in AS the target purely to accept the friend request. Deliberately
      // no initializeAndUploadKeys here: uploading would overwrite the bundle
      // the browser published and orphan its private keys.
      final target = E2eClient('target', baseUrl);
      final login = await target.api.login(_targetLogin, _targetPassword);
      target.userId = _targetUserId;
      target.username = _targetLogin;
      target.tag = '';
      target.accessToken = login['access_token'] as String;
      await target.connectSocket();

      sender.socketService.sendFriendRequest(_targetUserId);
      final request =
          await target.events.next(
                'newFriendRequest',
                reason: 'request reached target',
              )
              as Map;
      target.socketService.acceptFriendRequest((request['id'] as num).toInt());
      await sender.events.next(
        'friendRequestAccepted',
        reason: 'friendship established',
      );

      // Session against the bundle the BROWSER published.
      final bundle = await sender.fetchBundleFor(_targetUserId);
      await sender.encryption.buildSession(_targetUserId, bundle, expectedIdentityBase64: null);

      for (var i = 1; i <= _seedCount; i++) {
        final ciphertext = await sender.encryptText(
          _targetUserId,
          'seeded history line $i — long enough to look like a real chat message',
        );
        sender.socketService.sendMessage(
          _targetUserId,
          '[encrypted]',
          tempId: 'seed-$i',
          encryptedContent: ciphertext,
        );
        if (i % 25 == 0) {
          // Let the server and the receiving browser keep up.
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }
      }
      await Future<void>.delayed(const Duration(seconds: 3));

      // ignore: avoid_print
      print('SEEDED $_seedCount messages from ${sender.username} '
          '(id=${sender.userId}) to user $_targetUserId');

      sender.dispose();
      target.dispose();
    },
    timeout: const Timeout(Duration(minutes: 10)),
    skip: _targetUserId < 0 ? 'set --dart-define=TARGET_USER_ID' : false,
  );
}
