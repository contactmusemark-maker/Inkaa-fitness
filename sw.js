const CACHE = 'ifitness-v1';
const ASSETS = [
  './index.html',
  './manifest.json',
  './inkaa_fitness_icon_white_.png'
];

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

self.addEventListener('notificationclick', e => {
  e.notification.close();
  e.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(list => {
      for (const client of list) {
        if (client.url.includes('index.html') || client.url.endsWith('/')) {
          client.focus();
          client.postMessage({ type: 'ALARM_DISMISS' });
          return;
        }
      }
      return clients.openWindow('./index.html');
    })
  );
});

self.addEventListener('message', e => {
  if (e.data && e.data.type === 'SET_ALARM') {
    console.log('[SW] Alarm schedule received:', e.data);
  }
});
