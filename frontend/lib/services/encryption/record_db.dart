import 'dart:typed_data';

/// One row of the native content store.
///
/// Exactly one of [sealed]+[kid] (encrypted payload), [text] (cleartext
/// string), or [intValue] is populated, mirroring which `ContentKv` write
/// produced it. `kid` is CLEARTEXT by design: key-loss detection and rotation
/// must find rows by key id without decrypting anything (same trade-off as the
/// sealed-record envelope and the sealed audio header).
class RecordRow {
  const RecordRow({
    required this.k,
    this.kid,
    this.sealed,
    this.text,
    this.intValue,
  });

  final String k;
  final String? kid;

  /// `12-byte IV || AES-256-GCM ciphertext+tag` under the content key [kid].
  final Uint8List? sealed;
  final String? text;
  final int? intValue;
}

/// Minimal persistence surface of the native content store.
///
/// Deliberately this thin: everything with behavior worth testing — sealing,
/// the armed-gate, key-loss retirement, the legacy drain, rotation — lives
/// ABOVE this interface in `NativeContentStore`, so those tests run against
/// [InMemoryRecordDb] with no SQLite on the host. The drift/SQLCipher
/// implementation below it stays too thin to hide logic.
///
/// Every mutation answers whether it durably committed. `false`/throw both
/// mean "assume it is not on disk" — callers gate on it exactly like the
/// SharedPreferences commit results.
abstract class RecordDb {
  /// Every row. Called once at open to build the read view.
  Future<List<RecordRow>> loadAll();

  /// Upsert. Returns whether the write committed.
  Future<bool> put(RecordRow row);

  /// Returns whether the delete committed (deleting an absent key commits).
  Future<bool> delete(String k);

  /// Rows sealed under [kid], at most [limit].
  Future<List<RecordRow>> rowsByKid(String kid, int limit);

  /// Upsert many rows in one transaction. All-or-nothing — a rotation batch
  /// must never half-apply, or an interrupted rotation strands rows under a
  /// kid the bookkeeping believes drained.
  Future<bool> putMany(List<RecordRow> rows);

  Future<String?> getMeta(String k);

  Future<bool> setMeta(String k, String v);

  Future<bool> removeMeta(String k);

  /// Best-effort hygiene after a rotation: checkpoint/truncate the WAL so
  /// frames holding pre-rotation ciphertext stop accumulating. Defense in
  /// depth only — the shred guarantee comes from destroying the old key, and
  /// this must never be load-bearing.
  Future<void> vacuumHint();

  Future<void> close();
}

/// Hermetic [RecordDb] for tests.
class InMemoryRecordDb implements RecordDb {
  final Map<String, RecordRow> rows = <String, RecordRow>{};
  final Map<String, String> meta = <String, String>{};

  /// Test hook: when positive, that many upcoming mutations refuse to commit.
  int failNextWrites = 0;

  bool _takeFailure() {
    if (failNextWrites > 0) {
      failNextWrites--;
      return true;
    }
    return false;
  }

  @override
  Future<List<RecordRow>> loadAll() async => rows.values.toList();

  @override
  Future<bool> put(RecordRow row) async {
    if (_takeFailure()) return false;
    rows[row.k] = row;
    return true;
  }

  @override
  Future<bool> delete(String k) async {
    if (_takeFailure()) return false;
    rows.remove(k);
    return true;
  }

  @override
  Future<List<RecordRow>> rowsByKid(String kid, int limit) async {
    final matching = rows.values.where((r) => r.kid == kid).toList()
      ..sort((a, b) => a.k.compareTo(b.k));
    return matching.take(limit).toList();
  }

  @override
  Future<bool> putMany(List<RecordRow> batch) async {
    if (_takeFailure()) return false;
    for (final row in batch) {
      rows[row.k] = row;
    }
    return true;
  }

  @override
  Future<String?> getMeta(String k) async => meta[k];

  @override
  Future<bool> setMeta(String k, String v) async {
    if (_takeFailure()) return false;
    meta[k] = v;
    return true;
  }

  @override
  Future<bool> removeMeta(String k) async {
    if (_takeFailure()) return false;
    meta.remove(k);
    return true;
  }

  @override
  Future<void> vacuumHint() async {}

  @override
  Future<void> close() async {}
}
