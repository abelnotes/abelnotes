// AbelNotes offline service worker. Installed by tool/build_web.sh in place of
// Flutter's own flutter_service_worker.js (which, as of Flutter 3.44, is a stub
// that unregisters itself and caches nothing). The loader registers it under
// that same file name, so no page code has to change.
//
// Strategy: every file of the build is precached on install, then served
// cache-first (the app script only offline, see the fetch handler), so the app
// opens with no network at all. A new build gets a new
// CACHE name; the old cache is dropped once the new worker activates.
'use strict';

const CACHE = 'abelnotes-__BUILD_ID__';
const FILES = __FILES__;

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) =>
      // One by one so a single failure doesn't abort the whole install.
      Promise.all(FILES.map((f) => cache.add(new Request(f, { cache: 'reload' })).catch(() => {})))
    ).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  // Only our own files. WebDAV / Drive traffic goes straight to the network.
  if (url.origin !== self.location.origin) return;
  // V8 recompiles a script served from here on every launch, so the app script
  // goes to the browser; flutter_bootstrap.js adds ?offline when that can't work.
  if (/\/main\.dart\.[^/]+\.js$/.test(url.pathname) && !url.searchParams.has('offline')) return;

  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const hit = await cache.match(req, { ignoreSearch: true });
    if (hit) return hit;
    try {
      const res = await fetch(req);
      if (res.ok) cache.put(req, res.clone());
      return res;
    } catch (e) {
      if (req.mode === 'navigate') {
        const shell = await cache.match('index.html') || await cache.match('./');
        if (shell) return shell;
      }
      throw e;
    }
  })());
});
