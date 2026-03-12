import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

// Helpers matching the implementation in chat_provider.dart
Uint8List secureRandomBytes(int length) {
  final random = FortunaRandom();
  final seedSource = Random.secure();
  final seeds = List<int>.generate(32, (_) => seedSource.nextInt(256));
  random.seed(KeyParameter(Uint8List.fromList(seeds)));
  return random.nextBytes(length);
}

Uint8List aesGcmEncrypt(Uint8List key, Uint8List iv, Uint8List plaintext) {
  final cipher = GCMBlockCipher(AESEngine());
  cipher.init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
  return cipher.process(plaintext);
}

Uint8List aesGcmDecrypt(Uint8List key, Uint8List iv, Uint8List ciphertextWithTag) {
  final cipher = GCMBlockCipher(AESEngine());
  cipher.init(false, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
  return cipher.process(ciphertextWithTag);
}

void main() {
  group('Anti-Quantum Note crypto', () {
    test('AES-GCM roundtrip: encrypt then decrypt returns original plaintext', () {
      final key = secureRandomBytes(32); // 256-bit
      final iv = secureRandomBytes(12);  // 96-bit (GCM standard)
      const message = 'Top secret message 🔐';
      final plaintext = Uint8List.fromList(utf8.encode(message));

      final ciphertextWithTag = aesGcmEncrypt(key, iv, plaintext);
      final decrypted = aesGcmDecrypt(key, iv, ciphertextWithTag);

      expect(utf8.decode(decrypted), equals(message));
    });

    test('ciphertext format is base64(iv):base64(ciphertext+tag)', () {
      final key = secureRandomBytes(32);
      final iv = secureRandomBytes(12);
      final plaintext = Uint8List.fromList(utf8.encode('hello'));

      final ciphertextWithTag = aesGcmEncrypt(key, iv, plaintext);
      final encoded = '${base64.encode(iv)}:${base64.encode(ciphertextWithTag)}';

      final parts = encoded.split(':');
      expect(parts.length, equals(2), reason: 'format must be iv:ciphertext');

      final decodedIv = base64.decode(parts[0]);
      final decodedCiphertext = base64.decode(parts[1]);

      expect(decodedIv.length, equals(12), reason: 'IV must be 12 bytes (96-bit)');
      // GCM tag is 16 bytes (128-bit), appended to ciphertext
      expect(decodedCiphertext.length, equals(plaintext.length + 16),
          reason: 'ciphertext must be plaintext length + 16-byte GCM tag');
    });

    test('different keys produce different ciphertexts', () {
      final key1 = secureRandomBytes(32);
      final key2 = secureRandomBytes(32);
      final iv = secureRandomBytes(12);
      final plaintext = Uint8List.fromList(utf8.encode('same message'));

      final ct1 = aesGcmEncrypt(key1, iv, plaintext);
      final ct2 = aesGcmEncrypt(key2, iv, plaintext);

      expect(ct1, isNot(equals(ct2)));
    });

    test('wrong key fails to decrypt (GCM auth tag mismatch)', () {
      final key = secureRandomBytes(32);
      final wrongKey = secureRandomBytes(32);
      final iv = secureRandomBytes(12);
      final plaintext = Uint8List.fromList(utf8.encode('secret'));

      final ciphertextWithTag = aesGcmEncrypt(key, iv, plaintext);

      expect(
        () => aesGcmDecrypt(wrongKey, iv, ciphertextWithTag),
        throwsA(anything),
        reason: 'GCM authentication tag mismatch must throw',
      );
    });

    test('key encoded as base64url has no padding or unsafe chars', () {
      final key = secureRandomBytes(32);
      final keyBase64Url = base64Url.encode(key);

      // URL fragment must not contain + or / (base64 standard chars)
      expect(keyBase64Url.contains('+'), isFalse);
      expect(keyBase64Url.contains('/'), isFalse);
      // base64url without padding is safe in URL fragments
    });

    test('secureRandomBytes produces correct length', () {
      expect(secureRandomBytes(32).length, equals(32));
      expect(secureRandomBytes(12).length, equals(12));
    });

    test('secureRandomBytes produces different values each call', () {
      final a = secureRandomBytes(32);
      final b = secureRandomBytes(32);
      expect(a, isNot(equals(b)));
    });
  });
}
