import 'dart:math';

import 'package:flutter/foundation.dart';

import '../secure_kv.dart';

/// Owns the at-rest keys of the native encrypted content store.
///
/// Two kinds of key live here, with different lifecycles:
///
///  * **The DB key** (`fp_content_db_key_v1`) unlocks the SQLCipher file. It is
///    minted once and never rotated: rotating it re-encrypts pages in place,
///    which shreds nothing (freed pages are re-encrypted along with live ones,
///    still readable under the new key). File-level encryption protects the
///    cleartext metadata — key strings, kids, timestamps — not the payloads.
///  * **Content keys** (`fp_content_key_<kid>`) seal record payloads and audio
///    files individually. THESE are what rotation destroys: after a purge, a
///    new kid re-seals every survivor and the old key is deleted, so freelist
///    and WAL residue of purged records becomes ciphertext under a key that no
///    longer exists. That destruction is the only real shredding this design
///    has — SQLite deletes never shred (`PRAGMA secure_delete` is defense in
///    depth only), and flash wear-leveling keeps the usual honest caveat.
///
/// All entries live in the SAME `flutter_secure_storage` instance as the
/// Signal keys, deliberately WITHOUT auth binding: failure modes must stay
/// correlated. If secure storage dies, the Signal identity dies with it and
/// the app is already in its identity-loss path; a content key that could die
/// alone (biometric re-enrollment, auth-bound invalidation) would add a brand
/// new way to lose the whole local history — the cache is NOT re-derivable
/// (the ratchet consumed the message keys; media records hold the only
/// mediaKey/mediaIv).
///
/// Keys are NOT namespaced under `e2e_<uid>_` on purpose: `clearAllKeys`
/// sweeps that prefix on logout/account deletion, and the content keys must
/// survive it — another account on the same device shares the store, and the
/// deleted account's rows are shredded by the rotation that its row removals
/// stamp, not by deleting the shared key.
class ContentKeyManager {
  ContentKeyManager(this._secure, {String keyPrefix = contentKeyPrefix})
    : _keyPrefix = keyPrefix;

  final SecureKv _secure;

  /// Which payload-key family this instance owns. Defaults to the content
  /// family; the web sig-sealing store passes [sigKeyPrefix] — a SEPARATE
  /// namespace so content-key rotation/shredding can never destroy a key
  /// Signal rows still need (docs/design/web-sig-sealing.md §3.2).
  final String _keyPrefix;

  static const String dbKeyName = 'fp_content_db_key_v1';
  static const String contentKeyPrefix = 'fp_content_key_';
  static const String sigKeyPrefix = 'fp_sig_key_';

  static final Random _rng = Random.secure();

  static Uint8List _randomBytes(int n) =>
      Uint8List.fromList(List<int>.generate(n, (_) => _rng.nextInt(256)));

  /// The SQLCipher raw-key pragma value (`x'<64 hex>'`), minting and ARMING it
  /// on first use. Null means secure storage refused a durable write OR the
  /// read itself failed — the caller must fall back to the legacy path, never
  /// open a DB with a key that may not exist on the next launch.
  ///
  /// [DbKeyResult.freshlyMinted] is the recreate gate: the opener may delete
  /// an unopenable DB file ONLY when this call provably enumerated secure
  /// storage and found no key (a mint). A transient read failure returns null
  /// here instead, so it can never be misread as "the old key is gone" and
  /// destroy a recoverable database.
  ///
  /// Armed-gate, same rule as the web codec design: persist, then prove the
  /// persist with a FRESH read (flutter_secure_storage has no read cache — a
  /// read is a real platform round trip), and only then let anything depend on
  /// the key. The naive order can encrypt a database whose key was never
  /// stored, which converts every record on the device into noise, silently.
  Future<DbKeyResult?> dbKeyHex() async {
    try {
      final existing = await _secure.read(dbKeyName);
      if (existing != null && _isHex64(existing)) {
        return DbKeyResult(hex: existing, freshlyMinted: false);
      }
      final hex = _toHex(_randomBytes(32));
      await _secure.write(dbKeyName, hex);
      final readBack = await _secure.read(dbKeyName);
      if (readBack != hex) return null;
      return DbKeyResult(hex: hex, freshlyMinted: true);
    } catch (_) {
      return null;
    }
  }

