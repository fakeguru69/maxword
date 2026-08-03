// MaxWord service worker — handles incoming push notifications.
// (The send-side — actually triggering a push when someone starts a
// challenge — needs a Supabase Edge Function with the web-push library
// and your VAPID private key. See README > "Web Push setup".)
//
// THROTTLE POLICY (for whoever builds that edge function):
// cap at ~2-3 pushes per person per day. Suggested approach — batch:
// don't fire one push per event; instead run on a timer (e.g. every few
// hours) and send at most one push per person per run, summarizing
// everything new since their last push ("wxmen challenged you + 2 more
// open challenges waiting"). This keeps the promise made in the
// in-app "turn on notifications" banner copy.

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
