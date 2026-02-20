// Firebase background message handler for web push notifications.
// This service worker is automatically registered by the firebase_messaging plugin.
// It MUST be served from the root path (/) — placing it in /web/ satisfies this.
//
// TODO: Replace the firebaseConfig values below with your real values from:
// Firebase Console → Project Settings → Your web app → SDK setup and configuration

importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'REMOVED',
  authDomain: 'fireplace-android.firebaseapp.com',
  projectId: 'fireplace-android',
  storageBucket: 'fireplace-android.firebasestorage.app',
  messagingSenderId: '650276507312',
  appId: '1:650276507312:web:a3d4c73e91ac8d7b79b575',
});

const messaging = firebase.messaging();

// Background push handler — wakes the browser when a push arrives while closed.
// Privacy: payload only contains { type: 'new_message' } — no message content.
messaging.onBackgroundMessage((payload) => {
  self.registration.showNotification('MVP Chat', {
    body: 'You have a new message',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: 'new-message', // Replaces previous notification instead of stacking
    data: payload.data,
  });
});
