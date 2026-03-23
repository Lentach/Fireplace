import 'dart:convert';
import 'dart:typed_data';

import 'package:webcrypto/webcrypto.dart';

class EncryptedMedia {
  final Uint8List ciphertext;
  final String keyBase64;
  final String ivBase64;

  const EncryptedMedia({
    required this.ciphertext,
    required this.keyBase64,
    required this.ivBase64,
  });
}

class MediaCryptoService {
  static const int maxBytes = 20 * 1024 * 1024;

  Future<EncryptedMedia> encrypt(Uint8List bytes) async {
    if (bytes.length > maxBytes) {
      throw ArgumentError('File exceeds 20MB limit');
    }
    final keyBytes = Uint8List(32);
    fillRandomBytes(keyBytes);
    final iv = Uint8List(12);
    fillRandomBytes(iv);

    final key = await AesGcmSecretKey.importRawKey(keyBytes);
    final ciphertext = await key.encryptBytes(bytes, iv);

    return EncryptedMedia(
      ciphertext: Uint8List.fromList(ciphertext),
      keyBase64: base64.encode(keyBytes),
      ivBase64: base64.encode(iv),
    );
  }

  Future<Uint8List> decrypt(
    Uint8List ciphertext,
    String keyB64,
    String ivB64,
  ) async {
    final keyBytes = Uint8List.fromList(base64.decode(keyB64));
    final iv = Uint8List.fromList(base64.decode(ivB64));
    final key = await AesGcmSecretKey.importRawKey(keyBytes);
    final plaintext = await key.decryptBytes(ciphertext, iv);
    return Uint8List.fromList(plaintext);
  }
}
