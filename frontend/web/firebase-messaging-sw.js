// Firebase background message handler for web push notifications.
// This service worker is automatically registered by the firebase_messaging plugin.
// It MUST be served from the root path (/) — placing it in /web/ satisfies this.
//
// Setup: copy firebase-config.js.example → firebase-config.js and fill in real values.
// firebase-config.js is gitignored and loaded at runtime via importScripts.

importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js');
importScripts('/firebase-config.js');

firebase.initializeApp(firebaseConfig);

const messaging = firebase.messaging();

// Background push handler — wakes the browser when a push arrives while closed.
// Privacy: payload only contains { type: 'new_message' } — no message content.
messaging.onBackgroundMessage((payload) => {
  self.registration.showNotification('Fireplace', {
    body: 'You have a new message',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: 'new-message', // Replaces previous notification instead of stacking
    data: payload.data,
  });
});
