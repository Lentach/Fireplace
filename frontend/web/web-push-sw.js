/**
 * Push handler companion for `frontend/lib/services/web_push_bridge_web.dart` (scope `/web-push-scope/`).
 *
 * - **`APP_BADGE_MAX`** must match Dart `kAppBadgeMaxDisplayCount` in `frontend/lib/utils/app_badge_math.dart`.
 * - **`postMessage`** payloads below are best-effort hooks; Flutter does not listen yet — notification tap
 *   still relies on focusing / opening the client window.
 *
 * WebKit / iOS PWA often ignores `setAppBadge()` when called with no arguments; use a positive integer.
 */
const APP_BADGE_MAX = 19;

function trySetAppBadgeFromServiceWorker(payload) {
  try {
    const nav = self.navigator;
    if (nav && typeof nav.setAppBadge === 'function') {
      let n = 1;
      if (typeof payload.messageCount === 'number' && payload.messageCount > 0) {
        n =
          payload.messageCount > APP_BADGE_MAX ? APP_BADGE_MAX : payload.messageCount;
      }
      const result = nav.setAppBadge(n);
      return result && typeof result.then === 'function'
        ? result.catch(function () {})
        : Promise.resolve();
    }
  } catch (_) {}
  return Promise.resolve();
}

self.addEventListener('push', (event) => {
  let payload = {};
  try {
    payload = event.data ? event.data.json() : {};
  } catch (_) {
    payload = {};
  }

  const title = 'Fireplace';
  const count =
    typeof payload.messageCount === 'number' && payload.messageCount > 1
      ? payload.messageCount
      : null;
  const body =
    count != null ? `You have ${count} new messages` : 'You have a new message';
  const notificationOptions = {
    body,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: payload.conversationId
      ? `conversation-${payload.conversationId}`
      : 'new-message',
    data: payload,
    renotify: false,
  };

  // Safari/iOS requires user-visible notifications for push events — complete that first,
  // then best-effort badge. Parallel Promise.all caused flaky failures if either branch rejected.
  event.waitUntil(
    self.registration
      .showNotification(title, notificationOptions)
      .then(() => trySetAppBadgeFromServiceWorker(payload)),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const data = event.notification.data || {};
  const targetUrl = '/';

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ('focus' in client) {
          // Optional hook for a future web `message` listener (deep-link); not consumed by Dart today.
          client.postMessage({
            type: 'push-notification-click',
            conversationId: data.conversationId ?? null,
          });
          return client.focus();
        }
      }
      return clients.openWindow(targetUrl);
    }),
  );
});

self.addEventListener('pushsubscriptionchange', (event) => {
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        // Optional hook for client-side resync; Flutter does not listen yet.
        client.postMessage({ type: 'push-subscription-change' });
      }
    }),
  );
});
