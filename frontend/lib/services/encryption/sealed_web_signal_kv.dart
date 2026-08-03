import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../utils/e2e_diag_log.dart';
import '../../utils/e2e_persistent_diag.dart';
import 'content_key_manager.dart';
import 'content_sealer.dart';
import 'sealed_sig_envelope.dart';
import 'session_cross_context_lock.dart';
import 'signal_stores.dart';

/// Web at-rest sealing for Signal key material
/// (docs/design/web-sig-sealing.md). Wraps the untouched [WebSignalKvStore]
/// and seals/unseals inline per async operation — no RAM view, no sync-read
/// machinery (the deliberate structural divergence from B2a).
///
/// The load-bearing rules (each has a red-proven test; do not weaken):
///
///  * **An unseal failure on a value read THROWS ([SigStoreUnreadable]),
///    never null.** Null here means ABSENT, and absence drives identity
///    regeneration, fresh-SessionRecord ratchet resets, and prekey id reuse.
///  * **[readAll] is presence-preserving, never value-throwing** (design
///    review R4): every real enumeration caller consumes key NAMES only, so
///    an unsealable value is returned as its raw `fpsig1:` string — the key
///    stays present and residue/highest-id/inventory answers stay correct
///    under any crypto transient. A future value-reading enumeration caller
///    must use [read] per key, which throws properly.
///  * **Nothing destructive happens at open, ever** (design rule 5): no row
///    scan folds, no retirement, no deletion. Keys unavailable while sealed
///    rows exist (or existence UNKNOWN — a failed probe) → the open THROWS
///    with `fallbackLegal: false` and E2E stays down this session.
///  * **The drain never overwrites unverified, never fights the ratchet, and
///    NEVER nests locks** (design review R2 + lock-order advisory): a
///    `session_` row is drained under ONLY the per-peer Web Lock the ratchet
///    write takes (`fireplace-e2e-session-<uid>-<peer>`); every other row
///    under ONLY the sig-keys lock. Holding sig-keys while waiting on a
///    per-peer lock is the ABBA half of a cross-engine deadlock: the ratchet
///    path holds per-peer and its first store op lazily opens this store,
///    which acquires sig-keys. Envelope round-trips in RAM before the write;
///    compare-and-set re-read before the overwrite; a changed/deleted row is
///    skipped, never clobbered.
///  * **Fallback never coexists with sealed rows** (design review R6):
///    enforced here for the open decision and in [FallbackWebSignalKv] for
///    every later write.
class SealedWebSignalKv implements SigWebKv {
  SealedWebSignalKv._(this._inner, this._keys, this._sealer, this._lock);

  /// Cross-context Web Lock serializing mint and non-session drain rows. Its
  /// own name: it touches no SessionRecord, no ledger, no content keys. It
  /// is NEVER held while acquiring any other lock (see the class doc).
  static const String lockName = 'fireplace-e2e-sig-keys';

  /// Active-kid marker, a cleartext control record in the sig namespace.
  /// Outside `e2e_<uid>_` so `clearAllKeys` cannot sweep it.
  static const String activeKidMarker = 'fp_sig_active_kid_v1';

  /// One-shot drain-done marker (cleartext control record).
  static const String drainDoneMarker = 'fp_sig_drain_done_v1';

  /// Sealed families, matched on the LOGICAL key (`e2e_<uid>_<family>`).
  /// Control records (`next_pre_key_id`, `setup_complete`) and anything
  /// unrecognized pass through verbatim — an unknown future key must not be
  /// silently sealed into a format an older build cannot read.
  static final RegExp _sealedFamily = RegExp(
    r'^e2e_\d+_(identity_record_v1$|identity_key_pair$|registration_id$'
    r'|pre_key_\d+$|signed_pre_key_\d+$|session_|trusted_identity_)',
  );

  static final RegExp _sessionKey = RegExp(r'^e2e_(\d+)_session_(.+)_\d+$');

  /// `trusted_identity_` rows are rewritten mid-session by `saveIdentity`,
  /// which runs under the per-peer session lock — so their drain takes the
  /// same lock (data-loss review: a sibling's re-pin landing mid-drain would
  /// otherwise be clobbered by the stale-pin envelope; self-healing via TOFU,
  /// but cheap to exclude at source).
  static final RegExp _trustedKey = RegExp(
    r'^e2e_(\d+)_trusted_identity_(.+)_\d+$',
  );

  /// Whether [key] belongs to a family whose value this store seals.
  static bool isSealedFamilyKey(String key) => _sealedFamily.hasMatch(key);

