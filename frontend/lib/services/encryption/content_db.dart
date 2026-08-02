import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;

import 'record_db.dart';

part 'content_db.g.dart';

/// Rows of the native content store. `k` is the exact legacy
/// SharedPreferences key string — keeping it verbatim is what lets every
/// prefix-scan sweep above the `ContentKv` seam work unchanged.
class ContentRecords extends Table {
  TextColumn get k => text()();

  /// Content key id when [v] is sealed; null when [v]/[vi] is cleartext.
  /// Cleartext on purpose: key-loss detection and rotation select on it.
  TextColumn get kid => text().nullable()();

  /// Sealed: `12-byte IV || AES-256-GCM ciphertext+tag`. Cleartext: UTF-8.
  BlobColumn get v => blob().nullable()();

  IntColumn get vi => integer().nullable()();

  @override
  Set<Column> get primaryKey => {k};
}

/// Store bookkeeping: schema markers, the active kid, the shred generation
/// counters. Kept out of [ContentRecords] so a key-space scan never confuses
/// bookkeeping with records.
class ContentMetaRows extends Table {
  TextColumn get k => text()();
  TextColumn get v => text()();

  @override
  Set<Column> get primaryKey => {k};
}

@DriftDatabase(tables: [ContentRecords, ContentMetaRows])
class ContentDb extends _$ContentDb {
  ContentDb(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement(
        'CREATE INDEX idx_content_records_kid ON content_records (kid) '
        'WHERE kid IS NOT NULL',
      );
    },
  );
}

/// [RecordDb] over drift + SQLCipher. Thin by contract — see [RecordDb].
class DriftRecordDb implements RecordDb {
  DriftRecordDb._(this._db);

  final ContentDb _db;

  /// Opens (creating if absent) the encrypted store under the app support
  /// directory — NOT documents, which platform backup logic sweeps.
  ///
  /// THROWS when the executable SQLite is not SQLCipher or the key pragma
  /// fails. That check is a runtime invariant, not a debug assert: with the
  /// Android cipher override missing, `PRAGMA key` on stock SQLite is a
  /// silent no-op and every "sealed" byte would land on disk unencrypted
  /// while all tests stay green. The caller catches and falls back to the
  /// legacy path (status quo, loudly diagnosed) rather than ever running on
  /// a silently-plaintext database.
  static Future<DriftRecordDb> open({required String dbKeyHex}) async {
    final file = await databaseFile();
    final db = ContentDb(
      NativeDatabase.createInBackground(
        file,
        isolateSetup: _setupSqlCipher,
        setup: (raw) {
          final cipher = raw.select('PRAGMA cipher_version;');
          if (cipher.isEmpty) {
            throw StateError(
              'SQLCipher not linked: PRAGMA cipher_version is empty. '
              'Refusing to run on a plaintext database.',
            );
          }
          // Raw-key form: no KDF pass, and the key never appears as a
          // passphrase in any log that echoes pragmas.
          raw.execute('PRAGMA key = "x\'$dbKeyHex\'";');
          // Force early key verification: wrong key => throws here, inside
          // open, instead of on the first query.
          raw.select('SELECT count(*) FROM sqlite_master;');
          // Defense in depth only. Deletes still do not shred (freelist
          // pages survive intact); the shred guarantee is rotate-and-destroy
          // of the content key.
          raw.execute('PRAGMA secure_delete = ON;');
          raw.execute('PRAGMA journal_mode = WAL;');
        },
      ),
    );
    try {
      // Surface a bad key / missing cipher NOW: the first statement forces
      // the background isolate to actually open the file.
      await db.customSelect('SELECT 1').get();
    } catch (_) {
      await db.close();
      rethrow;
    }
    return DriftRecordDb._(db);
  }

  /// The store's on-disk location, shared with [deleteDatabaseFiles].
  static Future<File> databaseFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}fp_content.db');
  }

  /// Removes the database and its WAL/SHM siblings. ONLY for the
  /// unopenable-with-freshly-minted-key case (see the opener): the file is
  /// then noise nobody can ever read, and a file delete of noise is not a
  /// shred claim. Returns whether the paths are confirmed gone.
  static Future<bool> deleteDatabaseFiles() async {
    try {
      final file = await databaseFile();
      for (final path in [file.path, '${file.path}-wal', '${file.path}-shm']) {
        final f = File(path);
        if (await f.exists()) await f.delete();
      }
      return !await file.exists();
    } catch (_) {
      return false;
    }
  }

  static void _setupSqlCipher() {
    sqlite3_open.open.overrideFor(
      sqlite3_open.OperatingSystem.android,
      openCipherOnAndroid,
    );
  }

  @override
  Future<List<RecordRow>> loadAll() async {
    final rows = await _db.select(_db.contentRecords).get();
    final out = <RecordRow>[];
    for (final r in rows) {
      // Per-row: one damaged record (malformed UTF-8 above all) must degrade
      // to one skipped row, never throw the whole open path into the legacy
      // fallback and hide the entire history for the session.
      try {
        out.add(
          RecordRow(
            k: r.k,
            kid: r.kid,
            sealed: r.kid != null ? r.v : null,
            text: r.kid == null && r.v != null ? utf8.decode(r.v!) : null,
            intValue: r.vi,
          ),
        );
      } catch (_) {}
    }
    return out;
  }

  ContentRecordsCompanion _companion(RecordRow row) => ContentRecordsCompanion(
    k: Value(row.k),
    kid: Value(row.kid),
    v: Value(
      row.sealed ?? (row.text != null ? _utf8Bytes(row.text!) : null),
    ),
    vi: Value(row.intValue),
  );

  static Uint8List _utf8Bytes(String s) => Uint8List.fromList(utf8.encode(s));

  @override
  Future<bool> put(RecordRow row) async {
    try {
      await _db
          .into(_db.contentRecords)
          .insertOnConflictUpdate(_companion(row));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> delete(String k) async {
    try {
      await (_db.delete(_db.contentRecords)..where((t) => t.k.equals(k))).go();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<RecordRow>> rowsByKid(String kid, int limit) async {
    try {
      final rows =
          await (_db.select(_db.contentRecords)
                ..where((t) => t.kid.equals(kid))
                ..orderBy([(t) => OrderingTerm.asc(t.k)])
                ..limit(limit))
              .get();
      return rows
          .map((r) => RecordRow(k: r.k, kid: r.kid, sealed: r.v, intValue: r.vi))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<bool> putMany(List<RecordRow> rows) async {
    try {
      await _db.transaction(() async {
        for (final row in rows) {
          await _db
              .into(_db.contentRecords)
              .insertOnConflictUpdate(_companion(row));
        }
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> getMeta(String k) async {
    try {
      final row = await (_db.select(
        _db.contentMetaRows,
      )..where((t) => t.k.equals(k))).getSingleOrNull();
      return row?.v;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> setMeta(String k, String v) async {
    try {
      await _db
          .into(_db.contentMetaRows)
          .insertOnConflictUpdate(
            ContentMetaRowsCompanion(k: Value(k), v: Value(v)),
          );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> removeMeta(String k) async {
    try {
      await (_db.delete(_db.contentMetaRows)..where((t) => t.k.equals(k))).go();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> vacuumHint() async {
    try {
      await _db.customStatement('PRAGMA wal_checkpoint(TRUNCATE);');
    } catch (_) {}
  }

  @override
  Future<void> close() => _db.close();
}
