import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Pending notification deep-link handoff (page side).
///
/// The push SW writes `{ conversationId, at }` to IndexedDB in its
/// `notificationclick` handler (see web-push-sw.js). It must, because on a
/// killed iOS PWA `clients.openWindow('/?notify_conv=…')` opens the app at the
/// manifest start_url and DROPS the URL — and on a suspended iOS WebView the
/// click postMessage can be lost. IndexedDB is the only storage shared between
/// the SW and this page. Constants must match the SW's `DEEPLINK_*`.
const String _dbName = 'fireplace-push';
const String _storeName = 'kv';
const String _key = 'pending-deep-link';

/// Records older than this are discarded — a deep-link should only fire on the
/// launch/resume that immediately follows the tap, not days later.
const Duration kPendingDeepLinkMaxAge = Duration(minutes: 5);

/// Reads **and deletes** the pending deep-link. Returns the conversationId
/// when a fresh record exists, otherwise null (stale records are still
/// deleted so they can never fire on a later launch).
Future<int?> consumePendingNotificationDeepLink() async {
  final db = await _openDb();
  if (db == null) return null;
  try {
    final record = await _requestResult(
      db.transaction(_storeName.toJS, 'readonly').objectStore(_storeName).get(_key.toJS),
    );
    if (record.isUndefinedOrNull) return null;

    await _requestResult(
      db.transaction(_storeName.toJS, 'readwrite').objectStore(_storeName).delete(_key.toJS),
    );

    final map = record.dartify();
    if (map is! Map) return null;
    final rawId = map['conversationId'];
    final rawAt = map['at'];
    if (rawId is! num || rawAt is! num) return null;
    final age = DateTime.now().millisecondsSinceEpoch - rawAt.toInt();
    if (age < 0 || age > kPendingDeepLinkMaxAge.inMilliseconds) return null;
    return rawId.toInt();
  } catch (_) {
    return null;
  } finally {
    db.close();
  }
}

/// Deletes any pending record. Called when the notification click was already
/// handled live via the SW postMessage path, so a leftover record cannot
/// re-trigger navigation on the next launch.
Future<void> clearPendingNotificationDeepLink() async {
  final db = await _openDb();
  if (db == null) return;
  try {
    await _requestResult(
      db.transaction(_storeName.toJS, 'readwrite').objectStore(_storeName).delete(_key.toJS),
    );
  } catch (_) {
  } finally {
    db.close();
  }
}

Future<web.IDBDatabase?> _openDb() {
  final completer = Completer<web.IDBDatabase?>();
  try {
    final request = web.window.indexedDB.open(_dbName, 1);
    request.onupgradeneeded = ((web.Event _) {
      try {
        final db = request.result as web.IDBDatabase;
        if (!db.objectStoreNames.contains(_storeName)) {
          db.createObjectStore(_storeName);
        }
      } catch (_) {}
    }).toJS;
    request.onsuccess = ((web.Event _) {
      completer.complete(request.result as web.IDBDatabase);
    }).toJS;
    request.onerror = ((web.Event _) {
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
