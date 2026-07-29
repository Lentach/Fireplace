import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The storage seam under [EncryptionService]'s plaintext-record machinery.
///
/// Every persisted plaintext artifact — decrypted records, the raw replay
/// cache, pending-send records, the purge backlog, retention stamps, the
/// retired-id set — historically went through raw [SharedPreferences]. That
/// backend is being replaced on native (encrypted DB, issue #105 M4) WITHOUT
/// touching the semantics above it: commit-gated removals, the durable purge
/// backlog, two-phase expiry, reconcile, retention, the LRU — all of it was
/// paid for in the field and survives unchanged. So this interface mirrors the
/// exact [SharedPreferences] surface those code paths use, shape for shape:
///
///  * READS ARE SYNCHRONOUS against a loaded view. [SharedPreferences] serves
///    reads from its in-memory cache; the native store loads its records once
///    at open and serves reads the same way. Callers may loop `getString` over
///    thousands of keys without paying a round trip each.
///  * WRITES RETURN THE COMMIT RESULT. `setString`/`remove` answering `false`
///    is load-bearing: a dropped write is how a decrypted message later
///    re-decrypts, hits DuplicateMessage and bricks to a permanent
///    "[Decryption failed]" (see `saveDecryptedContent`). An implementation
///    must never report success for a write it cannot prove committed.
///  * [reload] is the cross-context coherence point. On web, another PWA
///    engine may have written plaintext this engine has not seen; serving a
///    stale snapshot there means a cache miss on a consumed ciphertext. On
///    native there is one process, so it is a no-op.
abstract class ContentKv {
  /// Refresh the read view from the backing store where another context can
  /// have written to it. Web-only concern; a no-op elsewhere.
  Future<void> reload();

  String? getString(String key);

  int? getInt(String key);

  bool containsKey(String key);

  /// Every key currently in the store. Prefix scans over this set are how all
  /// sweeps enumerate records; implementations must return the complete live
  /// key set, not a filtered view.
  Set<String> getKeys();

  /// Returns whether the value durably committed. Implementations retry
  /// nothing themselves — the callers own their retry policy.
  Future<bool> setString(String key, String value);

  Future<bool> setInt(String key, int value);

  /// Returns whether the removal durably committed. Removing an absent key
  /// succeeds ([SharedPreferences] semantics — callers distinguish presence
  /// via [containsKey] BEFORE removing, see `removeDecryptedContent`).
  Future<bool> remove(String key);
}

/// [SharedPreferences]-backed [ContentKv]: the historical behavior, verbatim.
///
/// This is the ONLY backend on web (localStorage writes are synchronous in JS
/// and survive tab close, which is why the records live there and not in
/// IndexedDB) and the fallback on native when the encrypted store cannot open
/// or arm — per the armed-gate rule, an unarmed device keeps writing the
/// legacy way rather than risk sealing records under a key that never
/// persisted.
class PrefsContentKv implements ContentKv {
  PrefsContentKv(this._prefs);

  static Future<PrefsContentKv> open() async =>
      PrefsContentKv(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  /// Web-only, same rule as the previous inline `_reloadPrefsForCrossContext`:
  /// on web `reload()` is a full localStorage enumeration (measured 65-77 ms
  /// per 50-row pass when called per row), so callers pay it once per pass —
  /// and on native the plugin cache is authoritative within the process.
  @override
  Future<void> reload() async {
    if (kIsWeb) await _prefs.reload();
  }

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  int? getInt(String key) => _prefs.getInt(key);

  @override
  bool containsKey(String key) => _prefs.containsKey(key);

  @override
  Set<String> getKeys() => _prefs.getKeys();

  @override
  Future<bool> setString(String key, String value) =>
      _prefs.setString(key, value);

  @override
  Future<bool> setInt(String key, int value) => _prefs.setInt(key, value);

  @override
  Future<bool> remove(String key) => _prefs.remove(key);
}
