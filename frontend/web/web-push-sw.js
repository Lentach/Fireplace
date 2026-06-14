/**
 * Push SW for Fireplace — scope `/web-push-scope/`.
 * Companion: frontend/lib/services/web_push_bridge_web.dart
 *            frontend/lib/services/push_sw_channel_web.dart
 *            frontend/lib/utils/pending_deep_link_web.dart
 *
 * APP_BADGE_MAX must match kAppBadgeMaxDisplayCount in frontend/lib/utils/app_badge_math.dart
 * DEEPLINK_* constants must match frontend/lib/utils/pending_deep_link_web.dart
 *
 * This SW is the single writer for the app icon badge and the notification tray.
 * The page never touches them directly — it posts messages here (see the
 * 'message' handler), because iOS WebKit requires these to run in SW context
 * to survive WebView suspension and to avoid racing the push handler.
 */
const APP_BADGE_MAX = 19;

const DEEPLINK_DB = 'fireplace-push';
const DEEPLINK_STORE = 'kv';
const DEEPLINK_KEY = 'pending-deep-link';

// ---------- Badge helpers ----------

function setBadgeFromSW(n) {
  try {
    const nav = self.navigator;
    if (!nav || typeof nav.setAppBadge !== 'function') return Promise.resolve();
    if (n <= 0) {
      // iOS Safari requires integer overload (not no-arg) for clearAppBadge
      const result = typeof nav.clearAppBadge === 'function'
        ? nav.clearAppBadge()
        : nav.setAppBadge(0);
      return result && typeof result.then === 'function'
        ? result.catch(function () {})
        : Promise.resolve();
    }
    const clamped = n > APP_BADGE_MAX ? APP_BADGE_MAX : n;
    const result = nav.setAppBadge(clamped);
    return result && typeof result.then === 'function'
      ? result.catch(function () {})
      : Promise.resolve();
  } catch (_) {
    return Promise.resolve();
  }
}

// ---------- Notification helpers ----------

// Close every shown notification carrying exactly this tag. iOS WebKit never
// replaces same-tag notifications (WebKit bug 258922), so the push handler
// emulates tag replacement with close-then-show; on engines with working tag
// replacement this is a harmless no-op pass.
// Queries BOTH the spec'd filtered form and an unfiltered scan and closes the
// union — belt-and-suspenders against engines where one form is unreliable.
// Closing the same notification twice is a harmless no-op. Hard limit (iOS):
// neither form can return notifications shown by a PREVIOUS SW instance, so
// cards from older bursts stay until the user swipes them.
function closeNotificationsForTag(tag) {
  function getSafe(filter) {
    try {
      var p = filter
        ? self.registration.getNotifications(filter)
        : self.registration.getNotifications();
      return p.catch(function () { return []; });
    } catch (_) {
      return Promise.resolve([]);
    }
  }
  return Promise.all([getSafe({ tag: tag }), getSafe(null)])
    .then(function (results) {
      for (var r = 0; r < results.length; r++) {
        var list = results[r] || [];
        for (var i = 0; i < list.length; i++) {
          if (list[i].tag === tag) {
            try { list[i].close(); } catch (_) {}
          }
        }
      }
    })
    .catch(function () {});
}

// Close any shown notification whose conversationId is NOT in unreadConvIds.
function sweepStaleNotifications(unreadConvIds) {
  var idSet = new Set(unreadConvIds.map(Number));
  return self.registration.getNotifications().then(function (notifications) {
    for (var i = 0; i < notifications.length; i++) {
      var n = notifications[i];
      var tag = n.tag || '';
      if (tag.indexOf('conversation-') !== 0) continue;
      var convId = Number(tag.slice('conversation-'.length));
      if (!isNaN(convId) && !idSet.has(convId)) {
        try { n.close(); } catch (_) {}
      }
    }
  }).catch(function () {});
}

// ---------- Pending deep-link (IndexedDB) ----------
// On a killed iOS PWA, notificationclick's clients.openWindow(url) opens the
// app at its manifest start_url and DROPS the URL (incl. ?notify_conv=), so
// the conversation id is persisted here and the page drains it on launch /
// resume. IndexedDB is the only storage shared between this SW and the page.

function openDeepLinkDb() {
  return new Promise(function (resolve, reject) {
    var req = indexedDB.open(DEEPLINK_DB, 1);
    req.onupgradeneeded = function () {
      try { req.result.createObjectStore(DEEPLINK_STORE); } catch (_) {}
    };
    req.onsuccess = function () { resolve(req.result); };
    req.onerror = function () { reject(req.error); };
  });
}

function storePendingDeepLink(conversationId) {
  return openDeepLinkDb().then(function (db) {
    return new Promise(function (resolve) {
      try {
        var tx = db.transaction(DEEPLINK_STORE, 'readwrite');
        tx.objectStore(DEEPLINK_STORE).put(
          { conversationId: conversationId, at: Date.now() },
          DEEPLINK_KEY
        );
        tx.oncomplete = function () { db.close(); resolve(); };
        tx.onabort = function () { db.close(); resolve(); };
        tx.onerror = function () { db.close(); resolve(); };
      } catch (_) { db.close(); resolve(); }
    });
  }).catch(function () {});
}

// ---------- Push handler ----------