  final SigWebKv _inner;
  final ContentKeyManager _keys;
  final ContentSealer _sealer;
  final SessionCrossContextLockRunner _lock;

  Map<String, Uint8List> _knownKeys = <String, Uint8List>{};
  final Set<String> _refreshFailedKids = <String>{};
  late String _activeKid;
  late Uint8List _activeKey;

  /// Legacy plaintext rows of the sealed families awaiting the drain.
  final List<String> _legacyResidue = <String>[];

  bool _unreadableDiagRecorded = false;
  Future<void>? _drainFuture;

  @visibleForTesting
  String get debugActiveKid => _activeKid;

  @visibleForTesting
  List<String> get debugLegacyResidue => List.unmodifiable(_legacyResidue);

  @visibleForTesting
  Future<void> debugDrainNow() => _drainFuture ??= _drainLegacy();

  /// Opens and ARMS the store, or throws [SigSealOpenUnavailable] carrying
  /// the rule-4 fallback decision. Never destructive.
  static Future<SealedWebSignalKv> open({
    required SigWebKv inner,
    required ContentKeyManager keys,
    required ContentSealer sealer,
    SessionCrossContextLockRunner? lock,
  }) async {
    final store = SealedWebSignalKv._(
      inner,
      keys,
      sealer,
      lock ?? runSessionCrossContextLocked,
    );
    await store._lock(lockName, store._openLocked);
    if (store._legacyResidue.isNotEmpty) {
      unawaited(store.debugDrainNow());
    }
    return store;
  }

  Future<void> _openLocked() async {
    final openedAt = DateTime.now();
    final inventory = await _keys.inventory();

    // The probe: the ONLY evidence that fallback is legal is a SUCCESSFUL
    // enumeration showing zero envelopes (design review R5 — a failed probe
    // means "sealed rows may exist", which fails closed).
    Map<String, String>? all;
    try {
      all = await _inner.readAll();
    } catch (_) {
      all = null;
    }
    var sealedRows = 0;
    if (all != null) {
      for (final e in all.entries) {
        if (SealedSigEnvelope.isEnvelope(e.value)) sealedRows++;
      }
    }

    if (inventory == null) {
      if (all == null) {
        throw const SigSealOpenUnavailable('probe', fallbackLegal: false);
      }
      throw sealedRows > 0
          ? const SigSealOpenUnavailable('keys-unavailable', fallbackLegal: false)
          : const SigSealOpenUnavailable('inventory', fallbackLegal: true);
    }

    if (inventory.keys.isEmpty) {
      if (all == null) {
        // Cannot prove the store is envelope-free; minting and sealing over
        // unknown state is not allowed either. Down this session.
        throw const SigSealOpenUnavailable('probe', fallbackLegal: false);
      }
      if (sealedRows > 0) {
        // Successful enumeration, no sig keys, sealed rows on disk: key loss
        // or an unavailable-not-wiped store. NEVER destructive — the rows
        // stay, E2E stays down, the key may come back next boot.
        throw const SigSealOpenUnavailable('keys-lost', fallbackLegal: false);
      }
      final kid = await _keys.mintContentKey();
      if (kid == null) {
        throw const SigSealOpenUnavailable('mint', fallbackLegal: true);
      }
      final armed = await _keys.inventory();
      final bytes = armed?.keys[kid];
      if (bytes == null) {
        throw const SigSealOpenUnavailable('arm', fallbackLegal: true);
      }
      _knownKeys = armed!.keys;
      _activeKid = kid;
      _activeKey = bytes;
      await _writeMarker(kid);
    } else {
      _knownKeys = inventory.keys;
      final marker = all?[activeKidMarker] ?? await _readMarkerQuiet();
      if (marker != null && _knownKeys.containsKey(marker)) {
        _activeKid = marker;
      } else {
        // Fallback selection: deterministic "newest" (kids embed a mint
        // timestamp; length-then-lex orders the ms component correctly).
        final kids = _knownKeys.keys.toList()
          ..sort(
            (a, b) => a.length != b.length
                ? a.length.compareTo(b.length)
                : a.compareTo(b),
          );
        _activeKid = kids.last;
        await _writeMarker(_activeKid);
      }
      _activeKey = _knownKeys[_activeKid]!;
    }

    if (all != null) {
      for (final e in all.entries) {
        if (isSealedFamilyKey(e.key) &&
            !SealedSigEnvelope.isEnvelope(e.value)) {
          _legacyResidue.add(e.key);
        }
      }
    }

    E2eDiagLog.add('SIG_SEAL_OPEN', {
      'sealed': sealedRows,
      'legacy': all == null ? -1 : _legacyResidue.length,
      'ms': DateTime.now().difference(openedAt).inMilliseconds,
    });
  }

