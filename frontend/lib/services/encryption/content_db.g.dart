// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'content_db.dart';

// ignore_for_file: type=lint
class $ContentRecordsTable extends ContentRecords
    with TableInfo<$ContentRecordsTable, ContentRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ContentRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _kMeta = const VerificationMeta('k');
  @override
  late final GeneratedColumn<String> k = GeneratedColumn<String>(
    'k',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kidMeta = const VerificationMeta('kid');
  @override
  late final GeneratedColumn<String> kid = GeneratedColumn<String>(
    'kid',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _vMeta = const VerificationMeta('v');
  @override
  late final GeneratedColumn<Uint8List> v = GeneratedColumn<Uint8List>(
    'v',
    aliasedName,
    true,
    type: DriftSqlType.blob,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _viMeta = const VerificationMeta('vi');
  @override
  late final GeneratedColumn<int> vi = GeneratedColumn<int>(
    'vi',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [k, kid, v, vi];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'content_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<ContentRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('k')) {
      context.handle(_kMeta, k.isAcceptableOrUnknown(data['k']!, _kMeta));
    } else if (isInserting) {
      context.missing(_kMeta);
    }
    if (data.containsKey('kid')) {
      context.handle(
        _kidMeta,
        kid.isAcceptableOrUnknown(data['kid']!, _kidMeta),
      );
    }
    if (data.containsKey('v')) {
      context.handle(_vMeta, v.isAcceptableOrUnknown(data['v']!, _vMeta));
    }
    if (data.containsKey('vi')) {
      context.handle(_viMeta, vi.isAcceptableOrUnknown(data['vi']!, _viMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {k};
  @override
  ContentRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ContentRecord(
      k: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}k'],
      )!,
      kid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kid'],
      ),
      v: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}v'],
      ),
      vi: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}vi'],
      ),
    );
  }

  @override
  $ContentRecordsTable createAlias(String alias) {
    return $ContentRecordsTable(attachedDatabase, alias);
  }
}

class ContentRecord extends DataClass implements Insertable<ContentRecord> {
  final String k;

  /// Content key id when [v] is sealed; null when [v]/[vi] is cleartext.
  /// Cleartext on purpose: key-loss detection and rotation select on it.
  final String? kid;

