const CACHE_NAME = 'neto-apertura-v9';
const ASSETS = [
  './',
  './index.html',
  './manifest.json',
  './dist/styles.css?v=9',
  './dist/qrcode.js',
  './favicon.ico',
  './icon.svg',
  './icons/logo-app.png',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/icon-maskable-512.png',
  './icons/apple-touch-icon.png',
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
  const req = event.request;
  if (req.method !== 'GET') return;

  // Let Supabase & Telegram API requests pass directly to network
  if (req.url.includes('/rest/v1/') || req.url.includes('t.me/')) {
    return;
  }

  const url = new URL(req.url);
  const isDocOrStyle =
    req.mode === 'navigate' ||
    url.pathname.endsWith('/') ||
    url.pathname.endsWith('.html') ||
    url.pathname.endsWith('.css');

  // Network-First for HTML & CSS so Tailwind utility classes never desync with index.html
  if (isDocOrStyle) {
    event.respondWith(
      fetch(req)
        .then((res) => {
          if (res && res.status === 200) {
            const clone = res.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(req, clone));
          }
          return res;
        })
        .catch(() => caches.match(req, { ignoreSearch: req.mode === 'navigate' }))
    );
    return;
  }

  // Cache-First with background refresh for icons and static vendor scripts
  event.respondWith(
    caches.match(req).then((cached) => {
      const fetchPromise = fetch(req)
        .then((res) => {
          if (res && res.status === 200) {
            const clone = res.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(req, clone));
          }
          return res;
        })
        .catch(() => cached);
      return cached || fetchPromise;
    })
  );
});
