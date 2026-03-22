import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/services/media_crypto_service.dart';

void main() {
  final service = MediaCryptoService();

  group('MediaCryptoService', () {
    test('encrypt produces ciphertext different from input', () async {
      final input = Uint8List.fromList(List.generate(100, (i) => i));
      final result = await service.encrypt(input);
      expect(result.ciphertext, isNot(equals(input)));
      expect(result.keyBase64.isNotEmpty, isTrue);
      expect(result.ivBase64.isNotEmpty, isTrue);
    });

    test('decrypt restores original bytes', () async {
      final input = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final encrypted = await service.encrypt(input);
      final decrypted = await service.decrypt(
        encrypted.ciphertext,
        encrypted.keyBase64,
        encrypted.ivBase64,
      );
      expect(decrypted, equals(input));
    });

    test('each encrypt call produces unique key and IV', () async {
      final input = Uint8List.fromList([42, 43, 44]);
      final a = await service.encrypt(input);
      final b = await service.encrypt(input);
      expect(a.keyBase64, isNot(equals(b.keyBase64)));
      expect(a.ivBase64, isNot(equals(b.ivBase64)));
    });

    test('decrypt with wrong key throws', () async {
      final input = Uint8List.fromList([1, 2, 3]);
      final encrypted = await service.encrypt(input);
      final other = await service.encrypt(input);
      await expectLater(
        service.decrypt(
          encrypted.ciphertext,
          other.keyBase64,
          encrypted.ivBase64,
        ),
        throwsA(anything),
      );
    });

    test('throws ArgumentError for input over 20MB', () async {
      final huge = Uint8List(21 * 1024 * 1024);
      await expectLater(service.encrypt(huge), throwsA(isA<ArgumentError>()));
    });
  });
}
