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

      // Re-initialize (simulating re-login)
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      final fresh = EncryptionService();
      await fresh.initialize(42);
      final result = await fresh.getDecryptedContent(1004);
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

    test('clearDecryptedContentCache removes plaintext cache without deleting keys', () async {
      await service.saveDecryptedContent(1005, {'content': 'Local plaintext'});

      final removed = await service.clearDecryptedContentCache();

      expect(removed, 1);
      expect(await service.getDecryptedContent(1005), isNull);
      expect(service.isInitialized, isTrue);
      expect(await service.getIdentityFingerprint(), isNotNull);
    });
  });
}
