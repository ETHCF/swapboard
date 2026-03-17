/**
 * Swapboard Service Worker
 * No-op worker for PWA support. Does not cache or intercept requests.
 */

self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => {
  // Clean up any old caches from previous versions
  event.waitUntil(
    caches.keys().then((names) => Promise.all(names.map((n) => caches.delete(n))))
  );
  self.clients.claim();
});