  Future<void> _writeMarker(String kid) async {
    try {
      await _inner.write(activeKidMarker, kid);
    } catch (_) {
      // Marker is an optimization; newest-kid selection recovers without it.
    }
  }

  Future<String?> _readMarkerQuiet() async {
    try {
      return await _inner.read(activeKidMarker);
    } catch (_) {
      return null;
    }
  }

  void _recordUnreadable(String stage) {
    if (_unreadableDiagRecorded) return;
    _unreadableDiagRecorded = true;
    E2ePersistentDiag.record('SIG_ROWS_UNREADABLE', {'stage': stage});
  }

  Future<Uint8List?> _keyForKid(String kid) async {
    final known = _knownKeys[kid];
    if (known != null) return known;
    if (_refreshFailedKids.contains(kid)) return null;
    // A sibling engine may have minted mid-session; refresh once per kid.
    final refreshed = await _keys.inventory();
    if (refreshed != null) {
      _knownKeys = refreshed.keys;
      final found = _knownKeys[kid];
      if (found != null) return found;
    }
    _refreshFailedKids.add(kid);
    return null;
  }

  /// Unseal [raw] (which MUST be an envelope) or throw [SigStoreUnreadable].
  Future<String> _unsealOrThrow(String raw) async {
    final env = SealedSigEnvelope.tryParse(raw);
    if (env == null) {
      _recordUnreadable('parse');
      throw const SigStoreUnreadable('parse');
    }
    final key = await _keyForKid(env.kid);
    if (key == null) {
      _recordUnreadable('kid');
      throw const SigStoreUnreadable('kid');
    }
    final plain = await _sealer.unseal(key, env.bytes);
    if (plain == null) {
      _recordUnreadable('unseal');
      throw const SigStoreUnreadable('unseal');
    }
    return utf8.decode(plain);
  }

  @override
  Future<void> write(String key, String value) async {
    if (!isSealedFamilyKey(key) || SealedSigEnvelope.isEnvelope(value)) {
      // Control/unknown keys verbatim; never double-seal an envelope.
      await _inner.write(key, value);
      return;
    }
    final sealed = await _sealer.seal(
      _activeKey,
      Uint8List.fromList(utf8.encode(value)),
    );
    if (sealed == null) {
      // A refused seal must FAIL the caller — silently persisting plaintext
      // instead would be a store that pretends to be sealed.
      throw const SigStoreUnreadable('seal');
    }
    await _inner.write(key, SealedSigEnvelope.encode(_activeKid, sealed));
  }

  @override
  Future<String?> read(String key) async {
    final raw = await _inner.read(key);
    if (raw == null) return null; // genuine absence keeps meaning absence
    if (!SealedSigEnvelope.isEnvelope(raw)) return raw; // read-both
    return _unsealOrThrow(raw);
  }

  @override
  Future<void> delete(String key) => _inner.delete(key);

  @override
  Future<Map<String, String>> readAll() async {
    final all = await _inner.readAll();
    final out = <String, String>{};
    for (final e in all.entries) {
      if (!SealedSigEnvelope.isEnvelope(e.value)) {
        out[e.key] = e.value;
        continue;
      }
      try {
        out[e.key] = await _unsealOrThrow(e.value);
      } on SigStoreUnreadable {
        // Presence-preserving: the key stays visible as its raw envelope so
        // residue/highest-id/inventory answers stay correct (review R4).
        out[e.key] = e.value;
      }
    }
    return out;
  }

  // -------------------------------------------------------------------------
  // Drain (design §3.3): resumable, never destructive, ratchet-safe.

