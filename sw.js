const CACHE_NAME = 'neto-apertura-v2';
const ASSETS = [
  './',
  './index.html',
  './manifest.json',
  './dist/styles.css',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/icon-maskable-512.png',
  './icons/apple-touch-icon.png',
  './icons/favicon.ico',
  './icons/favicon-32x32.png',
  './icons/favicon-16x16.png',
  './icons/logo-neto-clean.png',
  './icons/logo-neto-white.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(ASSETS))
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.map((k) => k !== CACHE_NAME && caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  // Let Supabase API requests pass directly to network
  if (event.request.url.includes('/rest/v1/')) {
    return;
  }
  event.respondWith(
    caches.match(event.request).then((cached) => cached || fetch(event.request).catch(() => cached))
  );
});
