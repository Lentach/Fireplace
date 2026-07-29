import 'dart:typed_data';

import 'package:webcrypto/webcrypto.dart';

/// The symmetric primitive sealing record payloads in the native store.
///
/// An interface for one reason: the store's failure-mode logic (armed-gate,
/// key-loss retirement, rotation resume) must be testable on hosts where the
/// webcrypto native library is not set up, and those tests are about state
/// machines, not ciphers. Production always uses [AesGcmContentSealer]; a
/// test may substitute a deterministic fake without weakening the real
/// cipher's own round-trip coverage.
abstract class ContentSealer {
  /// `12-byte IV || ciphertext+tag` under [key], or null on any failure —
  /// callers treat null as a refused write, never as empty content.
  Future<Uint8List?> seal(Uint8List key, Uint8List plaintext);

  /// Inverse of [seal]. Null for wrong key, tampered bytes, or a malformed
  /// envelope — never an empty plaintext (that round-trips as empty bytes).
  Future<Uint8List?> unseal(Uint8List key, Uint8List sealed);
}

/// AES-256-GCM via `package:webcrypto` (BoringSSL on Android — the same
/// primitive the media path uses).
class AesGcmContentSealer implements ContentSealer {
  /// Imported-key cache keyed on the raw key OBJECT. The store hands the same
  /// `Uint8List` per kid for its whole lifetime, and an [Expando] releases the
  /// import the moment rotation drops the raw key — no explicit invalidation
  /// to forget. The open path unseals every row at startup, so re-importing
  /// per call would be ~2N imports for N records.
  final Expando<AesGcmSecretKey> _imported = Expando<AesGcmSecretKey>();

  Future<AesGcmSecretKey> _key(Uint8List raw) async =>
      _imported[raw] ??= await AesGcmSecretKey.importRawKey(raw);

  @override
  Future<Uint8List?> seal(Uint8List key, Uint8List plaintext) async {
    try {
      final imported = await _key(key);
      final iv = Uint8List(12);
      fillRandomBytes(iv);
      final ct = await imported.encryptBytes(plaintext, iv);
      final out = Uint8List(12 + ct.length);
      out.setRange(0, 12, iv);
      out.setRange(12, out.length, ct);
      return out;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Uint8List?> unseal(Uint8List key, Uint8List sealed) async {
    if (sealed.length < 13) return null;
    try {
      final imported = await _key(key);
      final plain = await imported.decryptBytes(
        Uint8List.sublistView(sealed, 12),
        Uint8List.sublistView(sealed, 0, 12),
      );
      return Uint8List.fromList(plain);
    } catch (_) {
      return null;
    }
  }
}
