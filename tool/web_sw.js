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
// Fallback fonts are cached on first use and kept across builds: their paths carry a version.
const FONTS = 'abelnotes-fonts';
const FILES = __FILES__;
// Files fetched only when the app needs them (path from the scope: content hash),
// cached on first use in FONTS under a versioned key, so an update keeps them.
const LAZY = __LAZY__;

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) =>
      // One by one so a single failure doesn't abort the whole install.
      Promise.all(FILES.map((f) => cache.add(new Request(f, { cache: 'reload' })).catch(() => {})))
    ).then(keepLazyFromHttpCache).then(() => self.skipWaiting())
  );
});

function lazyKey(path, version) {
  return `${new URL(path, self.registration.scope).href}?v=${version}`;
}

// The page may have fetched a lazy file before this worker controlled it (the
// worker registers after the first frame): keep that copy, never download one.
async function keepLazyFromHttpCache() {
  const cache = await caches.open(FONTS);
  await Promise.all(Object.entries(LAZY).map(async ([path, version]) => {
    const key = lazyKey(path, version);
    if (await cache.match(key)) return;
    try {
      const res = await fetch(new Request(path, { cache: 'only-if-cached', mode: 'same-origin' }));
      if (res.ok) await cache.put(key, res);
    } catch (e) { /* not in the HTTP cache, or unsupported: cached on next use */ }
  }));
}

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE && k !== FONTS).map((k) => caches.delete(k))))
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

  const scope = new URL(self.registration.scope).pathname;
  const lazy = url.pathname.startsWith(scope) && LAZY[url.pathname.slice(scope.length)];
  if (lazy) {
    event.respondWith((async () => {
      const cache = await caches.open(FONTS);
      const key = lazyKey(url.pathname.slice(scope.length), lazy);
      const hit = await cache.match(key);
      if (hit) return hit;
      const res = await fetch(req);
      if (res.ok) {
        await cache.put(key, res.clone());
        // Drop the copies of earlier versions.
        for (const old of await cache.keys()) {
          const u = new URL(old.url);
          if (u.pathname === url.pathname && old.url !== key) await cache.delete(old);
        }
      }
      return res;
    })());
    return;
  }

  event.respondWith((async () => {
    const cache = await caches.open(url.pathname.includes('/fonts/fallback/') ? FONTS : CACHE);
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
