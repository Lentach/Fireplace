import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'boot_marker_logic.dart';

/// Web: one marker per independently-durable browser store, all inside this
/// origin's storage bucket. Read BEFORE plant, every arm isolated — see
/// `boot_marker_logic.dart` for the semantics and `readAndPlantBootMarkers`
/// for why the triple exists at all.
const String _lsKey = 'fp_boot_marker';
const String _idbDbName = 'fireplace-boot-marker';
const String _idbStoreName = 'kv';
const String _idbKey = 'marker';
const String _cacheName = 'fp-boot-marker';
const String _cacheEntry = '/fp-boot-marker';
const String _markerValue = '1';

Future<BootMarkerTriple> readAndPlantBootMarkers() =>
    readAndPlantBootMarkersWithStores(
      const BootMarkerStores(
        localStorage: _LocalStorageMarker(),
        indexedDb: _IndexedDbMarker(),
        cacheStorage: _CacheStorageMarker(),
      ),
    );

class _LocalStorageMarker implements BootMarkerStore {
  const _LocalStorageMarker();

  @override
  Future<bool> readMarker() async =>
      web.window.localStorage.getItem(_lsKey) != null;

  @override
  Future<void> plantMarker() async =>
      web.window.localStorage.setItem(_lsKey, _markerValue);
}

class _IndexedDbMarker implements BootMarkerStore {
  const _IndexedDbMarker();

  @override
  Future<bool> readMarker() async {
    final db = await _openDb();
    if (db == null) throw StateError('idb open failed');
    try {
      final tx = db.transaction(_idbStoreName.toJS, 'readonly');
      final request = tx.objectStore(_idbStoreName).get(_idbKey.toJS);
      final result = await _requestResult(request);
      return result != null;
    } finally {
      db.close();
    }
  }

  @override
  Future<void> plantMarker() async {
    final db = await _openDb();
    if (db == null) throw StateError('idb open failed');
    try {
      final tx = db.transaction(_idbStoreName.toJS, 'readwrite');
      final request = tx
          .objectStore(_idbStoreName)
          .put(_markerValue.toJS, _idbKey.toJS);
      await _requestResult(request);
    } finally {
      db.close();
    }
  }
}

class _CacheStorageMarker implements BootMarkerStore {
  const _CacheStorageMarker();

  @override
  Future<bool> readMarker() async {
    final cache = await web.window.caches.open(_cacheName).toDart;
    final match = await cache.match(_cacheEntry.toJS).toDart;
    return match != null;
  }

  @override
  Future<void> plantMarker() async {
    final cache = await web.window.caches.open(_cacheName).toDart;
    await cache.put(_cacheEntry.toJS, web.Response(_markerValue.toJS)).toDart;
  }
}

// IDB plumbing copied from pending_deep_link_web.dart — same event-callback
// bridge, but a throwing open is reported (null) so readMarker can surface it
// as an ERROR state instead of silently reading as absence.
Future<web.IDBDatabase?> _openDb() {
  final completer = Completer<web.IDBDatabase?>();
  try {
    final request = web.window.indexedDB.open(_idbDbName, 1);
    request.onupgradeneeded = ((web.Event _) {
      try {
        final db = request.result as web.IDBDatabase;
        if (!db.objectStoreNames.contains(_idbStoreName)) {
          db.createObjectStore(_idbStoreName);
        }
      } catch (_) {}
    }).toJS;
    request.onsuccess = ((web.Event _) {
      if (completer.isCompleted) return;
      completer.complete(request.result as web.IDBDatabase);
    }).toJS;
    request.onblocked = ((web.Event _) {
      // Another live context holds the DB open — do not wait forever; a null
      // db reads as ERROR upstream, never as absence. A late onsuccess after
      // the block clears is ignored via isCompleted.
      if (completer.isCompleted) return;
      completer.complete(null);
    }).toJS;
    request.onerror = ((web.Event _) {
      if (completer.isCompleted) return;
      completer.complete(null);
    }).toJS;
  } catch (_) {
    return Future.value(null);
  }
  return completer.future;
}

Future<JSAny?> _requestResult(web.IDBRequest request) {
  final completer = Completer<JSAny?>();
  request.onsuccess = ((web.Event _) {
    completer.complete(request.result);
  }).toJS;
  request.onerror = ((web.Event _) {
    completer.complete(null);
  }).toJS;
  return completer.future;
}
