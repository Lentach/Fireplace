import 'dart:convert';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fireplace/services/encryption_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EncryptionService decrypted content cache', () {
    late EncryptionService service;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      service = EncryptionService();
      await service.initialize(42);
    });

    test('saveDecryptedContent then getDecryptedContent returns stored data', () async {
      await service.saveDecryptedContent(1001, {'content': 'Hello world'});
      final result = await service.getDecryptedContent(1001);
      expect(result, isNotNull);
      expect(result!['content'], 'Hello world');
    });

    test('getDecryptedContent returns null for unknown id', () async {
      final result = await service.getDecryptedContent(9999);
      expect(result, isNull);
    });

    test('saveDecryptedContent persists link preview fields', () async {
      await service.saveDecryptedContent(1002, {
        'content': 'Check this',
        'linkPreviewUrl': 'https://example.com',
        'linkPreviewTitle': 'Example',
      });
      final result = await service.getDecryptedContent(1002);
      expect(result!['linkPreviewUrl'], 'https://example.com');
      expect(result['linkPreviewTitle'], 'Example');
    });

    test('content is isolated per user (different userId cannot read it)', () async {
      await service.saveDecryptedContent(1003, {'content': 'Secret'});

      // Different user
      final other = EncryptionService();
      await other.initialize(99);
      final result = await other.getDecryptedContent(1003);
      expect(result, isNull);
    });

    test('clearAllKeys removes decrypted content cache entries', () async {
      await service.saveDecryptedContent(1004, {'content': 'To be cleared'});
      await service.clearAllKeys();

      // Re-initialize the SAME service against the real post-clear store
      // (like the pending-send Contract 7a) so a stale read here would fail
      // if clearAllKeys left the content behind.
      await service.initialize(42);
      final result = await service.getDecryptedContent(1004);
      expect(result, isNull);
    });

    test('saveDecryptedContent prunes oldest entries above the cache limit', () async {
      final limited = EncryptionService(decryptedContentCacheLimit: 2);
      await limited.initialize(42);

      await limited.saveDecryptedContent(1001, {'content': 'oldest'});
      await limited.saveDecryptedContent(1002, {'content': 'middle'});
      await limited.saveDecryptedContent(1003, {'content': 'newest'});

      expect(await limited.getDecryptedContent(1001), isNull);
      expect((await limited.getDecryptedContent(1002))!['content'], 'middle');
      expect((await limited.getDecryptedContent(1003))!['content'], 'newest');
    });

    test('saveDecryptedContent prunes legacy secure-storage decrypted entries', () async {
      final secureStorage = const FlutterSecureStorage();
      await secureStorage.write(
        key: 'e2e_42_decrypted_1001',
        value: '{"content":"legacy oldest"}',
      );
      await secureStorage.write(
        key: 'e2e_42_decrypted_1002',
        value: '{"content":"legacy middle"}',
      );

      final limited = EncryptionService(decryptedContentCacheLimit: 2);
      await limited.initialize(42);
      await limited.saveDecryptedContent(1003, {'content': 'newest'});

      expect(await limited.getDecryptedContent(1001), isNull);
      expect((await limited.getDecryptedContent(1002))!['content'], 'legacy middle');
      expect((await limited.getDecryptedContent(1003))!['content'], 'newest');
    });

    test('a keyless [Decryption failed] write never destroys stored media keys',
        () async {
      // First decrypt persists the media keys (only chance — ratchet is one-shot).
      await service.saveDecryptedContent(2001, {
        'content': '',
        'messageType': 'VOICE',
        'mediaUrl': 'https://x/media/msgs/a.bin',
        'mediaKey': 'KEYbase64',
        'mediaIv': 'IVbase64',
      });

      // A later transient re-decrypt throws DuplicateMessage and tries to mark
      // the row failed — this must be ignored, the keys must survive.
      await service.saveDecryptedContent(2001, {'content': '[Decryption failed]'});

      final result = await service.getDecryptedContent(2001);
      expect(result, isNotNull);
      expect(result!['mediaKey'], 'KEYbase64');
      expect(result['mediaIv'], 'IVbase64');
      expect(result['messageType'], 'VOICE');
      expect(result['content'], isNot('[Decryption failed]'));
    });

    test('a keyed write still updates an existing keyed entry', () async {
      await service.saveDecryptedContent(2002, {
        'content': '',
        'mediaUrl': 'https://x/old.bin',
        'mediaKey': 'OLD',
        'mediaIv': 'OLDIV',
      });
      await service.saveDecryptedContent(2002, {
        'content': '',
        'mediaUrl': 'https://x/new.bin',
        'mediaKey': 'NEW',
        'mediaIv': 'NEWIV',
      });
      final result = await service.getDecryptedContent(2002);
      expect(result!['mediaKey'], 'NEW');
      expect(result['mediaUrl'], 'https://x/new.bin');
    });

    test('a keyless write still overwrites a keyless (text) entry', () async {
      await service.saveDecryptedContent(2003, {'content': 'hello'});
      await service.saveDecryptedContent(2003, {'content': '[Decryption failed]'});
      final result = await service.getDecryptedContent(2003);
      expect(result!['content'], '[Decryption failed]');
    });

    test('clearDecryptedContentCache removes plaintext cache without deleting keys', () async {
      await service.saveDecryptedContent(1005, {'content': 'Local plaintext'});

      final removed = await service.clearDecryptedContentCache();

      expect(removed, 1);
      expect(await service.getDecryptedContent(1005), isNull);
      expect(service.isInitialized, isTrue);
      expect(await service.getIdentityFingerprint(), isNotNull);
    });

    // Pins the in-app "Clear local message cache" scope (Class-A verdict):
    // it removes ONLY persisted plaintext — Signal sessions and identity stay,
    // so a peer's NEXT message on the existing session still decrypts. A user
    // who "cleared cache" and then lost the session did a browser-level
    // site-data clear or reinstall, not this.
    test('clearDecryptedContentCache does NOT delete Signal sessions or identity', () async {
      const secureStorage = FlutterSecureStorage();
      await secureStorage.write(
        key: 'e2e_42_session_7_1',
        value: 'fake-session-record',
      );
      await service.saveDecryptedContent(1006, {'content': 'plain'});

      await service.clearDecryptedContentCache();

      expect(
        await secureStorage.read(key: 'e2e_42_session_7_1'),
        'fake-session-record',
        reason: 'sessions must survive a plaintext-cache clear',
      );
      expect(
        await secureStorage.read(key: 'e2e_42_identity_key_pair'),
        isNotNull,
        reason: 'identity must survive a plaintext-cache clear',
      );
      expect(await service.getDecryptedContent(1006), isNull);
    });

    test('sessionInventoryPeerIds lists only peers with a persisted session', () async {
      // Pre-seed session rows (+ a non-session key that must be ignored) before
      // init. Under flutter test kIsWeb is false, so DualStorage reads these
      // from the FlutterSecureStorage mock.
      //
      // The identity is seeded too, and must be: sessions on disk with NO
      // identity is the partial-loss signature that initialize() now refuses
      // to regenerate over (see encryption_identity_guard_test.dart). That
      // state cannot occur in production, so a fixture must not fake it.
      final identity = generateIdentityKeyPair();
      FlutterSecureStorage.setMockInitialValues({
        'e2e_77_identity_record_v1': jsonEncode(<String, dynamic>{
          'pair': base64Encode(identity.serialize()),
          'registrationId': 4242,
        }),
        'e2e_77_session_49_1': 'fake-record',
        'e2e_77_session_580_1': 'fake-record',
        'e2e_77_signed_pre_key_0': 'not-a-session',
      });
      SharedPreferences.setMockInitialValues({});
      final svc = EncryptionService();
      await svc.initialize(77);

      final peers = await svc.sessionInventoryPeerIds();
      expect(peers.toSet(), {'49', '580'},
          reason: 'multi-digit peer ids must parse; non-session keys excluded');
    });

    test('clearAllKeys (account deletion) deletes sessions AND identity', () async {
      const secureStorage = FlutterSecureStorage();
      await secureStorage.write(
        key: 'e2e_42_session_7_1',
        value: 'fake-session-record',
      );

      await service.clearAllKeys();

      expect(await secureStorage.read(key: 'e2e_42_session_7_1'), isNull);
      expect(
        await secureStorage.read(key: 'e2e_42_identity_key_pair'),
        isNull,
      );
    });
  });
}