  /// Every content key currently held, or null when secure storage could not
  /// be ENUMERATED — and the difference is load-bearing. A transient read
  /// failure (Keystore not ready, device still locked after boot, plugin init
  /// race — all real on Android) must never be read as "the keys are gone":
  /// that misreading would retire the entire history over a hiccup. Null
  /// means "answer unknown, change nothing"; a successfully enumerated map
  /// that lacks a kid is the only evidence of genuine key loss.
  ///
  /// [otherEntryCount] reports how many NON-content entries the enumeration
  /// saw (Signal keys live in the same store, so any real device has some).
  /// An enumeration that succeeds but returns nothing at all is treated by
  /// the caller as unavailable-not-wiped, because a wiped secure store also
  /// means a wiped Signal identity — a different failure with its own path.
  ///
  /// Entries that fail to parse are dropped (a corrupt value cannot decrypt
  /// anything anyway; reporting it as present would just turn key-loss
  /// detection off).
  Future<KeyInventory?> inventory() async {
    try {
      final keys = <String, Uint8List>{};
      var others = 0;
      final all = await _secure.readAll();
      for (final entry in all.entries) {
        if (!entry.key.startsWith(_keyPrefix)) {
          others++;
          continue;
        }
        final kid = entry.key.substring(_keyPrefix.length);
        final bytes = _fromHex(entry.value);
        if (kid.isNotEmpty && bytes != null && bytes.length == 32) {
          keys[kid] = bytes;
        }
      }
      return KeyInventory(keys: keys, otherEntryCount: others);
    } catch (_) {
      return null;
    }
  }

  /// Mint and ARM a new content key. Returns its kid, or null when the write
  /// could not be proven durable (in which case any partial entry is removed
  /// best-effort and nothing may be sealed under it).
  ///
  /// The kid embeds a time component only to be unique and debuggable; nothing
  /// parses it.
  Future<String?> mintContentKey() async {
    final kid =
        'k${DateTime.now().toUtc().millisecondsSinceEpoch}${_rng.nextInt(0xffff)}';
    final name = '$_keyPrefix$kid';
    final hex = _toHex(_randomBytes(32));
    try {
      await _secure.write(name, hex);
      final readBack = await _secure.read(name);
      if (readBack != hex) {
        try {
          await _secure.delete(name);
        } catch (_) {}
        return null;
      }
      return kid;
    } catch (_) {
      try {
        await _secure.delete(name);
      } catch (_) {}
      return null;
    }
  }

  /// Destroy the content key [kid]. This is the shredding step: everything
  /// still sealed under it — freelist pages, WAL frames, replaced audio bytes
  /// — becomes unrecoverable ciphertext. Only call once NOTHING live still
  /// needs it (the rotation controller owns that proof).
  ///
  /// Returns whether the entry is confirmed gone; a false leaves the key alive
  /// and the rotation must not report the shred as done.
  Future<bool> destroyContentKey(String kid) async {
    final name = '$_keyPrefix$kid';
    try {
      await _secure.delete(name);
      return await _secure.read(name) == null;
    } catch (_) {
      return false;
    }
  }

  static String _toHex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static bool _isHex64(String s) =>
      s.length == 64 && RegExp(r'^[0-9a-f]+$').hasMatch(s);

  static Uint8List? _fromHex(String s) {
    if (s.length.isOdd) return null;
    final out = Uint8List(s.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      final byte = int.tryParse(s.substring(i * 2, i * 2 + 2), radix: 16);
      if (byte == null) return null;
      out[i] = byte;
    }
    return out;
  }
}

/// Result of a SUCCESSFUL secure-storage enumeration. See
/// [ContentKeyManager.inventory] for why failure is a distinct null, not an
/// empty map.
class KeyInventory {
  const KeyInventory({required this.keys, required this.otherEntryCount});

  final Map<String, Uint8List> keys;
  final int otherEntryCount;
}

/// See [ContentKeyManager.dbKeyHex].
class DbKeyResult {
  const DbKeyResult({required this.hex, required this.freshlyMinted});

  final String hex;
  final bool freshlyMinted;
}
