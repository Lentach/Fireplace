import 'dart:convert';
import 'dart:typed_data';

import 'content_sealer.dart';

/// Phase 2 of the app-level Passcode Lock: the passcode stops being a
/// verifier and becomes key material.
///
/// **What is wrapped and what is NOT — this distinction is the whole safety
/// argument.** Only the 32-byte content keys held by `ContentKeyManager`
/// (`fp_sig_key_<kid>`, `fp_content_key_<kid>`) are wrapped. The sealed rows
/// themselves keep their cleartext `fpsig1:` / `fps1:` envelope prefix and
/// their key NAMES, because:
///
///  * the sealed-store open probe counts sealed rows by that cleartext prefix
///    (`sealed_web_signal_kv.dart`), and a probe that sees zero sealed rows
///    declares a plaintext fallback LEGAL — after which the identity reads
///    `absent` and `EncryptionService` mints a new one. That is the
///    0.1.10/0.1.11 identity-loss catastrophe, reachable purely by encrypting
///    a prefix;
///  * `_hasPriorInstallResidue` scans key NAMES only
///    (`encryption_service.dart`), so renaming or hiding them would silently
///    switch off the residue guard.
///
/// With the wrap in this position, a locked device is already handled by the
/// existing machinery: no usable keys + sealed rows on disk ⇒
/// `SigSealOpenUnavailable(fallbackLegal: false)` ⇒ E2E down for the session,
/// nothing destructive, nothing minted.
///
/// Web-scoped by owner ruling (2026-09-04): on Android the same material is
/// already Keystore-backed behind `FLAG_SECURE`, and wrapping it there would
/// turn every Keystore fault into permanent history loss on the platform
/// where a forgotten code is currently survivable.

/// A content key at rest under the passcode-derived KEK.
///
/// `fpwk1:<kekId>:<base64(sealed)>` — prefix and `kekId` deliberately
/// CLEARTEXT so that a caller holding no KEK can still tell
/// "present but locked" from "absent", which is the difference between
/// "wait for the user" and "mint a new identity".
class WrappedContentKey {
  const WrappedContentKey._();

  static const String prefix = 'fpwk1:';

  static bool isEnvelope(String raw) => raw.startsWith(prefix);

  static String encode({required String kekId, required Uint8List sealed}) =>
      '$prefix$kekId:${base64Encode(sealed)}';

  /// The KEK id an envelope was wrapped under, or null if [raw] is not one.
  static String? kekIdOf(String raw) {
    if (!isEnvelope(raw)) return null;
    final rest = raw.substring(prefix.length);
    final sep = rest.indexOf(':');
    if (sep <= 0) return null;
    return rest.substring(0, sep);
  }

  /// The sealed bytes, or null when the envelope is malformed. A malformed
  /// envelope is still an envelope: callers must treat it as damaged/locked,
  /// never as an absent key.
  static Uint8List? sealedOf(String raw) {
    if (!isEnvelope(raw)) return null;
    final rest = raw.substring(prefix.length);
    final sep = rest.indexOf(':');
    if (sep <= 0) return null;
    try {
      return base64Decode(rest.substring(sep + 1));
    } catch (_) {
      return null;
    }
  }
}

/// How the KEK is derived, stored next to the wrapped keys so the cost factor
/// can be raised later without locking anyone out (NIST SP 800-63B-4
/// §3.1.1.1.2: "a reference to the password hashing scheme used, including the
/// cost factor, SHOULD be stored"; MetaMask ships the same `keyMetadata`
/// pattern for exactly this migration).
class PasscodeKekMeta {
  const PasscodeKekMeta({
    required this.kekId,
    required this.iterations,
    required this.saltB64,
  });

  /// Storage name of the meta record. Device-wide, alongside the keys it
  /// describes, and OUTSIDE the `e2e_<uid>_` namespace that `clearAllKeys`
  /// sweeps on logout — the wrap must survive a logout exactly as the keys do.
  static const String storageKey = 'fp_passcode_kek_meta_v1';

  static const int version = 1;

  final String kekId;
  final int iterations;
  final String saltB64;

  Uint8List get salt => base64Decode(saltB64);

  Map<String, dynamic> toJson() => {
    'v': version,
    'kdf': 'PBKDF2-HMAC-SHA256',
    'kekId': kekId,
    'iters': iterations,
    'salt': saltB64,
  };

  /// Null for anything unparseable — never a default. A meta record we cannot
  /// read means we cannot derive the KEK, which must surface as locked, not as
  /// "no wrapping configured" (that would read the wrapped keys as garbage).
  static PasscodeKekMeta? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final kekId = map['kekId'];
      final iters = map['iters'];
      final salt = map['salt'];
      if (kekId is! String || kekId.isEmpty) return null;
      if (iters is! int || iters <= 0) return null;
      if (salt is! String || salt.isEmpty) return null;
      return PasscodeKekMeta(
        kekId: kekId,
        iterations: iters,
        saltB64: salt,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Holds the passcode-derived KEK for the unlocked session and wraps/unwraps
/// content keys with it.
///
/// Locked means "no KEK in memory": every wrap and unwrap answers null, and
/// callers MUST translate that into unavailable-not-absent. It never answers
/// with a guess.
class ContentKeyWrap {
  ContentKeyWrap({ContentSealer? sealer})
    : _sealer = sealer ?? AesGcmContentSealer();

  final ContentSealer _sealer;

  Uint8List? _kek;
  String? _kekId;

  bool get isLocked => _kek == null;

  /// The KEK id this vault can open, or null while locked. A caller comparing
  /// it against an envelope's `kekId` can tell "locked with the wrong KEK"
  /// (a stale wrap after a passcode change) from "locked entirely".
  String? get kekId => _kekId;

  void unlock({required Uint8List kek, required String kekId}) {
    _kek = kek;
    _kekId = kekId;
  }

  /// Drops the KEK. Called on lock and on logout; after this every content
  /// key on disk is ciphertext to this process.
  void lock() {
    _kek = null;
    _kekId = null;
  }

  /// Wraps a raw 32-byte content key for storage, or null while locked / if
  /// the cipher refuses. Null must never be persisted as a raw key.
  Future<String?> wrapKey(Uint8List raw) async {
    final kek = _kek;
    final id = _kekId;
    if (kek == null || id == null) return null;
    final sealed = await _sealer.seal(kek, raw);
    if (sealed == null) return null;
    return WrappedContentKey.encode(kekId: id, sealed: sealed);
  }

  /// Opens an envelope, or null when locked, when the KEK is the wrong one, or
  /// when the envelope is damaged. The caller distinguishes those from an
  /// absent key by the envelope's mere presence.
  Future<Uint8List?> unwrapKey(String envelope) async {
    final kek = _kek;
    if (kek == null) return null;
    final sealed = WrappedContentKey.sealedOf(envelope);
    if (sealed == null) return null;
    return _sealer.unseal(kek, sealed);
  }
}
