import 'package:fireplace/utils/boot_marker_logic.dart';
import 'package:flutter_test/flutter_test.dart';

/// The boot-marker triple exists to diagnose storage loss AFTER the fact, so
/// its own failure modes must never destroy the evidence they report on:
/// every pre-existing marker is read before any arm plants a replacement, a
/// failed read is an ERROR (never absence), and a failed plant in one store
/// must not silence the others.
class _FakeStore implements BootMarkerStore {
  _FakeStore(
    this.name,
    this.log, {
    this.present = false,
    this.readThrows = false,
    this.plantThrows = false,
  });

  final String name;
  final List<String> log;
  final bool present;
  final bool readThrows;
  final bool plantThrows;

  @override
  Future<bool> readMarker() async {
    log.add('read:$name');
    if (readThrows) throw StateError('read failed: $name');
    return present;
  }

  @override
  Future<void> plantMarker() async {
    log.add('plant:$name');
    if (plantThrows) throw StateError('plant failed: $name');
  }
}

void main() {
  late List<String> log;

  BootMarkerStores stores({
    bool lsPresent = false,
    bool idbPresent = false,
    bool cachePresent = false,
    bool lsReadThrows = false,
    bool idbPlantThrows = false,
  }) => BootMarkerStores(
    localStorage: _FakeStore(
      'ls',
      log,
      present: lsPresent,
      readThrows: lsReadThrows,
    ),
    indexedDb: _FakeStore(
      'idb',
      log,
      present: idbPresent,
      plantThrows: idbPlantThrows,
    ),
    cacheStorage: _FakeStore('cache', log, present: cachePresent),
  );

  setUp(() => log = []);

  test('every read happens before any plant', () async {
    await readAndPlantBootMarkersWithStores(stores());

    final firstPlant = log.indexWhere((op) => op.startsWith('plant:'));
    final lastRead = log.lastIndexWhere((op) => op.startsWith('read:'));
    expect(
      lastRead < firstPlant,
      isTrue,
      reason: 'planting before reading would overwrite the evidence: '
          'a replanted marker reads as "survived" on this very boot',
    );
  });

  test('presence and absence are reported per arm', () async {
    final triple = await readAndPlantBootMarkersWithStores(
      stores(idbPresent: true, cachePresent: true),
    );

    expect(triple.localStorage, BootMarkerState.absent);
    expect(triple.indexedDb, BootMarkerState.present);
    expect(triple.cacheStorage, BootMarkerState.present);
    expect(triple.toDiagnosticPayload(), {
      'ls': 'absent',
      'idb': 'present',
      'cache': 'present',
    });
  });

  test('a failed read is ERROR, never absence', () async {
    final triple = await readAndPlantBootMarkersWithStores(
      stores(lsReadThrows: true, idbPresent: true),
    );

    expect(
      triple.localStorage,
      BootMarkerState.error,
      reason: 'error-as-absence would fabricate an eviction verdict',
    );
    expect(triple.indexedDb, BootMarkerState.present);
  });

  test('a failed plant does not affect the triple or the other arms',
      () async {
    final triple = await readAndPlantBootMarkersWithStores(
      stores(lsPresent: true, idbPlantThrows: true),
    );

    expect(triple.localStorage, BootMarkerState.present);
    expect(triple.indexedDb, BootMarkerState.absent);
    expect(
      log,
      contains('plant:cache'),
      reason: 'one failing store must not stop later arms from replanting',
    );
  });
}
