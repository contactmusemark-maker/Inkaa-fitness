const CACHE = 'transform-v3';
const ASSETS = ['./index.html', './manifest.json'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(ASSETS)));
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(keys =>
    Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
  ));
  self.clients.claim();
});

self.addEventListener('fetch', e => {
  e.respondWith(
    caches.match(e.request).then(cached => cached || fetch(e.request).catch(() => caches.match('./index.html')))
  );
});

// When user taps the alarm notification — open app and signal dismiss
self.addEventListener('notificationclick', e => {
  e.notification.close();
  const action = e.action;
  e.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(list => {
      // If app is already open, focus it and send dismiss message
      for (const client of list) {
        if (client.url.includes('index.html') || client.url.endsWith('/')) {
          client.focus();
          client.postMessage({ type: 'ALARM_DISMISS' });
          return;
        }
      }
      // Otherwise open app
      return clients.openWindow('./index.html');
    })
  );
});

// Listen for alarm schedule messages from the page
self.addEventListener('message', e => {
  if (e.data && e.data.type === 'SET_ALARM') {
    // Could set up background sync here in future
    console.log('[SW] Alarm schedule received:', e.data);
  }
});
