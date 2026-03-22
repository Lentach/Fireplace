import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

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
    return compute(_encryptIsolate, bytes);
  }

  Future<Uint8List> decrypt(
    Uint8List ciphertext,
    String keyB64,
    String ivB64,
  ) {
    return compute(_decryptIsolate, _DecryptArgs(ciphertext, keyB64, ivB64));
  }
}

EncryptedMedia _encryptIsolate(Uint8List plaintext) {
  final key = _randomBytes(32);
  final iv = _randomBytes(12);
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      true,
      AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)),
    );
  final ciphertext = cipher.process(plaintext);
  return EncryptedMedia(
    ciphertext: ciphertext,
    keyBase64: base64.encode(key),
    ivBase64: base64.encode(iv),
  );
}

Uint8List _decryptIsolate(_DecryptArgs args) {
  final key = Uint8List.fromList(base64.decode(args.keyB64));
  final iv = Uint8List.fromList(base64.decode(args.ivB64));
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      false,
      AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)),
    );
  return cipher.process(args.ciphertext);
}

Uint8List _randomBytes(int length) {
  final rng = Random.secure();
  return Uint8List.fromList(
    List.generate(length, (_) => rng.nextInt(256)),
  );
}

class _DecryptArgs {
  final Uint8List ciphertext;
  final String keyB64;
  final String ivB64;

  const _DecryptArgs(this.ciphertext, this.keyB64, this.ivB64);
}
