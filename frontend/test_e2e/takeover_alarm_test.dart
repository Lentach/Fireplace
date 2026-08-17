// Phase 0a takeover alarm (multi-device spec §6.0), wire-level.
//
// The server branch under test: `upsertKeyBundle` with a DIFFERENT
// identityPublicKey than stored must (1) alert the account's OTHER live
// sessions via `ownIdentityReplaced` — excluding the uploading socket, which
// caused the event — and (2) alert every conversation peer via
// `peerIdentityChanged`. The same-identity re-upload (the client's normal
// every-connect path) must stay silent on both events.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/e2e_test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  enableRealNetwork();

  group('takeover alarm (Phase 0a)', () {
    final baseUrl = e2eBaseUrl();
    late E2eClient victim;
    late E2eClient peer;
    late E2eClient victimTab;
    E2eClient? replacement;

    setUpAll(() async {
      await requireBackendUp(baseUrl);
      // ignore: invalid_use_of_visible_for_testing_member
      FlutterSecureStorage.setMockInitialValues({});
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});

      victim = E2eClient('vic', baseUrl);
      peer = E2eClient('peer', baseUrl);
      await victim.registerFresh();
      await peer.registerFresh();
      await victim.connectSocket();
      await peer.connectSocket();
      await victim.initializeAndUploadKeys();
      await peer.initializeAndUploadKeys();

      // Friendship + conversation: `peerIdentityChanged` goes to CONVERSATION
      // peers, so the pair must actually share one.
      victim.socketService.sendFriendRequest(peer.userId);
      final request = await peer.events.next(
        'newFriendRequest',
        where: (p) =>
            p is Map &&
            p['sender'] is Map &&
            (p['sender'] as Map)['id'] == victim.userId,
        reason: 'peer receiving the friend request',
      ) as Map;
      victim.events.discard('friendRequestAccepted');
      peer.socketService.acceptFriendRequest(request['id'] as int);
      await victim.events.next(
        'friendRequestAccepted',
        reason: 'victim accept confirmation',
      );

      // A second live session of the victim's account (another tab/device).
      victimTab = E2eClient('victab', baseUrl)..adoptAccountFrom(victim);
      await victimTab.connectSocket();

      // Reinstall/takeover model, same seam as the incident regression test:
      // reset the shared mock stores so a replacement instance on the SAME
      // account mints a genuinely different Signal identity.
      // ignore: invalid_use_of_visible_for_testing_member
      FlutterSecureStorage.setMockInitialValues({});
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      replacement = E2eClient('repl', baseUrl)..adoptAccountFrom(victim);
      await replacement!.connectSocket();
    });

    tearDownAll(() {
      victim.dispose();
      peer.dispose();
      victimTab.dispose();
      replacement?.dispose();
    });

    test(
      'identity replacement alerts other sessions and conversation peers; '
      'same-identity re-upload stays silent',
      () async {
        final replacementKeys = await replacement!.initializeKeys();

        victim.events.discard('ownIdentityReplaced');
        victimTab.events.discard('ownIdentityReplaced');
        peer.events.discard('peerIdentityChanged');

        await replacement!.uploadKeyBundle(replacementKeys);

        // Both of the account's OTHER live sessions are alerted.
        final tabAlarm = await victimTab.events.next(
          'ownIdentityReplaced',
          reason: 'second session must learn its identity was replaced',
        ) as Map;
        expect(tabAlarm['occurredAt'], isA<String>());
        await victim.events.next(
          'ownIdentityReplaced',
          reason: 'original session must learn its identity was replaced',
        );
        // The uploading socket caused the event — it must NOT be alarmed.
        await replacement!.events.none(
          'ownIdentityReplaced',
          within: const Duration(seconds: 3),
          reason: 'the replacing session must not alarm itself',
        );

        // The conversation peer gets the corroborating event.
        final peerAlarm = await peer.events.next(
          'peerIdentityChanged',
          where: (p) => p is Map && p['userId'] == victim.userId,
          reason: 'conversation peer must see the identity change',
        ) as Map;
        expect(peerAlarm['occurredAt'], isA<String>());

        // Same-identity re-upload — the client's normal every-connect path —
        // must raise NO alarm anywhere.
        victim.events.discard('ownIdentityReplaced');
        victimTab.events.discard('ownIdentityReplaced');
        peer.events.discard('peerIdentityChanged');
        await replacement!.uploadKeyBundle(replacementKeys);
        await victimTab.events.none(
          'ownIdentityReplaced',
          within: const Duration(seconds: 3),
          reason: 'same-identity re-upload must stay silent (sessions)',
        );
        await peer.events.none(
          'peerIdentityChanged',
          within: const Duration(seconds: 3),
          reason: 'same-identity re-upload must stay silent (peers)',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
