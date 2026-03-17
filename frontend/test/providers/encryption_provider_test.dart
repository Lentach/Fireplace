import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fireplace/providers/encryption_provider.dart';

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
      expect(result['linkPreviewUrl'], 'https://example.com');
      expect(result['linkPreviewTitle'], 'Example');
    });
  });
}
