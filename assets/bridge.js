/* Sydwalt OS app bridge.
 *
 * Injected into every page at document start, before the web app's own
 * scripts run. It makes four browser features that a mobile WebView does not
 * provide behave the way they do in Chrome or Safari, without any change to
 * the web app itself:
 *
 *   1. Downloads. The web app saves exports by clicking an <a download> whose
 *      href is a blob: URL (CSV logs, Word reports, the company book) or a
 *      same-origin file URL. A WebView cannot save either, so the click is
 *      caught here, the bytes are read in the page and handed to the app,
 *      which saves them to its Downloads library.
 *   2. Revoked blobs. Several exports call URL.revokeObjectURL right after
 *      click(), before an asynchronous read could finish. Every Blob passed
 *      to createObjectURL is therefore kept here for two minutes after it is
 *      revoked, and read from that copy rather than from the URL.
 *   3. window.print(). WebViews ignore it; it is forwarded to the native
 *      print dialog, which also offers "Save as PDF". beforeprint and
 *      afterprint still fire, so the web app's title swap keeps working.
 *   4. New tabs. window.open() and target="_blank" links have no tab to open
 *      in; the app decides whether to load the URL in place, download it or
 *      hand it to the system browser.
 *
 * Every call into the app goes through window.flutter_inappwebview, which may
 * not exist yet at document start, so calls wait for the platform-ready event.
 */
(function () {
  'use strict';
  if (window.__sydwaltShell) return;

  var KEEP_REVOKED_MS = 120000;
  var blobs = new Map();
  var readyResolve;
  var ready = new Promise(function (resolve) { readyResolve = resolve; });

  function checkReady() {
    if (window.flutter_inappwebview && typeof window.flutter_inappwebview.callHandler === 'function') {
      readyResolve();
      return true;
    }
    return false;
  }
  if (!checkReady()) {
    window.addEventListener('flutterInAppWebViewPlatformReady', checkReady);
    var poll = setInterval(function () { if (checkReady()) clearInterval(poll); }, 50);
    ready.then(function () { clearInterval(poll); });
  }

  function call(handler, payload) {
    return ready.then(function () { return window.flutter_inappwebview.callHandler(handler, payload); });
  }

  /* ---- 2. keep blobs readable after revoke ------------------------------ */
  var origCreate = URL.createObjectURL;
  var origRevoke = URL.revokeObjectURL;
  URL.createObjectURL = function (obj) {
    var url = origCreate.apply(URL, arguments);
    if (obj instanceof Blob) blobs.set(url, obj);
    return url;
  };
  URL.revokeObjectURL = function (url) {
    origRevoke.apply(URL, arguments);
    setTimeout(function () { blobs.delete(url); }, KEEP_REVOKED_MS);
  };

  /* ---- 1. downloads ----------------------------------------------------- */
  function sameOrigin(href) {
    try { return new URL(href, location.href).origin === location.origin; } catch (e) { return false; }
  }

  function nameFromDisposition(header) {
    if (!header) return '';
    var star = /filename\*\s*=\s*(?:UTF-8|utf-8)''([^;]+)/.exec(header);
    if (star) { try { return decodeURIComponent(star[1].trim()); } catch (e) { /* fall through */ } }
    var plain = /filename\s*=\s*"?([^";]+)"?/.exec(header);
    return plain ? plain[1].trim() : '';
  }

  function nameFromUrl(href) {
    try {
      var last = new URL(href, location.href).pathname.split('/').pop() || '';
      return decodeURIComponent(last);
    } catch (e) { return ''; }
  }

  function blobToBase64(blob) {
    return new Promise(function (resolve, reject) {
      var reader = new FileReader();
      reader.onload = function () {
        var s = String(reader.result || '');
        resolve(s.slice(s.indexOf(',') + 1));
      };
      reader.onerror = function () { reject(reader.error || new Error('Could not read the file.')); };
      reader.readAsDataURL(blob);
    });
  }

  function download(anchor) {
    var href = anchor.href;
    var name = anchor.getAttribute('download') || '';
    var known = blobs.get(href);
    var isLocal = href.indexOf('blob:') === 0 || href.indexOf('data:') === 0 || sameOrigin(href);
    if (!known && !isLocal) {
      /* Browsers ignore the download attribute across origins, so this is
         an ordinary link to another site. */
      return call('openUrl', { url: href });
    }
    var token = 'dl-' + Date.now() + '-' + Math.random().toString(36).slice(2);
    call('downloadStarted', { token: token, name: name || nameFromUrl(href) });
    var get = known
      ? Promise.resolve({ blob: known, name: name })
      : fetch(href, { credentials: 'include' }).then(function (res) {
          if (!res.ok) throw new Error('The server answered ' + res.status + '.');
          return res.blob().then(function (b) {
            return { blob: b, name: name || nameFromDisposition(res.headers.get('Content-Disposition')) || nameFromUrl(href) };
          });
        });
    return get
      .then(function (got) {
        return blobToBase64(got.blob).then(function (base64) {
          return call('download', {
            token: token,
            name: got.name || 'Sydwalt download',
            mime: got.blob.type || 'application/octet-stream',
            size: got.blob.size,
            base64: base64,
          });
        });
      })
      .catch(function (err) {
        return call('downloadFailed', { token: token, name: name, message: String((err && err.message) || err) });
      });
  }

  function isDownloadAnchor(a) {
    return !!(a && a.hasAttribute && a.hasAttribute('download') && a.getAttribute('href'));
  }

  /* Exports build a detached <a> and call click() on it, so no document
     listener would ever see that click. */
  var origClick = HTMLAnchorElement.prototype.click;
  HTMLAnchorElement.prototype.click = function () {
    if (isDownloadAnchor(this)) { download(this); return; }
    if (opensNewTab(this)) { openInApp(this.href); return; }
    return origClick.apply(this, arguments);
  };

  /* ---- 4. new tabs ------------------------------------------------------ */
  function opensNewTab(a) {
    var t = (a.getAttribute('target') || '').toLowerCase();
    return !!(a.getAttribute('href') && t && t !== '_self' && t !== '_top' && t !== '_parent');
  }

  function openInApp(url) {
    var abs;
    try { abs = new URL(url, location.href).href; } catch (e) { abs = String(url); }
    call('openUrl', { url: abs });
  }

  window.open = function (url) {
    if (url == null || url === '' || url === 'about:blank') {
      console.warn('Sydwalt app: window.open() without a URL is not supported in the app.');
      return null;
    }
    openInApp(url);
    return null;
  };

  /* Real taps. Bubble phase on window runs after the web app's own handlers,
     so a link the app already handled (defaultPrevented) is left alone. */
  window.addEventListener('click', function (e) {
    if (e.defaultPrevented || e.button !== 0) return;
    var a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
    if (!a) return;
    if (isDownloadAnchor(a)) { e.preventDefault(); download(a); return; }
    if (opensNewTab(a)) { e.preventDefault(); openInApp(a.href); }
  }, false);

  /* ---- 3. printing ------------------------------------------------------ */
  window.print = function () {
    try { window.dispatchEvent(new Event('beforeprint')); } catch (e) { /* ignore */ }
    call('print', { title: document.title })
      .catch(function (err) { console.warn('Sydwalt app: printing failed', err); })
      .then(function () {
        try { window.dispatchEvent(new Event('afterprint')); } catch (e) { /* ignore */ }
      });
  };

  window.__sydwaltShell = { version: 1, _blobs: blobs };
})();
