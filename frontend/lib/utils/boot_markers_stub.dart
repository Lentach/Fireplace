import 'boot_marker_logic.dart';

/// Native/non-web: keys live in platform secure storage, not a browser
/// bucket, so eviction forensics do not apply.
Future<BootMarkerTriple> readAndPlantBootMarkers() async =>
    const BootMarkerTriple(
      localStorage: BootMarkerState.unsupported,
      indexedDb: BootMarkerState.unsupported,
      cacheStorage: BootMarkerState.unsupported,
    );
