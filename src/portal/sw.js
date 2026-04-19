// sw.js — Service Worker SoundSpot PWA
// Cache les assets statiques pour un fonctionnement hors-ligne partiel.
// Les appels CGI (.sh) ne sont jamais mis en cache (toujours réseau).

const CACHE = 'soundspot-v1';
const STATIC = ['/', '/index.html', '/manifest.json', '/sw.js'];

// ── Installation : pré-cache les assets statiques ─────────────
self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE).then(c => c.addAll(STATIC)).then(() => self.skipWaiting())
  );
});

// ── Activation : purge les anciens caches ─────────────────────
self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

// ── Fetch : stratégie hybride ─────────────────────────────────
// • Scripts CGI (.sh) → toujours réseau (jamais de cache)
// • Assets statiques  → cache-first, puis réseau
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);

  // CGI → réseau direct, pas de cache
  if (url.pathname.endsWith('.sh')) {
    e.respondWith(fetch(e.request));
    return;
  }

  // Assets statiques → cache-first
  e.respondWith(
    caches.match(e.request).then(cached => {
      if (cached) return cached;
      return fetch(e.request).then(resp => {
        // Ne pas cacher les réponses non-OK
        if (!resp || resp.status !== 200 || resp.type === 'opaque') return resp;
        const clone = resp.clone();
        caches.open(CACHE).then(c => c.put(e.request, clone));
        return resp;
      });
    }).catch(() => caches.match('/index.html')) // fallback offline
  );
});
