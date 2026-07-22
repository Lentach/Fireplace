import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/utils/e2e_persistent_diag.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EncryptionProvider — decrypted content delegation', () {
    late EncryptionProvider provider;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      provider = EncryptionProvider();
      // initializeE2E loads keys from storage; emit callback is nullable so
      // socket events are silently ignored in tests.
      await provider.initializeE2E(42);
    });

    test('saveDecryptedContent + getDecryptedContent round-trip', () async {
      await provider.saveDecryptedContent(1001, {'content': 'Hello world'});
      final result = await provider.getDecryptedContent(1001);
      expect(result, isNotNull);
      expect(result!['content'], 'Hello world');
    });

    test('getDecryptedContent returns null for unknown id', () async {
      final result = await provider.getDecryptedContent(9999);
      expect(result, isNull);
    });

    test('saveDecryptedContent before initializeE2E does not throw', () async {
      // Provider without initializeE2E — _userId is null.
      // Documented contract: silent no-op, never throws.
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      final uninitializedProvider = EncryptionProvider();
      await expectLater(
        uninitializedProvider.saveDecryptedContent(1, {'content': 'test'}),
        completes,
      );
      final result = await uninitializedProvider.getDecryptedContent(1);
      expect(result, isNull);
    });

    test('saveDecryptedContent persists all envelope fields', () async {
      await provider.saveDecryptedContent(1002, {
        'content': 'Check this',
        'messageType': 'TEXT',
        'linkPreviewUrl': 'https://example.com',
        'linkPreviewTitle': 'Example',
      });
      final result = await provider.getDecryptedContent(1002);
      expect(result!['content'], 'Check this');
      expect(result['messageType'], 'TEXT');
      expect(result['linkPreviewUrl'], 'https://example.com');
      expect(result['linkPreviewTitle'], 'Example');
    });

    test(
      'clearLocalDecryptedContentCache removes persisted plaintext cache only',
      () async {
        await provider.saveDecryptedContent(1003, {
          'content': 'Cached message',
        });

        final removed = await provider.clearLocalDecryptedContentCache();

        expect(removed, 1);
        expect(await provider.getDecryptedContent(1003), isNull);
        expect(provider.isE2EReady, isTrue);
        expect(await provider.getIdentityFingerprint(), isNotNull);
      },
    );
  });

  group('EncryptionProvider — race and idempotency guards', () {
    late EncryptionProvider provider;
    late List<Map<String, dynamic>> emitted;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      emitted = <Map<String, dynamic>>[];
      provider = EncryptionProvider();
      provider.setEmitCallback((event, data) {
        emitted.add({'event': event, 'data': data});
      });
      await provider.initializeE2E(7);
    });

    test(
      'duplicate preKeyBundleResponse is ignored after first completion',
      () async {
        final future = provider.ensureSession(99);
        await Future<void>.delayed(Duration.zero);
        provider.onPreKeyBundleResponse({'userId': 99, 'bundle': null});
        provider.onPreKeyBundleResponse({'userId': 99, 'bundle': null});
        await expectLater(future, throwsStateError);
        expect(provider.pendingPreKeyFetches.containsKey(99), isFalse);
        final fetchEvents = emitted.where(
          (e) => e['event'] == 'fetchPreKeyBundle',
        );
        expect(fetchEvents.length, 1);
      },
    );

    test('preKeysLow handler is reentrant-safe', () async {
      final initialUploads = emitted
          .where((e) => e['event'] == 'uploadOneTimePreKeys')
          .length;
      provider.onPreKeysLow({'remaining': 1});
      provider.onPreKeysLow({'remaining': 1});
      await Future<void>.delayed(Duration.zero);
      final uploads = emitted.where(
        (e) => e['event'] == 'uploadOneTimePreKeys',
      );
      expect(uploads.length - initialUploads, 1);
    });
    test(
      'null identity defers without upload and later initialized identity uploads tagged OTPs',
      () async {
        FlutterSecureStorage.setMockInitialValues({});
        SharedPreferences.setMockInitialValues({});
        final deferredEmits = <Map<String, dynamic>>[];
        final deferred = EncryptionProvider()
          ..setEmitCallback((event, data) {
            deferredEmits.add({'event': event, 'data': data});
          });
        deferred.onPreKeysLow({'remaining': 0});
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          deferredEmits.where((e) => e['event'] == 'uploadOneTimePreKeys'),
          isEmpty,
        );
        expect(
          E2ePersistentDiag.entries.any(
            (e) => e.contains('OTP_REPLENISH_DEFERRED'),
          ),
          isTrue,
        );

        final taggedEmits = <Map<String, dynamic>>[];
        final ready = EncryptionProvider()
          ..setEmitCallback((event, data) {
            taggedEmits.add({'event': event, 'data': data});
          });
        await ready.initializeE2E(8);
        ready.onPreKeysLow({'remaining': 0});
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final uploads = taggedEmits
            .where((e) => e['event'] == 'uploadOneTimePreKeys')
            .map((e) => e['data'] as Map<String, dynamic>);
      expect(uploads, isNotEmpty);
      expect(uploads.last['identityPublicKey'], isA<String>());
      expect((uploads.last['identityPublicKey'] as String), isNotEmpty);
      },
    );
  });
}
