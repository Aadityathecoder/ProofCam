// Offline shell: ProofCam needs no network once loaded, so cache the app's own files.
const CACHE = 'proofcam-web-v1';
const FILES = ['./', 'index.html', 'styles.css', 'manifest.webmanifest', 'icons/icon.svg', 'icons/icon-180.png',
  'js/app.js', 'js/brand.js', 'js/icons.js', 'js/store.js', 'js/worker.js', 'js/core/image.js', 'js/core/watermark.js', 'js/core/proof.js'];
self.addEventListener('install', (event) => event.waitUntil(caches.open(CACHE).then((c) => c.addAll(FILES)).then(() => self.skipWaiting())));
self.addEventListener('activate', (event) => event.waitUntil(caches.keys()
  .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim())));
self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET' || new URL(event.request.url).origin !== location.origin) return;
  event.respondWith(fetch(event.request).then((response) => {
    const copy = response.clone(); caches.open(CACHE).then((c) => c.put(event.request, copy)); return response;
  }).catch(() => caches.match(event.request)));
});
