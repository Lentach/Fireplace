// Focused incident probes for identity-epoch races and decrypted-cache replay.
//
// The legacy/new-client test asserts fail-closed rejection of untagged OTPs.
// The cache replay test documents the irreversible boundary while proving the
// live Signal session remains usable for new messages.

import 'dart:convert';
import 'dart:io';

import 'package:fireplace/services/encryption_service.dart';
import 'package:fireplace/widgets/audio/playback_controller.dart';
import 'package:fireplace/utils/e2e_envelope.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/e2e_test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  enableRealNetwork();

  group('identity epoch wire invariant', () {
    final baseUrl = e2eBaseUrl();
    late E2eClient observer;
    late E2eClient legacy;
    E2eClient? replacement;

    setUpAll(() async {
      await requireBackendUp(baseUrl);
      // ignore: invalid_use_of_visible_for_testing_member
      FlutterSecureStorage.setMockInitialValues({});
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});

      observer = E2eClient('obs', baseUrl);
      legacy = E2eClient('legacy', baseUrl);
      await observer.registerFresh();
      await legacy.registerFresh();
      await observer.connectSocket();
      await legacy.connectSocket();

      final observerKeys = await observer.initializeKeys();
      await observer.uploadKeyBundle(observerKeys);
      await observer.uploadOneTimePreKeys(observerKeys, tagIdentityEpoch: true);

      final legacyKeys = await legacy.initializeKeys();
      await legacy.uploadKeyBundle(legacyKeys);
      await legacy.uploadOneTimePreKeys(legacyKeys, tagIdentityEpoch: true);

      // Simulate reinstall/site-state loss without destroying the still-running
      // legacy instance's in-memory key objects. The replacement instance logs
      // into the same server account but generates a different Signal identity.
      // ignore: invalid_use_of_visible_for_testing_member
      FlutterSecureStorage.setMockInitialValues({});
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      replacement = E2eClient('repl', baseUrl)..adoptAccountFrom(legacy);
      await replacement!.connectSocket();
    });

    tearDownAll(() {
      observer.dispose();
      legacy.dispose();
      replacement?.dispose();
    });

    test(
      'legacy OTP upload cannot be relabelled with a competing current identity',
      () async {
        final oldKeys = legacy.encryption.getKeysForUpload()!;
        final oldIdentity =
            (oldKeys['keyBundle'] as Map)['identityPublicKey'] as String;

        final replacementKeys = await replacement!.initializeKeys();
        final replacementIdentity =
            (replacementKeys['keyBundle'] as Map)['identityPublicKey']
                as String;
        expect(
          replacementIdentity,
          isNot(oldIdentity),
          reason: 'replacement must represent a new Signal identity epoch',
        );

        // Adversarial ordering: replacement bundle B wins, then a still-running
        // pre-epoch client uploads OTP-A without an epoch tag. The server must
        // fail closed; reading current bundle B and stamping it onto OTP-A would
        // manufacture the exact {identity B, stale OTP-A} bad-MAC bundle.
        await replacement!.uploadKeyBundle(replacementKeys);

        await legacy.uploadOneTimePreKeys(
          oldKeys,
          tagIdentityEpoch: false,
          expectRejection: true,
        );
        final fetched = await observer.fetchBundleFor(legacy.userId);
        expect(fetched['identityPublicKey'], replacementIdentity);
        expect(
          fetched['oneTimePreKeyId'],
          isNull,
          reason:
              'an untagged legacy OTP uploaded after another identity won '
              'must be quarantined, not relabelled as the current epoch',
        );

        // Signed-prekey-only X3DH is the safe fallback and must still establish
        // future traffic with the replacement client.
        await observer.encryption.buildSession(legacy.userId, fetched);
        final ciphertext = await observer.encryptText(
          legacy.userId,
          'epoch-safe-${DateTime.now().microsecondsSinceEpoch}',
        );
        expect(ciphertext, startsWith('3:'));
        expect(
          await replacement!.decryptText(observer.userId, ciphertext),
          startsWith('epoch-safe-'),
        );
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );
  });

  group('decrypted cache replay boundary', () {
    setUp(() {
      // ignore: invalid_use_of_visible_for_testing_member
      FlutterSecureStorage.setMockInitialValues({});
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'cache clear makes consumed history unreplayable but keeps new traffic alive',
      () async {
        final alice = EncryptionService();
        final bob = EncryptionService();
        await alice.initialize(91001, checkServerBundleExists: () async => false);
        await bob.initialize(91002, checkServerBundleExists: () async => false);

        final bobKeys = bob.getKeysForUpload()!;
        final bobBundle = (bobKeys['keyBundle'] as Map).cast<String, dynamic>();
        final bobOtp = ((bobKeys['oneTimePreKeys'] as List).first as Map)
            .cast<String, dynamic>();
        await alice.buildSession(91002, {
          ...bobBundle,
          'oneTimePreKeyId': bobOtp['keyId'],
          'oneTimePreKeyPublic': bobOtp['publicKey'],
        });
        const historicalPlaintext = 'history-before-cache-clear';
        final historicalCiphertext = await alice.encrypt(
          91002,
          jsonEncode(E2eEnvelope.build(historicalPlaintext)),
        );
        final decryptedEnvelope = await bob.decrypt(
          91001,
          historicalCiphertext,
        );
        expect(
          E2eEnvelope.parse(decryptedEnvelope).content,
          historicalPlaintext,
        );
        await bob.saveDecryptedContent(70001, {'content': historicalPlaintext});
        expect(await bob.getDecryptedContent(70001), isNotNull);

        final wipe = await bob.clearDecryptedContentCache();
        expect(wipe.removed, 1);
        expect(
          wipe.isComplete,
          isTrue,
          reason: 'a wipe that could not commit must not report success',
        );
        expect(await bob.getDecryptedContent(70001), isNull);

        Object? replayError;
        try {
          await bob.decrypt(91001, historicalCiphertext);
        } catch (error) {
          replayError = error;
        }
        expect(
          replayError,
          isNotNull,
          reason: 'the consumed Signal message key cannot be reconstructed',
        );
        expect(
          replayError.toString(),
          anyOf(contains('old counter'), contains('DuplicateMessageException')),
          reason: 'capture the exact libsignal replay signature',
        );

        final freshCiphertext = await alice.encrypt(
          91002,
          jsonEncode(E2eEnvelope.build('new-after-cache-clear')),
        );
        final freshEnvelope = await bob.decrypt(91001, freshCiphertext);
        expect(
          E2eEnvelope.parse(freshEnvelope).content,
          'new-after-cache-clear',
          reason: 'plaintext-cache deletion must not delete the live session',
        );
      },
    );
    test(
      'audio-only cache action preserves durable E2E content after reload',
      () async {
        final alice = EncryptionService();
        final bob = EncryptionService();
        await alice.initialize(92001, checkServerBundleExists: () async => false);
        await bob.initialize(92002, checkServerBundleExists: () async => false);
        final keys = bob.getKeysForUpload()!;
        final bundle = (keys['keyBundle'] as Map).cast<String, dynamic>();
        final otp = ((keys['oneTimePreKeys'] as List).first as Map)
            .cast<String, dynamic>();
        await alice.buildSession(92002, {
          ...bundle,
          'oneTimePreKeyId': otp['keyId'],
          'oneTimePreKeyPublic': otp['publicKey'],
        });
        final ciphertext = await alice.encrypt(
          92002,
          jsonEncode(E2eEnvelope.build('durable text')),
        );
        await bob.decrypt(92001, ciphertext);
        await bob.saveDecryptedContent(80001, {
          'content': 'durable text',
          'editedAt': '2026-07-12T00:00:00Z',
          'mediaKey': 'media-key',
          'mediaIv': 'media-iv',
        });
        await bob.savePendingSendRecord('durable-ciphertext', {
          'content': 'pending plaintext',
          'mediaKey': 'pending-key',
          'mediaIv': 'pending-iv',
        });

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              (call) async => Directory.systemTemp.path,
            );
        await PlaybackController.clearAudioCache();

        final reloaded = EncryptionService();
        await reloaded.initialize(92002, checkServerBundleExists: () async => false);
        final saved = await reloaded.getDecryptedContent(80001);
        expect(saved?['content'], 'durable text');
        expect(saved?['editedAt'], '2026-07-12T00:00:00Z');
        expect(saved?['mediaKey'], 'media-key');
        expect(saved?['mediaIv'], 'media-iv');
        expect(
          await reloaded.peekPendingSendRecord('durable-ciphertext'),
          isNotNull,
        );

        final nextCiphertext = await alice.encrypt(
          92002,
          jsonEncode(E2eEnvelope.build('fresh after audio clear')),
        );
        final next = await reloaded.decrypt(92001, nextCiphertext);
        expect(E2eEnvelope.parse(next).content, 'fresh after audio clear');
      },
    );
  });
}