  /// Sealed: `12-byte IV || AES-256-GCM ciphertext+tag`. Cleartext: UTF-8.
  final Uint8List? v;
  final int? vi;
  const ContentRecord({required this.k, this.kid, this.v, this.vi});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['k'] = Variable<String>(k);
    if (!nullToAbsent || kid != null) {
      map['kid'] = Variable<String>(kid);
    }
    if (!nullToAbsent || v != null) {
      map['v'] = Variable<Uint8List>(v);
    }
    if (!nullToAbsent || vi != null) {
      map['vi'] = Variable<int>(vi);
    }
    return map;
  }

  ContentRecordsCompanion toCompanion(bool nullToAbsent) {
    return ContentRecordsCompanion(
      k: Value(k),
      kid: kid == null && nullToAbsent ? const Value.absent() : Value(kid),
      v: v == null && nullToAbsent ? const Value.absent() : Value(v),
      vi: vi == null && nullToAbsent ? const Value.absent() : Value(vi),
    );
  }

  factory ContentRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ContentRecord(
      k: serializer.fromJson<String>(json['k']),
      kid: serializer.fromJson<String?>(json['kid']),
      v: serializer.fromJson<Uint8List?>(json['v']),
      vi: serializer.fromJson<int?>(json['vi']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'k': serializer.toJson<String>(k),
      'kid': serializer.toJson<String?>(kid),
      'v': serializer.toJson<Uint8List?>(v),
      'vi': serializer.toJson<int?>(vi),
    };
  }

  ContentRecord copyWith({
    String? k,
    Value<String?> kid = const Value.absent(),
    Value<Uint8List?> v = const Value.absent(),
    Value<int?> vi = const Value.absent(),
  }) => ContentRecord(
    k: k ?? this.k,
    kid: kid.present ? kid.value : this.kid,
    v: v.present ? v.value : this.v,
    vi: vi.present ? vi.value : this.vi,
  );
  ContentRecord copyWithCompanion(ContentRecordsCompanion data) {
    return ContentRecord(
      k: data.k.present ? data.k.value : this.k,
      kid: data.kid.present ? data.kid.value : this.kid,
      v: data.v.present ? data.v.value : this.v,
      vi: data.vi.present ? data.vi.value : this.vi,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ContentRecord(')
          ..write('k: $k, ')
          ..write('kid: $kid, ')
          ..write('v: $v, ')
          ..write('vi: $vi')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(k, kid, $driftBlobEquality.hash(v), vi);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ContentRecord &&
          other.k == this.k &&
          other.kid == this.kid &&
          $driftBlobEquality.equals(other.v, this.v) &&
          other.vi == this.vi);
}

class ContentRecordsCompanion extends UpdateCompanion<ContentRecord> {
  final Value<String> k;
  final Value<String?> kid;
  final Value<Uint8List?> v;
  final Value<int?> vi;
  final Value<int> rowid;
  const ContentRecordsCompanion({
    this.k = const Value.absent(),
    this.kid = const Value.absent(),
    this.v = const Value.absent(),
    this.vi = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ContentRecordsCompanion.insert({
    required String k,
    this.kid = const Value.absent(),
    this.v = const Value.absent(),
    this.vi = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : k = Value(k);
  static Insertable<ContentRecord> custom({
    Expression<String>? k,
    Expression<String>? kid,
    Expression<Uint8List>? v,
    Expression<int>? vi,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (k != null) 'k': k,
      if (kid != null) 'kid': kid,
      if (v != null) 'v': v,
      if (vi != null) 'vi': vi,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ContentRecordsCompanion copyWith({
    Value<String>? k,
    Value<String?>? kid,
    Value<Uint8List?>? v,
    Value<int?>? vi,
    Value<int>? rowid,
  }) {
    return ContentRecordsCompanion(
      k: k ?? this.k,
      kid: kid ?? this.kid,
      v: v ?? this.v,
      vi: vi ?? this.vi,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (k.present) {
      map['k'] = Variable<String>(k.value);
    }
    if (kid.present) {
      map['kid'] = Variable<String>(kid.value);
    }
    if (v.present) {
      map['v'] = Variable<Uint8List>(v.value);
    }
    if (vi.present) {
      map['vi'] = Variable<int>(vi.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ContentRecordsCompanion(')
          ..write('k: $k, ')
          ..write('kid: $kid, ')
          ..write('v: $v, ')
          ..write('vi: $vi, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ContentMetaRowsTable extends ContentMetaRows
    with TableInfo<$ContentMetaRowsTable, ContentMetaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ContentMetaRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _kMeta = const VerificationMeta('k');
  @override
  late final GeneratedColumn<String> k = GeneratedColumn<String>(
    'k',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _vMeta = const VerificationMeta('v');
  @override
  late final GeneratedColumn<String> v = GeneratedColumn<String>(
    'v',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [k, v];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'content_meta_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<ContentMetaRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('k')) {
      context.handle(_kMeta, k.isAcceptableOrUnknown(data['k']!, _kMeta));
    } else if (isInserting) {
      context.missing(_kMeta);
    }
    if (data.containsKey('v')) {
      context.handle(_vMeta, v.isAcceptableOrUnknown(data['v']!, _vMeta));
    } else if (isInserting) {
      context.missing(_vMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {k};
  @override
  ContentMetaRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ContentMetaRow(
      k: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}k'],
      )!,
      v: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}v'],
      )!,
    );
  }

  @override
  $ContentMetaRowsTable createAlias(String alias) {
    return $ContentMetaRowsTable(attachedDatabase, alias);
  }
}

class ContentMetaRow extends DataClass implements Insertable<ContentMetaRow> {
  final String k;
  final String v;
  const ContentMetaRow({required this.k, required this.v});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['k'] = Variable<String>(k);
    map['v'] = Variable<String>(v);
    return map;
  }

  ContentMetaRowsCompanion toCompanion(bool nullToAbsent) {
    return ContentMetaRowsCompanion(k: Value(k), v: Value(v));
  }

  factory ContentMetaRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ContentMetaRow(
      k: serializer.fromJson<String>(json['k']),
      v: serializer.fromJson<String>(json['v']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'k': serializer.toJson<String>(k),
      'v': serializer.toJson<String>(v),
    };
  }

  ContentMetaRow copyWith({String? k, String? v}) =>
      ContentMetaRow(k: k ?? this.k, v: v ?? this.v);
  ContentMetaRow copyWithCompanion(ContentMetaRowsCompanion data) {
    return ContentMetaRow(
      k: data.k.present ? data.k.value : this.k,
      v: data.v.present ? data.v.value : this.v,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ContentMetaRow(')
          ..write('k: $k, ')
          ..write('v: $v')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(k, v);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ContentMetaRow && other.k == this.k && other.v == this.v);
}

class ContentMetaRowsCompanion extends UpdateCompanion<ContentMetaRow> {
  final Value<String> k;
  final Value<String> v;
  final Value<int> rowid;
  const ContentMetaRowsCompanion({
    this.k = const Value.absent(),
    this.v = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ContentMetaRowsCompanion.insert({
    required String k,
    required String v,
    this.rowid = const Value.absent(),
  }) : k = Value(k),
       v = Value(v);
  static Insertable<ContentMetaRow> custom({
    Expression<String>? k,
    Expression<String>? v,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (k != null) 'k': k,
      if (v != null) 'v': v,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ContentMetaRowsCompanion copyWith({
    Value<String>? k,
    Value<String>? v,
    Value<int>? rowid,
  }) {
    return ContentMetaRowsCompanion(
      k: k ?? this.k,
      v: v ?? this.v,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (k.present) {
      map['k'] = Variable<String>(k.value);
    }
    if (v.present) {
      map['v'] = Variable<String>(v.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ContentMetaRowsCompanion(')
          ..write('k: $k, ')
          ..write('v: $v, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$ContentDb extends GeneratedDatabase {
  _$ContentDb(QueryExecutor e) : super(e);
  $ContentDbManager get managers => $ContentDbManager(this);
  late final $ContentRecordsTable contentRecords = $ContentRecordsTable(this);
  late final $ContentMetaRowsTable contentMetaRows = $ContentMetaRowsTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    contentRecords,
    contentMetaRows,
  ];
}

typedef $$ContentRecordsTableCreateCompanionBuilder =
    ContentRecordsCompanion Function({
      required String k,
      Value<String?> kid,
      Value<Uint8List?> v,
      Value<int?> vi,
      Value<int> rowid,
    });
typedef $$ContentRecordsTableUpdateCompanionBuilder =
    ContentRecordsCompanion Function({
      Value<String> k,
      Value<String?> kid,
      Value<Uint8List?> v,
      Value<int?> vi,
      Value<int> rowid,
    });

class $$ContentRecordsTableFilterComposer
    extends Composer<_$ContentDb, $ContentRecordsTable> {
  $$ContentRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get k => $composableBuilder(
    column: $table.k,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kid => $composableBuilder(
    column: $table.kid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get v => $composableBuilder(
    column: $table.v,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get vi => $composableBuilder(
    column: $table.vi,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ContentRecordsTableOrderingComposer
    extends Composer<_$ContentDb, $ContentRecordsTable> {
  $$ContentRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get k => $composableBuilder(
    column: $table.k,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kid => $composableBuilder(
    column: $table.kid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get v => $composableBuilder(
    column: $table.v,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get vi => $composableBuilder(
    column: $table.vi,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ContentRecordsTableAnnotationComposer
    extends Composer<_$ContentDb, $ContentRecordsTable> {
  $$ContentRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get k =>
      $composableBuilder(column: $table.k, builder: (column) => column);

  GeneratedColumn<String> get kid =>
      $composableBuilder(column: $table.kid, builder: (column) => column);

  GeneratedColumn<Uint8List> get v =>
      $composableBuilder(column: $table.v, builder: (column) => column);

  GeneratedColumn<int> get vi =>
      $composableBuilder(column: $table.vi, builder: (column) => column);
}

class $$ContentRecordsTableTableManager
    extends
        RootTableManager<
          _$ContentDb,
          $ContentRecordsTable,
          ContentRecord,
          $$ContentRecordsTableFilterComposer,
          $$ContentRecordsTableOrderingComposer,
          $$ContentRecordsTableAnnotationComposer,
          $$ContentRecordsTableCreateCompanionBuilder,
          $$ContentRecordsTableUpdateCompanionBuilder,
          (
            ContentRecord,
            BaseReferences<_$ContentDb, $ContentRecordsTable, ContentRecord>,
          ),
          ContentRecord,
          PrefetchHooks Function()
        > {
  $$ContentRecordsTableTableManager(_$ContentDb db, $ContentRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ContentRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ContentRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ContentRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> k = const Value.absent(),
                Value<String?> kid = const Value.absent(),
                Value<Uint8List?> v = const Value.absent(),
                Value<int?> vi = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ContentRecordsCompanion(
                k: k,
                kid: kid,
                v: v,
                vi: vi,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String k,
                Value<String?> kid = const Value.absent(),
                Value<Uint8List?> v = const Value.absent(),
                Value<int?> vi = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ContentRecordsCompanion.insert(
                k: k,
                kid: kid,
                v: v,
                vi: vi,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ContentRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$ContentDb,
      $ContentRecordsTable,
      ContentRecord,
      $$ContentRecordsTableFilterComposer,
      $$ContentRecordsTableOrderingComposer,
      $$ContentRecordsTableAnnotationComposer,
      $$ContentRecordsTableCreateCompanionBuilder,
      $$ContentRecordsTableUpdateCompanionBuilder,
      (
        ContentRecord,
        BaseReferences<_$ContentDb, $ContentRecordsTable, ContentRecord>,
      ),
      ContentRecord,
      PrefetchHooks Function()
    >;
typedef $$ContentMetaRowsTableCreateCompanionBuilder =
    ContentMetaRowsCompanion Function({
      required String k,
      required String v,
      Value<int> rowid,
    });
typedef $$ContentMetaRowsTableUpdateCompanionBuilder =
    ContentMetaRowsCompanion Function({
      Value<String> k,
      Value<String> v,
      Value<int> rowid,
    });

class $$ContentMetaRowsTableFilterComposer
    extends Composer<_$ContentDb, $ContentMetaRowsTable> {
  $$ContentMetaRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get k => $composableBuilder(
    column: $table.k,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get v => $composableBuilder(
    column: $table.v,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ContentMetaRowsTableOrderingComposer
    extends Composer<_$ContentDb, $ContentMetaRowsTable> {
  $$ContentMetaRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get k => $composableBuilder(
    column: $table.k,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get v => $composableBuilder(
    column: $table.v,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ContentMetaRowsTableAnnotationComposer
    extends Composer<_$ContentDb, $ContentMetaRowsTable> {
  $$ContentMetaRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get k =>
      $composableBuilder(column: $table.k, builder: (column) => column);

  GeneratedColumn<String> get v =>
      $composableBuilder(column: $table.v, builder: (column) => column);
}

class $$ContentMetaRowsTableTableManager
    extends
        RootTableManager<
          _$ContentDb,
          $ContentMetaRowsTable,
          ContentMetaRow,
          $$ContentMetaRowsTableFilterComposer,
          $$ContentMetaRowsTableOrderingComposer,
          $$ContentMetaRowsTableAnnotationComposer,
          $$ContentMetaRowsTableCreateCompanionBuilder,
          $$ContentMetaRowsTableUpdateCompanionBuilder,
          (
            ContentMetaRow,
            BaseReferences<_$ContentDb, $ContentMetaRowsTable, ContentMetaRow>,
          ),
          ContentMetaRow,
          PrefetchHooks Function()
        > {
  $$ContentMetaRowsTableTableManager(
    _$ContentDb db,
    $ContentMetaRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ContentMetaRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ContentMetaRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ContentMetaRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> k = const Value.absent(),
                Value<String> v = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ContentMetaRowsCompanion(k: k, v: v, rowid: rowid),
          createCompanionCallback:
              ({
                required String k,
                required String v,
                Value<int> rowid = const Value.absent(),
              }) => ContentMetaRowsCompanion.insert(k: k, v: v, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ContentMetaRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$ContentDb,
      $ContentMetaRowsTable,
      ContentMetaRow,
      $$ContentMetaRowsTableFilterComposer,
      $$ContentMetaRowsTableOrderingComposer,
      $$ContentMetaRowsTableAnnotationComposer,
      $$ContentMetaRowsTableCreateCompanionBuilder,
      $$ContentMetaRowsTableUpdateCompanionBuilder,
      (
        ContentMetaRow,
        BaseReferences<_$ContentDb, $ContentMetaRowsTable, ContentMetaRow>,
      ),
      ContentMetaRow,
      PrefetchHooks Function()
    >;

class $ContentDbManager {
  final _$ContentDb _db;
  $ContentDbManager(this._db);
  $$ContentRecordsTableTableManager get contentRecords =>
      $$ContentRecordsTableTableManager(_db, _db.contentRecords);
  $$ContentMetaRowsTableTableManager get contentMetaRows =>
      $$ContentMetaRowsTableTableManager(_db, _db.contentMetaRows);
}
