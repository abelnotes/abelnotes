{{flutter_js}}
{{flutter_build_config}}

// The app script comes from the network / HTTP cache, the offline worker's copy
// (?offline) only when the server can't give this build (WEB_PWA.md, Startup).
(function () {
  var build = _flutter.buildConfig.builds.filter(function (b) { return b.mainJsPath; })[0];
  var sw = navigator.serviceWorker && navigator.serviceWorker.controller;
  if (!build || !sw) return _flutter.loader.load();
  var path = build.mainJsPath, started = false;

  function retry(e) {
    var s = e.target;
    if (!(s instanceof HTMLScriptElement) || s.src.indexOf(path) < 0 ||
        s.src.indexOf('?offline') >= 0) return;
    window.removeEventListener('error', retry, true);
    var again = document.createElement('script');
    again.src = path + '?offline';
    document.head.append(again);
  }
  // No serviceWorkerSettings: they make the loader wait up to 4 s for the
  // worker's install. index.html registers it after the first frame.
  function start(online) {
    if (started) return;
    started = true;
    if (online) window.addEventListener('error', retry, true);
    else build.mainJsPath = path + '?offline';
    _flutter.loader.load();
  }

  if (navigator.onLine === false) return start(false);
  var ctl = typeof AbortController === 'function' ? new AbortController() : null;
  setTimeout(function () { if (ctl) ctl.abort(); start(false); }, 2000);
  // An older build's name gets the server's HTML fallback, not a script.
  fetch(path, { method: 'HEAD', cache: 'no-store', signal: ctl ? ctl.signal : undefined })
      .then(function (r) {
        return r.ok && /javascript/.test(r.headers.get('content-type') || '');
      }, function () { return false; })
      .then(start);
})();
