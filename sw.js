// MaxWord service worker — intentionally minimal.
// Its main job is to be registered at all: a registered service worker is
// one of the signals Chrome's installability check looks at, which helps
// the "Add to Home Screen" prompt actually fire. There is no push handling
// here — the browser-push notification feature was removed (it needs a
// server-side sender via a Supabase Edge Function + real VAPID keys, which
// was never built, so it was pulled rather than shipped half-working).

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

// Force the app's own HTML page and JS files to always be fetched fresh
// from the network, bypassing whatever the browser or GitHub Pages' CDN
// would otherwise cache. This is what actually fixes "different people see
// different/old versions of the app" — GitHub Pages doesn't let us set our
// own Cache-Control headers, and the <meta http-equiv="Cache-Control">
// tags in index.html are a weak signal most browsers largely ignore for
// real caching decisions. This is the one lever we do have control over.
// Nothing is cached here (no caches.put anywhere) — this purely bypasses
// existing caches, it doesn't add a new one, so there's no separate cache
// to go stale or need clearing later.
self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  const isSameOrigin = url.origin === self.location.origin;
  const isAppFile = event.request.mode === 'navigate' || /\.(html|js)$/.test(url.pathname);
  if (isSameOrigin && isAppFile) {
    event.respondWith(fetch(event.request, { cache: 'no-store' }));
  }
});
