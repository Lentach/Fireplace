/**
 * Push SW for Fireplace — scope `/web-push-scope/`.
 * Companion: frontend/lib/services/web_push_bridge_web.dart
 *
 * APP_BADGE_MAX must match kAppBadgeMaxDisplayCount in frontend/lib/utils/app_badge_math.dart
 */
const APP_BADGE_MAX = 19;

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

// Close any shown notification whose conversationId is NOT in unreadConvIds.
// Called after showNotification so the new notification is already in the list.
function sweepStaleNotifications(unreadConvIds) {
  var idSet = new Set(unreadConvIds.map(Number));
  return self.registration.getNotifications().then(function (notifications) {
    for (var i = 0; i < notifications.length; i++) {
      var n = notifications[i];
      var tag = n.tag || '';
      if (tag.indexOf('conversation-') !== 0) continue;
      var convId = Number(tag.slice('conversation-'.length));
      if (!isNaN(convId) && !idSet.has(convId)) {
        n.close();
      }
    }
    return Promise.resolve();
  }).catch(function () {});
}

// ---------- Push handler ----------

self.addEventListener('push', function (event) {
  var payload = {};
  try { payload = event.data ? event.data.json() : {}; } catch (_) {}

  var convId = payload.conversationId != null ? Number(payload.conversationId) : null;
  var unreadCount = typeof payload.unreadCount === 'number'
    ? payload.unreadCount
    : (typeof payload.messageCount === 'number' ? payload.messageCount : 1);
  var unreadTotal = typeof payload.unreadTotal === 'number'
    ? payload.unreadTotal
    : unreadCount;
  var unreadConvIds = Array.isArray(payload.unreadConversationIds)
    ? payload.unreadConversationIds
    : (convId != null ? [convId] : []);

  var body = unreadCount > 1
    ? 'You have ' + unreadCount + ' new messages'
    : 'You have a new message';

  var notificationOptions = {
    body: body,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: convId != null ? 'conversation-' + convId : 'new-message',
    data: payload,
    renotify: false,
  };

  event.waitUntil(
    self.registration
      .showNotification('Fireplace', notificationOptions)
      .then(function () { return sweepStaleNotifications(unreadConvIds); })
      .then(function () { return setBadgeFromSW(unreadTotal); })
  );
});

// ---------- Notification click — deep link ----------

self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  var data = (event.notification.data) || {};
  var convId = data.conversationId != null ? Number(data.conversationId) : null;

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (all) {
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
        best.postMessage({ type: 'push-notification-click', conversationId: convId });
        return best.focus();
      }
      // Cold start / killed PWA — encode conversationId in URL param
      var url = convId != null ? '/?notify_conv=' + convId : '/';
      return clients.openWindow(url);
    })
  );
});

// ---------- Message handler — badge updates from app ----------

self.addEventListener('message', function (event) {
  if (!event.data) return;
  if (event.data.type === 'clear-badge') {
    setBadgeFromSW(0);
  } else if (event.data.type === 'set-badge') {
    var n = typeof event.data.count === 'number' ? event.data.count : 0;
    setBadgeFromSW(n);
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
