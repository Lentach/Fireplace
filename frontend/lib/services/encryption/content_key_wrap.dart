import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../secure_kv.dart';
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
  ContentKeyWrap({ContentSealer? sealer, SecureKv? meta})
    : _sealer = sealer ?? AesGcmContentSealer(),
      _meta = meta;

  /// Process-wide vault. The web store openers and `PasscodeProvider` have no
  /// other way to reach the same KEK: the openers are static functions
  /// resolved through conditional imports, and the provider lives above them
  /// in the widget tree. Mutable so a test can substitute its own.
  ///
  /// The meta record shares the `FireplaceE2E` secure store with the keys it
  /// describes — same instance and options as `signal_stores.dart` and the
  /// content opener use, so wrapping state cannot outlive its own keys.
  ///
  /// The meta store exists on WEB ONLY, for two reasons that happen to agree:
  /// wrapping is a web feature (owner ruling 2026-09-04), and off-web this
  /// would be a real platform channel — which in a widget test never answers,
  /// so every provider call that asked "is wrapping on?" would hang forever.
  /// With no store the answer is an immediate no.
  static ContentKeyWrap instance = ContentKeyWrap(
    meta: kIsWeb
        ? const FlutterSecureStorageKv(
            FlutterSecureStorage(webOptions: WebOptions(dbName: 'FireplaceE2E')),
          )
        : null,
  );

  final ContentSealer _sealer;
  final SecureKv? _meta;

  Uint8List? _kek;
  String? _kekId;
  PasscodeKekMeta? _cachedMeta;
  bool _metaRead = false;

  bool get isLocked => _kek == null;

  /// The KEK id this vault can open, or null while locked. A caller comparing
  /// it against an envelope's `kekId` can tell "locked with the wrong KEK"
  /// (a stale wrap after a passcode change) from "locked entirely".
  String? get kekId => _kekId;

  /// Whether this DEVICE has wrapping turned on, which is emphatically not the
  /// same question as [isLocked].
  ///
  /// Every user who never sets a passcode has a permanently locked vault, so
  /// treating locked as "wrapping on" would make `mintContentKey` refuse on a
  /// perfectly ordinary fresh install and drop the store into its plaintext
  /// fallback. The meta record is the only evidence that wrapping is on.
  Future<bool> isWrappingOn() async => (await _readMeta()) != null;

  /// The stored derivation parameters, or null when wrapping is off. Callers
  /// need the salt and cost factor to re-derive the KEK from a passcode.
  Future<PasscodeKekMeta?> readMeta() => _readMeta();

  Future<PasscodeKekMeta?> _readMeta() async {
    if (_metaRead) return _cachedMeta;
    final store = _meta;
    if (store == null) {
      _metaRead = true;
      return null;
    }
    try {
      _cachedMeta = PasscodeKekMeta.decode(
        await store.read(PasscodeKekMeta.storageKey),
      );
      _metaRead = true;
    } catch (_) {
      // Leave `_metaRead` false: a read that FAILED is not evidence that
      // wrapping is off, and caching it as such would let the next mint write
      // a raw key over a wrapped device.
      _cachedMeta = null;
    }
    return _cachedMeta;
  }

  void unlock({required Uint8List kek, required String kekId}) {
    _kek = kek;
    _kekId = kekId;
  }

  /// Turns wrapping on for this device and unlocks in the same step.
  ///
  /// The meta record is written FIRST, before any key is wrapped, and that
  /// order is the whole safety argument for an interrupted migration. Both
  /// failure directions were considered:
  ///
  ///  * meta present, some keys still raw ⇒ everything is still readable
  ///    (`inventory` handles both forms), so the device is merely LESS
  ///    protected until [wrapRawKeys] finishes on the next unlock;
  ///  * meta missing, some keys already wrapped ⇒ the KEK can never be
  ///    re-derived, every wrapped key reads as locked forever, and the only
  ///    way out is the destructive erase. That state must be unreachable.
  Future<bool> enableWrapping({
    required Uint8List kek,
    required String kekId,
    required int iterations,
    required String saltB64,
  }) async {
    final store = _meta;
    if (store == null) return false;
    final meta = PasscodeKekMeta(
      kekId: kekId,
      iterations: iterations,
      saltB64: saltB64,
    );
    final encoded = jsonEncode(meta.toJson());
    try {
      await store.write(PasscodeKekMeta.storageKey, encoded);
      if (await store.read(PasscodeKekMeta.storageKey) != encoded) return false;
    } catch (_) {
      return false;
    }
    _cachedMeta = meta;
    _metaRead = true;
    unlock(kek: kek, kekId: kekId);
    return true;
  }

  /// Turns wrapping off. The caller must have already unwrapped every key
  /// back to raw form — dropping the meta first would leave envelopes nothing
  /// can open.
  Future<void> disableWrapping() async {
    try {
      await _meta?.delete(PasscodeKekMeta.storageKey);
    } catch (_) {}
    _cachedMeta = null;
    _metaRead = true;
    lock();
  }

  /// Drops the KEK. Called on lock and on logout; after this every content
  /// key on disk is ciphertext to this process.
  ///
  /// The bytes are ZEROED before the reference drops: the sealer memoizes its
  /// imported `AesGcmSecretKey` in an `Expando` keyed on this exact object, so
  /// a copy surviving anywhere would keep a usable KEK alive in the heap long
  /// after the lock. Zeroing is what makes a mid-session re-lock cost the
  /// attacker the same arithmetic a cold boot does.
  void lock() {
    _kek?.fillRange(0, _kek!.length, 0);
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

  /// Wraps every still-raw key under [prefixes], in place and ARMED (write,
  /// then read back and prove it unwraps to the same bytes). Returns how many
  /// keys it converted, or null if the store could not be enumerated.
  ///
  /// Idempotent and resumable: already-wrapped entries are skipped, so this
  /// runs on every unlock and finishes a migration that was interrupted. A
  /// single key that fails to arm is rolled back to its raw form rather than
  /// left as an envelope the vault might not open.
  Future<int?> wrapRawKeys(List<String> prefixes) async {
    final store = _meta;
    if (store == null || isLocked) return null;
    final Map<String, String> all;
    try {
      all = await store.readAll();
    } catch (_) {
      return null;
    }

    var converted = 0;
    for (final entry in all.entries) {
      if (!prefixes.any(entry.key.startsWith)) continue;
      if (WrappedContentKey.isEnvelope(entry.value)) continue;
      final raw = _hexToBytes(entry.value);
      if (raw == null || raw.length != 32) continue;

      final envelope = await wrapKey(raw);
      if (envelope == null) continue;
      try {
        await store.write(entry.key, envelope);
        final back = await store.read(entry.key);
        final proof = back == null ? null : await unwrapKey(back);
        if (back != envelope || proof == null || !_sameBytes(proof, raw)) {
          // Could not prove the wrapped form opens. Put the raw key back:
          // an envelope this vault cannot read is exactly the state that
          // bricks the store.
          await store.write(entry.key, entry.value);
          continue;
        }
        converted++;
      } catch (_) {
        try {
          await store.write(entry.key, entry.value);
        } catch (_) {}
      }
    }
    return converted;
  }

  /// Unwraps every wrapped key under [prefixes] back to raw hex — the inverse
  /// migration, run BEFORE [disableWrapping] so no envelope is ever orphaned.
  /// Returns false when any key could not be restored, in which case the
  /// caller must keep wrapping ON.
  Future<bool> unwrapAllKeys(List<String> prefixes) async {
    final store = _meta;
    if (store == null || isLocked) return false;
    final Map<String, String> all;
    try {
      all = await store.readAll();
    } catch (_) {
      return false;
    }

    for (final entry in all.entries) {
      if (!prefixes.any(entry.key.startsWith)) continue;
      if (!WrappedContentKey.isEnvelope(entry.value)) continue;
      final raw = await unwrapKey(entry.value);
      if (raw == null || raw.length != 32) return false;
      final hex = _bytesToHex(raw);
      try {
        await store.write(entry.key, hex);
        if (await store.read(entry.key) != hex) return false;
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  /// Re-wraps every key under a NEW KEK (a passcode change). Unwraps with the
  /// current KEK first, so it must run while unlocked; the meta record is
  /// replaced only after every key is proven readable under the new KEK.
  Future<bool> rekey({
    required Uint8List newKek,
    required String newKekId,
    required int iterations,
    required String saltB64,
    required List<String> prefixes,
  }) async {
    if (isLocked) return false;
    // Back to raw under the old KEK, then forward under the new one. Raw is
    // the only representation both KEKs agree on, and a device interrupted
    // mid-rekey is left readable rather than orphaned.
    if (!await unwrapAllKeys(prefixes)) return false;
    if (!await enableWrapping(
      kek: newKek,
      kekId: newKekId,
      iterations: iterations,
      saltB64: saltB64,
    )) {
      return false;
    }
    return await wrapRawKeys(prefixes) != null;
  }

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String _bytesToHex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List? _hexToBytes(String s) {
    if (s.isEmpty || s.length.isOdd) return null;
    final out = Uint8List(s.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      final byte = int.tryParse(s.substring(i * 2, i * 2 + 2), radix: 16);
      if (byte == null) return null;
      out[i] = byte;
    }
    return out;
  }
}
