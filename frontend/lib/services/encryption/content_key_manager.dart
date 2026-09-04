import 'dart:math';

import 'package:flutter/foundation.dart';

import '../secure_kv.dart';
import 'content_key_wrap.dart';

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
  ContentKeyManager(
    this._secure, {
    String keyPrefix = contentKeyPrefix,
    ContentKeyWrap? wrap,
  }) : _keyPrefix = keyPrefix,
       _wrap = wrap;

  final SecureKv _secure;

  /// Which payload-key family this instance owns. Defaults to the content
  /// family; the web sig-sealing store passes [sigKeyPrefix] — a SEPARATE
  /// namespace so content-key rotation/shredding can never destroy a key
  /// Signal rows still need (docs/design/web-sig-sealing.md §3.2).
  final String _keyPrefix;

  /// Passcode-derived wrap for this family's keys, or null when wrapping is
  /// off (native builds, and web before the user enables Phase 2). See
  /// `content_key_wrap.dart` for why only the KEYS are wrapped.
  final ContentKeyWrap? _wrap;

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

  /// Every content key currently USABLE, plus how many are present but
  /// locked, or null when secure storage could not be ENUMERATED — and all
  /// three answers are load-bearing. A transient read failure (Keystore not
  /// ready, device still locked after boot, plugin init race — all real on
  /// Android) must never be read as "the keys are gone": that misreading
  /// would retire the entire history over a hiccup. Null means "answer
  /// unknown, change nothing"; a successfully enumerated map that lacks a kid
  /// is the only evidence of genuine key loss.
  ///
  /// [otherEntryCount] reports how many NON-content entries the enumeration
  /// saw (Signal keys live in the same store, so any real device has some).
  /// An enumeration that succeeds but returns nothing at all is treated by
  /// the caller as unavailable-not-wiped, because a wiped secure store also
  /// means a wiped Signal identity — a different failure with its own path.
  ///
  /// [KeyInventory.lockedKeyCount] counts passcode-wrapped keys this process
  /// cannot open right now (`ContentKeyWrap` locked, wrong KEK, damaged
  /// envelope). It exists because the alternative — dropping them like any
  /// other unparseable value — makes a locked device look like a device with
  /// NO keys, and a device with no keys and no sealed rows mints a fresh key
  /// or falls back to plaintext. Callers MUST treat a non-zero count as
  /// unavailable-not-absent, whatever the sealed-row probe says.
  ///
  /// Entries that fail to parse and are NOT envelopes are dropped (a corrupt
  /// raw value cannot decrypt anything anyway; reporting it as present would
  /// just turn key-loss detection off).
  Future<KeyInventory?> inventory() async {
    try {
      final keys = <String, Uint8List>{};
      var others = 0;
      var locked = 0;
      final all = await _secure.readAll();
      for (final entry in all.entries) {
        if (!entry.key.startsWith(_keyPrefix)) {
          others++;
          continue;
        }
        final kid = entry.key.substring(_keyPrefix.length);
        if (kid.isEmpty) continue;
        if (WrappedContentKey.isEnvelope(entry.value)) {
          final opened = await _wrap?.unwrapKey(entry.value);
          if (opened != null && opened.length == 32) {
            keys[kid] = opened;
          } else {
            locked++;
          }
          continue;
        }
        final bytes = _fromHex(entry.value);
        if (bytes != null && bytes.length == 32) {
          keys[kid] = bytes;
        }
      }
      return KeyInventory(
        keys: keys,
        otherEntryCount: others,
        lockedKeyCount: locked,
      );
    } catch (_) {
      return null;
    }
  }

  /// Mint and ARM a new content key. Returns its kid, or null when the write
  /// could not be proven durable (in which case any partial entry is removed
  /// best-effort and nothing may be sealed under it).
  ///
  /// Under wrapping, minting while LOCKED returns null instead of writing a
  /// raw key: a key minted while locked would be readable without the
  /// passcode, which is precisely the door Phase 2 closes. It is also the
  /// path a mis-set `lockedKeyCount` would take, so it fails closed twice.
  ///
  /// The kid embeds a time component only to be unique and debuggable; nothing
  /// parses it.
  Future<String?> mintContentKey() async {
    final wrap = _wrap;
    if (wrap != null && wrap.isLocked) return null;

    final kid =
        'k${DateTime.now().toUtc().millisecondsSinceEpoch}${_rng.nextInt(0xffff)}';
    final name = '$_keyPrefix$kid';
    final raw = _randomBytes(32);
    final stored = wrap == null ? _toHex(raw) : await wrap.wrapKey(raw);
    if (stored == null) return null;
    try {
      await _secure.write(name, stored);
      final readBack = await _secure.read(name);
      if (readBack != stored) {
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
  const KeyInventory({
    required this.keys,
    required this.otherEntryCount,
    this.lockedKeyCount = 0,
  });

  /// Passcode-wrapped keys this process cannot open right now. Non-zero means
  /// unavailable-not-absent: callers MUST NOT mint, MUST NOT fall back to a
  /// plaintext store, and MUST NOT let an identity read resolve to `absent`.
  final int lockedKeyCount;

  final Map<String, Uint8List> keys;
  final int otherEntryCount;
}

/// See [ContentKeyManager.dbKeyHex].
class DbKeyResult {
  const DbKeyResult({required this.hex, required this.freshlyMinted});

  final String hex;
  final bool freshlyMinted;
}
