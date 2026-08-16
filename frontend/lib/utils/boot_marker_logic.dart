/// A marker store's state before its current boot writes are attempted.
enum BootMarkerState {
  present,
  absent,
  error,
  unsupported,
}

/// Read results from every independently durable browser store.
///
/// An [error] is deliberately distinct from [absent]: a failed read must never
/// be interpreted as proof that the marker is gone.
class BootMarkerTriple {
  const BootMarkerTriple({
    required this.localStorage,
    required this.indexedDb,
    required this.cacheStorage,
  });

  final BootMarkerState localStorage;
  final BootMarkerState indexedDb;
  final BootMarkerState cacheStorage;

  Map<String, String> toDiagnosticPayload() => {
    'ls': localStorage.name,
    'idb': indexedDb.name,
    'cache': cacheStorage.name,
  };
}

/// One browser-backed boot marker arm.
abstract interface class BootMarkerStore {
  /// Reports whether the pre-existing marker is present.
  ///
  /// Throw on a failed read; [readAndPlantBootMarkersWithStores] records that
  /// state as [BootMarkerState.error], never as absence.
  Future<bool> readMarker();

  /// Plants the current marker after every store's read has completed.
  Future<void> plantMarker();
}

/// The three independent storage arms used for eviction diagnosis.
class BootMarkerStores {
  const BootMarkerStores({
    required this.localStorage,
    required this.indexedDb,
    required this.cacheStorage,
  });

  final BootMarkerStore localStorage;
  final BootMarkerStore indexedDb;
  final BootMarkerStore cacheStorage;
}

/// Reads every existing marker before planting any replacement marker.
///
/// Each arm is isolated so a browser error in one storage mechanism cannot
/// conceal evidence retained by another one.
Future<BootMarkerTriple> readAndPlantBootMarkersWithStores(
  BootMarkerStores stores,
) async {
  final localStorage = await _readState(stores.localStorage);
  final indexedDb = await _readState(stores.indexedDb);
  final cacheStorage = await _readState(stores.cacheStorage);

  await _plantIgnoringFailure(stores.localStorage);
  await _plantIgnoringFailure(stores.indexedDb);
  await _plantIgnoringFailure(stores.cacheStorage);

  return BootMarkerTriple(
    localStorage: localStorage,
    indexedDb: indexedDb,
    cacheStorage: cacheStorage,
  );
}

Future<BootMarkerState> _readState(BootMarkerStore store) async {
  try {
    return await store.readMarker()
        ? BootMarkerState.present
        : BootMarkerState.absent;
  } catch (_) {
    return BootMarkerState.error;
  }
}

Future<void> _plantIgnoringFailure(BootMarkerStore store) async {
  try {
    await store.plantMarker();
  } catch (_) {
    // The next boot must still inspect every surviving arm.
  }
}
