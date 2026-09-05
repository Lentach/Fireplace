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

  /// AES-GCM appends a 16-byte authentication tag, so a plaintext that just
  /// passes [maxBytes] on the sender produces a ciphertext 16 bytes longer.
  /// The RECEIVER's size guard must compare against this, not [maxBytes] —
  /// otherwise a clip in the last 16 bytes under the cap sends fine and is
  /// refused on every receiver with a silent poster + "failed to load".
  static const int maxCiphertextBytes = maxBytes + 16;

  /// Client video-length policy, in seconds. Enforced by the composer with a
  /// toast and re-checked in `sendVideoMessage` as a backstop.
  ///
  /// Sized against the real constraint, which is bytes rather than seconds:
  /// iOS HTML Media Capture downsamples to ~360x480 and measures ~103 KB/s in
  /// production, so 180 s lands near 18.5 MB — inside [maxBytes] and inside
  /// nginx's `client_max_body_size`. A full-quality gallery clip is an order
  /// of magnitude denser and will hit [maxBytes] long before this cap; that
  /// asymmetry only disappears with on-device transcoding.
  static const int maxVideoDurationSeconds = 180;

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
