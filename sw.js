// MaxWord service worker — intentionally minimal.
// Its only job is to be registered at all: a registered service worker is
// one of the signals Chrome's installability check looks at, which helps
// the "Add to Home Screen" prompt actually fire. There is no push handling
// here — the browser-push notification feature was removed (it needs a
// server-side sender via a Supabase Edge Function + real VAPID keys, which
// was never built, so it was pulled rather than shipped half-working).

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));
