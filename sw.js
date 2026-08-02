// MaxWord service worker — handles incoming push notifications.
// (The send-side — actually triggering a push when someone starts a
// challenge — needs a Supabase Edge Function with the web-push library
// and your VAPID private key. See README > "Web Push setup".)

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

self.addEventListener('push', (event) => {
  let payload = { title: 'MaxWord', body: 'Someone challenged you!', url: '/' };
  try { payload = event.data.json(); } catch (e) { /* use default */ }

  event.waitUntil(
    self.registration.showNotification(payload.title, {
      body: payload.body,
      icon: 'icon-192.png',
      badge: 'icon-192.png',
      data: { url: payload.url || '/' }
    })
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(clients.openWindow(event.notification.data?.url || '/'));
});
