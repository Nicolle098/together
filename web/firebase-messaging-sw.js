// Firebase Cloud Messaging Service Worker
// Required so the browser can register the FCM push scope without a MIME error.

importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-messaging-compat.js');

// Background message handler — fires when the app is not in the foreground.
self.addEventListener('push', function (event) {
  // Handled by firebase-messaging-compat above when firebase.messaging() is initialised.
});