self.addEventListener('push', function (event) {
  var payload = {};
  try { payload = event.data ? event.data.json() : {}; } catch (_) {}

  var convId = payload.conversationId != null ? Number(payload.conversationId) : null;
  // Per-conversation unread — card text only.
  var unreadCount = typeof payload.unreadCount === 'number'
    ? payload.unreadCount
    : (typeof payload.messageCount === 'number' ? payload.messageCount : 1);
  // Badge MUST come from the live cumulative total. When the backend failed to
  // compute it at flush time the field is absent — then we leave the badge
  // untouched rather than writing a per-burst guess (the old fallback caused
  // visible resets to 1).
  var hasUnreadTotal = typeof payload.unreadTotal === 'number';
  // null = field absent (backend error at flush time) — skip sweep rather than
  // wrongly closing other conversations' notifications.
  var unreadConvIds = Array.isArray(payload.unreadConversationIds)
    ? payload.unreadConversationIds
    : null;

  // WhatsApp/Signal model: title = sender display name (metadata-only,
  // approved), body = per-conversation unread count → "Bob: 15 new messages".
  var senderName = typeof payload.senderName === 'string' && payload.senderName
    ? payload.senderName
    : null;
  var title = senderName || 'Fireplace';
  var body = unreadCount > 1
    ? unreadCount + ' new messages'
    : 'New message';

  var tag = convId != null ? 'conversation-' + convId : 'new-message';
  var notificationOptions = {
    body: body,
    // Large icon (notification body): full-colour Fireplace campfire mark.
    icon: '/icons/notification-icon-512.png',
    // Small/status-bar icon: MUST be monochrome white-on-transparent — Android
    // renders only its alpha channel. A full-colour image here is the classic
    // "white square" bug.
    badge: '/icons/notification-badge-96.png',
    tag: tag,
    data: payload,
    // Re-alert on tag replacement (Chrome/Android); ignored by Safari, where
    // close-then-show below produces a fresh alerting notification anyway.
    renotify: true,
  };

  event.waitUntil(
    closeNotificationsForTag(tag)
      .then(function () {
        return self.registration.showNotification(title, notificationOptions);
      })
      .then(function () {
        return unreadConvIds != null
          ? sweepStaleNotifications(unreadConvIds)
          : Promise.resolve();
      })
      .then(function () {
        return hasUnreadTotal
          ? setBadgeFromSW(payload.unreadTotal)
          : Promise.resolve();
      })
  );
});

// ---------- Notification click — deep link ----------

self.addEventListener('notificationclick', function (event) {
  var data = (event.notification.data) || {};
  var convId = data.conversationId != null ? Number(data.conversationId) : null;
  // iOS has been observed dropping notification.data — recover the id from the
  // tag, which survives reliably.
  if (convId == null || isNaN(convId)) {
    var tag = event.notification.tag || '';
    if (tag.indexOf('conversation-') === 0) {
      var parsed = Number(tag.slice('conversation-'.length));
      if (!isNaN(parsed)) convId = parsed;
    }
  }
  event.notification.close();

  event.waitUntil(
    (convId != null
      ? closeNotificationsForTag('conversation-' + convId) // clear the whole group
          .then(function () { return storePendingDeepLink(convId); })
      : Promise.resolve())
      .then(function () {
        return clients.matchAll({ type: 'window', includeUncontrolled: true });
      })
      .then(function (all) {
        var best = null;
        for (var i = 0; i < all.length; i++) {
          if (all[i].focused) { best = all[i]; break; }
        }
        if (!best) {
          for (var i = 0; i < all.length; i++) {
            if (all[i].visibilityState === 'visible') { best = all[i]; break; }
          }
        }
        if (!best && all.length > 0) { best = all[0]; }

        if (best) {
          // The pending deep-link stays stored as a fallback: if this client is
          // a suspended/stale iOS WebView the message is lost, and the page
          // drains IndexedDB on resume instead. The page deletes the record
          // when either path handles it.
          best.postMessage({ type: 'push-notification-click', conversationId: convId });
          return best.focus().catch(function () {});
        }
        // Cold start / killed PWA — URL param works on Android/desktop; iOS
        // ignores it (start_url) and relies on the IndexedDB record above.
        var url = convId != null ? '/?notify_conv=' + convId : '/';
        return clients.openWindow(url);
      })
  );
});

// ---------- Message handler — tray + badge ops requested by the app ----------

self.addEventListener('message', function (event) {
  var data = event.data;
  if (!data) return;
  var work = null;

  if (data.type === 'clear-badge') {
    work = setBadgeFromSW(0);
  } else if (data.type === 'set-badge') {
    work = setBadgeFromSW(typeof data.count === 'number' ? data.count : 0);
  } else if (data.type === 'close-conv') {
    var convId = Number(data.conversationId);
    work = isNaN(convId)
      ? Promise.resolve()
      : closeNotificationsForTag('conversation-' + convId);
    if (typeof data.unreadTotal === 'number') {
      var totalAfterClose = data.unreadTotal;
      work = work.then(function () { return setBadgeFromSW(totalAfterClose); });
    }
  } else if (data.type === 'sweep') {
    var ids = Array.isArray(data.unreadConversationIds)
      ? data.unreadConversationIds
      : [];
    work = sweepStaleNotifications(ids);
    if (typeof data.unreadTotal === 'number') {
      var totalAfterSweep = data.unreadTotal;
      work = work.then(function () { return setBadgeFromSW(totalAfterSweep); });
    }
  }

  if (work && event.waitUntil) {
    try { event.waitUntil(work); } catch (_) {}
  }
});

// ---------- Subscription change ----------

self.addEventListener('pushsubscriptionchange', function (event) {
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (clientList) {
      for (var i = 0; i < clientList.length; i++) {
        clientList[i].postMessage({ type: 'push-subscription-change' });
      }
    })
  );
});
