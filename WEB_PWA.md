# AbelNotes on the web (PWA)

The web build is the same app, running in the browser and installable on an
iPad's Home Screen. Notebooks live **on the device** (IndexedDB), so it opens
and records notes with no network and no server running; sync with Nextcloud /
WebDAV happens whenever you are online.

## Build

```bash
tool/build_web.sh              # served from the site root
tool/build_web.sh /abelnotes/  # served from a sub-path
```

Output: `build/web/` — a plain static folder (~50 MB, mostly CanvasKit).
The script bundles CanvasKit and fonts (no CDN), and installs an offline
service worker (`tool/web_sw.js`) that precaches every file.

## Startup

What keeps the first frame early (measured on Chrome, desktop):

- **The app script is not served by the service worker.** V8 keeps the
  compiled code of a script only when the browser fetched it itself; served
  from Cache Storage (precached, cached later, or passed through with
  `fetch()`), the 6.7 MB `main.dart.js` was recompiled on every launch:
  ~960 ms to the first frame instead of ~340 ms. The worker therefore lets
  `main.dart.<build id>.js` go to the network / HTTP cache, and
  `flutter_bootstrap.js` asks for its precached copy (`?offline`) only when
  the browser is offline or that load fails. The build id in the name keeps
  an older cached shell from running a newer script: on the server the old
  name answers with the HTML fallback, the load fails, and the worker's copy
  of the same build runs.
- **The loader does not wait for the worker.** `flutter_bootstrap.js` has no
  `serviceWorkerSettings` (with them a first visit waited up to 4 s for the
  install), and `index.html` registers the worker after the first frame, so
  its download of the whole build never competes with the app's own files.
- **A splash** in the app's paper / dark colour covers the load instead of a
  white page, and goes at Flutter's `flutter-first-frame` event.

## Host it (no PC needed)

Any static HTTPS host works; **HTTPS is required** (service workers and
Add-to-Home-Screen don't work over plain HTTP, except on `localhost`).

- On the same host as your Nextcloud (recommended — see CORS below).
- Cloudflare Pages / Netlify: upload the `build/web` folder directly. Do not
  connect it to the public repository.

## Sync needs CORS (or the same origin)

A browser only lets the app talk to your Nextcloud if either:

1. the app is served from the **same origin** as Nextcloud (e.g. an `/abelnotes/`
   alias on the same domain) — nothing else to configure; or
2. Nextcloud answers CORS preflights for the app's origin. nginx example:

```nginx
location /remote.php/dav/ {
    if ($request_method = OPTIONS) {
        add_header Access-Control-Allow-Origin  "https://notes.example.com" always;
        add_header Access-Control-Allow-Methods "GET, PUT, DELETE, PROPFIND, MKCOL, MOVE, COPY, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Authorization, Depth, Content-Type, If-Match, If-None-Match, Destination, Overwrite" always;
        add_header Access-Control-Max-Age 86400 always;
        return 204;
    }
    add_header Access-Control-Allow-Origin  "https://notes.example.com" always;
    add_header Access-Control-Expose-Headers "ETag, Content-Length, Last-Modified" always;
    # ... usual Nextcloud proxy/fastcgi config
}
```

If a reverse proxy sits in front of Nextcloud, leave request buffering on
(nginx's default). With `proxy_request_buffering off` an upload cut off
midway reaches Nextcloud as a short body, and Nextcloud may keep it in place
of the file. Current app versions upload pages to a temporary file and rename
it, so they are safe either way; older ones are not.

## Limits of the web build

- Google Drive sign-in, OneNote import and Obsidian-vault import are desktop/mobile only.
- Storage is the browser's: on iPad, **add the app to the Home Screen**
  (Share → Add to Home Screen). Safari may evict the data of a plain website
  that goes unused for ~7 days; an installed web app is exempt. Keep sync on
  as a backup.
- Exports are downloads (Files app on iPad).
- No certificate pinning (the browser decides which certificates to trust).
