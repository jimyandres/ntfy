// Shell cacheado para que la app abra aunque el túnel esté apagado.
// Los avisos no dependen del túnel: llegan desde Apple directamente al service worker.
const CACHE = 'avisos-v2';
const SHELL = ['/', '/index.html', '/app.js', '/manifest.json', '/icon-192.png', '/icon-512.png'];

self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)));
  self.skipWaiting();
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== self.location.origin || url.pathname.startsWith('/api/')) return;
  // Red primero (para recibir cambios); si falla o el túnel responde con error, usa la copia.
  event.respondWith(
    fetch(event.request)
      .then(res => {
        if (!res.ok) throw new Error('HTTP ' + res.status);
        const copy = res.clone();
        caches.open(CACHE).then(c => c.put(event.request, copy));
        return res;
      })
      .catch(() => caches.match(event.request).then(r => r || caches.match('/')))
  );
});

self.addEventListener('push', event => {
  let data = { title: 'Aviso', body: '' };
  try {
    if (event.data) data = event.data.json();
  } catch (_) {
    data = { title: 'Aviso', body: event.data ? event.data.text() : '' };
  }
  const options = { body: data.body || '', icon: '/icon-192.png' };
  if (data.tag) options.tag = data.tag;
  // iOS exige mostrar siempre una notificación por cada push.
  event.waitUntil(self.registration.showNotification(data.title || 'Aviso', options));
});

self.addEventListener('notificationclick', event => {
  event.notification.close();
  event.waitUntil(clients.openWindow('/'));
});
