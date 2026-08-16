// Keyed on dart.library.js_interop, NOT dart.library.html — same wasm trap as
// storage_persist.dart: under `flutter build web --wasm` the latter is false
// and the eviction forensics would silently vanish.
import 'boot_marker_logic.dart';
import 'boot_markers_stub.dart'
    if (dart.library.js_interop) 'boot_markers_web.dart' as impl;

export 'boot_marker_logic.dart'
    show BootMarkerState, BootMarkerTriple, BootMarkerStore, BootMarkerStores;

/// Reads then (re)plants a marker in localStorage, IndexedDB and CacheStorage
/// — three independently-durable stores that all live INSIDE the origin's
/// storage bucket. The read triple is the forensic payload:
///
///   - all three ABSENT on a container that ran before ⇒ whole-bucket
///     eviction (browser/OS took the origin's data);
///   - IndexedDB or CacheStorage PRESENT while localStorage is empty ⇒ the
///     loss is localStorage-only ⇒ ours to explain;
///   - ERROR arms are inconclusive and must never be read as absence.
///
/// First boot ever legitimately reads all-absent; the caller records the
/// triple durably and interpretation happens at dump-reading time.
Future<BootMarkerTriple> readAndPlantBootMarkers() =>
    impl.readAndPlantBootMarkers();
