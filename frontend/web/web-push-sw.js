/**
 * Best-effort generic app-icon badge (Badging API, no numeric count).
 * Supported in Chromium PWAs; iOS WebKit may expose this only in some contexts —
 * failures are ignored so push + tray notification always proceed.
 */
function trySetAppBadgeIndicatorFromServiceWorker() {
  try {
    const nav = self.navigator;
    if (nav && typeof nav.setAppBadge === 'function') {
      const result = nav.setAppBadge();
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

  // Safari/iOS requires user-visible notifications for push events.
  // Run badge update in parallel so the icon can show a dot before the app opens (where supported).
  event.waitUntil(
    Promise.all([
      self.registration.showNotification(title, notificationOptions),
      trySetAppBadgeIndicatorFromServiceWorker(),
    ]),
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
        client.postMessage({ type: 'push-subscription-change' });
      }
    }),
  );
});