  Future<void> _drainLegacy() async {
    const batchSize = 16;
    var sealedTotal = 0;
    for (var i = 0; i < _legacyResidue.length; i += batchSize) {
      final batch = _legacyResidue.sublist(
        i,
        (i + batchSize).clamp(0, _legacyResidue.length),
      );
      for (final key in batch) {
        // EXACTLY ONE lock per row, NEVER nested (lock-order advisory):
        // the ratchet path acquires per-peer → (lazy open) sig-keys, so a
        // drain holding sig-keys while WAITING on a per-peer lock is the
        // ABBA half of a cross-engine deadlock — Web Locks are origin-wide
        // with no timeout, and both engines would hang until a tab dies.
        //  * session AND trusted-identity rows take ONLY the per-peer lock
        //    (R2 + data-loss review: the same lock their writers take — the
        //    ratchet write and saveIdentity respectively);
        //  * every other row takes ONLY the sig-keys lock (no concurrent
        //    rewriter exists; this merely serializes against a future
        //    rotation and a sibling's drain).
        final peer = _sessionKey.firstMatch(key) ?? _trustedKey.firstMatch(key);
        final rowLock = peer != null
            ? 'fireplace-e2e-session-${peer.group(1)}-${peer.group(2)}'
            : lockName;
        final sealedOne = await _lock(rowLock, () => _drainOne(key));
        if (!sealedOne) {
          E2eDiagLog.add('SIG_SEAL_DRAIN_ABORT', {'sealed': sealedTotal});
          return; // abort: retry next session
        }
        sealedTotal++;
      }
      E2eDiagLog.add('SIG_SEAL_DRAIN', {'done': i + batch.length});
    }
    await _maybeRecordDrainDone();
  }

  /// True when the row needs no further work (sealed, skipped, or gone);
  /// false aborts the drain for this session.
  Future<bool> _drainOne(String key) async {
    final raw = await _inner.read(key);
    // Deleted or already sealed by a concurrent writer: nothing to do.
    if (raw == null || SealedSigEnvelope.isEnvelope(raw)) return true;
    final plainBytes = Uint8List.fromList(utf8.encode(raw));
    final sealed = await _sealer.seal(_activeKey, plainBytes);
    if (sealed == null) return false;
    // RAM round-trip BEFORE the destructive in-place write (H1 class): the
    // value under this key is the ONLY copy of this key material.
    final roundTrip = await _sealer.unseal(_activeKey, sealed);
    if (roundTrip == null || utf8.decode(roundTrip) != raw) return false;
    final envelope = SealedSigEnvelope.encode(_activeKid, sealed);
    // Compare-and-set (D1 class): a row rewritten or deleted since the first
    // read is SKIPPED — seal-on-write already covered it; clobbering it with
    // the stale envelope would roll back a ratchet. Cross-engine session
    // writers are excluded by the per-peer lock held by the caller.
    final current = await _inner.read(key);
    if (current != raw) return true;
    await _inner.write(key, envelope);
    final readBack = await _inner.read(key);
    return readBack == envelope;
  }

  Future<void> _maybeRecordDrainDone() async {
    try {
      final all = await _inner.readAll();
      var legacy = 0;
      var sealed = 0;
      for (final e in all.entries) {
        if (!isSealedFamilyKey(e.key)) continue;
        if (SealedSigEnvelope.isEnvelope(e.value)) {
          sealed++;
        } else {
          legacy++;
        }
      }
      if (legacy > 0) return;
      if (all[drainDoneMarker] != null) return; // one-shot
      await _inner.write(drainDoneMarker, '1');
      E2ePersistentDiag.record('SIG_SEAL_DRAIN_DONE', {'sealed': sealed});
    } catch (_) {
      // Purely informational; never let diagnostics fail the drain.
    }
  }
}

/// The pre-first-seal plaintext fallback (design §3.4). Legal ONLY because a
/// SUCCESSFUL probe found zero envelopes at open; because a sibling engine
/// can seal at any moment afterward, every WRITE re-probes and refuses to
/// persist plaintext beside sealed rows (design review R6). Reads keep
/// serving legacy plaintext; the session never flips to sealed mid-flight —
/// it only loses write permission.
class FallbackWebSignalKv implements SigWebKv {
  FallbackWebSignalKv(this._inner);

  final SigWebKv _inner;
  bool _supersededDiagRecorded = false;

  @override
  Future<void> write(String key, String value) async {
    if (SealedWebSignalKv.isSealedFamilyKey(key)) {
      final all = await _inner.readAll();
      final superseded = all.values.any(SealedSigEnvelope.isEnvelope);
      if (superseded) {
        if (!_supersededDiagRecorded) {
          _supersededDiagRecorded = true;
          E2ePersistentDiag.record('SIG_KEY_UNAVAILABLE', {
            'stage': 'fallback-superseded',
          });
        }
        throw const SigStoreUnreadable('fallback-superseded');
      }
    }
    await _inner.write(key, value);
  }

  @override
  Future<String?> read(String key) => _inner.read(key);

  @override
  Future<void> delete(String key) => _inner.delete(key);

  @override
  Future<Map<String, String>> readAll() => _inner.readAll();
}
