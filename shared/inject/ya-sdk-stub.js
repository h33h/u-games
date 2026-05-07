// Layer 2: SDK stub. Inject in iframe (game CDN hosts) at documentStart.
// Catches direct calls to ysdk.adv.* from inside the game bundle and replies
// with onClose(false) so the game thinks an ad was attempted but skipped.
// Wraps real YaGames so non-adv methods (player, storage, getStorage, environment,
// auth, payments, leaderboards, features.*) keep working unchanged.
//
// Yandex hosts games on multiple CDN families:
//   - app-XXX.games.s3.yandex.net     (legacy S3 origin)
//   - app-XXX.cdn.games.yandex.net    (CDN edge — e.g. 263344 Red Ball 4)
//   - app-XXX.gamecdn.yandex.net      (alt CDN)
//   - publisher-owned domains, e.g. game-static.ru (Vizor Apps / Klondike)
// Hard-coding every publisher CDN doesn't scale; the universal marker is
// the `#origin=https://yandex.com|ru` hash that Yandex appends when it
// loads a game iframe, regardless of host. We accept either signal.
(function () {
  // Origin guard: only run inside Yandex-hosted game iframes, no-op on
  // yandex.com itself or any unrelated frame.
  try {
    var host = location.host;
    var hash = location.hash || '';
    var hashHasYandexOrigin =
      hash.indexOf('origin=https%3A%2F%2Fyandex.com') !== -1 ||
      hash.indexOf('origin=https://yandex.com') !== -1 ||
      hash.indexOf('origin=https%3A%2F%2Fyandex.ru') !== -1 ||
      hash.indexOf('origin=https://yandex.ru') !== -1;
    var hostMatchesGameCdn =
      host.indexOf('games.s3.yandex.net') !== -1 ||
      host.indexOf('cdn.games.yandex.net') !== -1 ||
      host.indexOf('gamecdn.yandex.net') !== -1 ||
      host.indexOf('game-static.ru') !== -1;
    var inGameFrame = hashHasYandexOrigin || hostMatchesGameCdn;
    // Avoid running on yandex.com / yandex.ru / passport.* — we have a
    // separate honest-path / pwa-mode pair for those.
    if (host.indexOf('yandex.com') !== -1 || host.indexOf('yandex.ru') !== -1 ||
        host.indexOf('yandex.by') !== -1 || host.indexOf('yandex.kz') !== -1 ||
        host.indexOf('yandex.uz') !== -1 || host.indexOf('passport.') !== -1) {
      inGameFrame = false;
    }
    if (!inGameFrame) return;
  } catch (_) { return; }

  if (window.__yga_stub__) return;
  window.__yga_stub__ = true;

  function ylog(tag, msg) {
    try { if (typeof window.__yga_log === 'function') window.__yga_log(tag, msg); } catch (_) {}
  }

  // Forward console.error / console.warn / unhandled errors to LogStore so
  // games that freeze at the loader leave a breadcrumb trail (Construct 3 /
  // GamePush titles like 388978 dump useful messages on init failure that
  // we'd otherwise need a USB-attached browser to see).
  try {
    var realErr = console.error.bind(console);
    var realWarn = console.warn.bind(console);
    function fmt(args) {
      try {
        return Array.prototype.map.call(args, function (a) {
          if (a == null) return String(a);
          if (typeof a === 'string') return a;
          if (a instanceof Error) return (a.name || 'Error') + ': ' + a.message;
          try { return JSON.stringify(a); } catch (_) { return String(a); }
        }).join(' ').slice(0, 600);
      } catch (_) { return '<unstringifiable>'; }
    }
    console.error = function () { try { ylog('jserr', fmt(arguments)); } catch (_) {} return realErr.apply(console, arguments); };
    console.warn  = function () { try { ylog('jswarn', fmt(arguments)); } catch (_) {} return realWarn.apply(console, arguments); };
    window.addEventListener('error', function (ev) {
      var src = ev && (ev.filename || (ev.target && (ev.target.src || ev.target.href)) || '');
      ylog('jserr', 'window.onerror ' + (ev && ev.message || '') + ' @ ' + (src || '?') + (ev && ev.lineno ? ':' + ev.lineno : ''));
    }, true);
    window.addEventListener('unhandledrejection', function (ev) {
      var r = ev && ev.reason;
      var msg = r ? (r.message || String(r)) : '?';
      ylog('jserr', 'unhandledrejection ' + msg);
    });
  } catch (_) {}

  // Behavior flags. 'auto' grants the rewarded reward without showing an ad
  // (the user expects every monetization touchpoint to "just work" for free).
  var REWARDED_MODE = 'auto';
  var FREE_PURCHASES = true;

  // Trap screen.orientation.lock() so the native wrapper knows when a game
  // wants landscape — the iOS shell shows a "rotate device" overlay when the
  // device is in portrait but the game wants landscape. WKWebView rejects
  // lock() anyway, so we forward to the real call (which throws) and just
  // capture the requested target as a side-channel notification.
  try {
    if (typeof screen !== 'undefined' && screen.orientation &&
        typeof screen.orientation.lock === 'function' &&
        !screen.orientation.__yga_trapped__) {
      var realLock = screen.orientation.lock.bind(screen.orientation);
      screen.orientation.lock = function (target) {
        ylog('orient', String(target));
        try { return realLock(target); }
        catch (e) { return Promise.reject(e); }
      };
      screen.orientation.__yga_trapped__ = true;
    }
  } catch (_) {}

  // Many games never call screen.orientation.lock(); instead they hard-code
  // a canvas at a fixed resolution (e.g. 1920×1080 for landscape, 720×1280
  // for portrait). Watch for the canvas to mount and auto-emit an `orient`
  // signal based on its aspect ratio so the native shell can show the
  // rotate-overlay even when the SDK lock() trap stays silent.
  var __yga_orient_emitted__ = false;
  function emitOrientFromCanvas(canvas, stage) {
    if (__yga_orient_emitted__ || !canvas) return;
    var cw = canvas.width || canvas.getBoundingClientRect().width || 0;
    var ch = canvas.height || canvas.getBoundingClientRect().height || 0;
    if (cw < 200 || ch < 200) return; // skip placeholders / empty canvases
    var ratio = cw / ch;
    var inferred = null;
    if (ratio > 1.3) inferred = 'landscape';
    else if (ratio < 0.77) inferred = 'portrait';
    if (inferred) {
      __yga_orient_emitted__ = true;
      ylog('orient', inferred + ' (canvas ' + cw + 'x' + ch + ' ' + stage + ')');
    }
  }

  function reportViewport(stage) {
    try {
      var w = window.innerWidth || 0;
      var h = window.innerHeight || 0;
      var ar = h > 0 ? (w / h).toFixed(2) : '?';
      var meta = document.querySelector('meta[name="viewport"]');
      var metaC = meta ? String(meta.content || '').slice(0, 120) : '';
      var canvas = document.querySelector('canvas');
      var cw = canvas ? canvas.width : 0;
      var ch = canvas ? canvas.height : 0;
      ylog('orient', stage + ' inner=' + w + 'x' + h + ' ar=' + ar +
                     ' canvas=' + cw + 'x' + ch + ' viewport=' + metaC);
      emitOrientFromCanvas(canvas, stage);
    } catch (_) {}
  }

  // Watch DOM for canvas insertion and resize — cover Unity / Phaser / PIXI
  // games that mount their canvas dynamically after the engine boots.
  function startCanvasWatcher() {
    try {
      if (typeof MutationObserver !== 'function') return;
      var mo = new MutationObserver(function () {
        if (__yga_orient_emitted__) { mo.disconnect(); return; }
        var c = document.querySelector('canvas');
        if (c) emitOrientFromCanvas(c, 'mutated');
      });
      var root = document.documentElement || document.body;
      if (root) mo.observe(root, { childList: true, subtree: true, attributes: true, attributeFilter: ['width', 'height'] });
      // Stop polling after 30s — by then any reasonable game has rendered.
      setTimeout(function () { try { mo.disconnect(); } catch (_) {} }, 30000);
    } catch (_) {}
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () {
      reportViewport('domready');
      startCanvasWatcher();
    });
  } else {
    reportViewport('atstart');
    startCanvasWatcher();
  }
  setTimeout(function () { reportViewport('boot+2s'); }, 2000);
  setTimeout(function () { reportViewport('boot+5s'); }, 5000);

  // Backend purchase verification bypass.
  //
  // Games often ship the fake Purchase we just resolved (`{purchaseToken,
  // signature}`) to their own backend, which then asks Yandex's API to
  // validate the signature. Our fake signature won't pass, so the backend
  // returns "invalid", and the game refuses to grant the item.
  //
  // We detect outbound requests that carry our recognizable token prefix
  // `__yga_free_` (or a known fake signature) in the URL or body, and
  // synthesize a 200 OK JSON response with every commonly-used "success"
  // shape. The game's backend is bypassed end-to-end — no real verification
  // happens, the game sees what looks like a valid receipt confirmation.
  var FAKE_PURCHASE_MARKER = '__yga_free_';
  function isOurFakePurchase(s) {
    return typeof s === 'string' && s.indexOf(FAKE_PURCHASE_MARKER) !== -1;
  }
  function fakeVerifyResponseBody() {
    return JSON.stringify({
      ok: true, success: true, valid: true, verified: true,
      granted: true, status: 'ok', result: 'success',
      isValid: true, isVerified: true, isGranted: true,
      // Also echo a fake order ID/receipt in case the caller reads it.
      orderId: '__yga_free_order_' + Date.now(),
      receipt: '__yga_free_receipt__'
    });
  }

  function patchFetch() {
    if (typeof window.fetch !== 'function' || window.__yga_fetch_patched__) return;
    window.__yga_fetch_patched__ = true;
    var origFetch = window.fetch.bind(window);
    window.fetch = function (input, init) {
      try {
        var url = typeof input === 'string' ? input : (input && input.url) || '';
        var body = init && init.body;
        var bodyStr = '';
        if (typeof body === 'string') bodyStr = body;
        else if (body instanceof URLSearchParams) bodyStr = body.toString();
        if (isOurFakePurchase(url) || isOurFakePurchase(bodyStr)) {
          ylog('sdk', 'fetch verify intercepted: ' + String(url).slice(0, 120));
          return Promise.resolve(new Response(fakeVerifyResponseBody(), {
            status: 200,
            headers: { 'Content-Type': 'application/json' }
          }));
        }
      } catch (_) {}
      return origFetch(input, init);
    };
  }

  // Hook XMLHttpRequest.prototype only — do NOT replace the constructor
  // (a wrapper class breaks games that rely on subtle XHR semantics like
  // `withCredentials`, `responseType`, custom headers — Klondike refused to
  // launch with a wrapper). When send() sees our `__yga_free_` marker we
  // short-circuit before the real XHR fires the network request, then
  // synthesize a 200 lifecycle by overriding the relevant getters on the
  // instance. setTimeout(0) ensures listeners fire after .send() returns.
  function patchXHR() {
    if (typeof XMLHttpRequest !== 'function' || XMLHttpRequest.prototype.__yga_xhr_proto_patched__) return;
    XMLHttpRequest.prototype.__yga_xhr_proto_patched__ = true;
    var origOpen = XMLHttpRequest.prototype.open;
    var origSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function (method, url) {
      this.__yga_url__ = url;
      this.__yga_method__ = method;
      return origOpen.apply(this, arguments);
    };
    XMLHttpRequest.prototype.send = function (body) {
      try {
        var bodyStr = (typeof body === 'string') ? body : '';
        var url = this.__yga_url__ || '';
        if (isOurFakePurchase(url) || isOurFakePurchase(bodyStr)) {
          ylog('sdk', 'xhr verify intercepted: ' + String(url).slice(0, 120));
          var self = this;
          var bodyText = fakeVerifyResponseBody();
          // Override the readonly getters on this instance with own
          // properties. Configurable getters/setters shadow the prototype
          // descriptors. WebKit / Chromium both honour this.
          function defGetter(prop, value) {
            try {
              Object.defineProperty(self, prop, {
                configurable: true,
                get: function () { return value; },
                set: function () {}
              });
            } catch (_) {}
          }
          // Walk the lifecycle so any onreadystatechange handler that
          // checks readyState===4 fires correctly.
          setTimeout(function () {
            try {
              defGetter('responseURL', url);
              defGetter('statusText', 'OK');
              defGetter('status', 200);
              defGetter('responseText', bodyText);
              try {
                var rt = self.responseType;
                if (rt === 'json') defGetter('response', JSON.parse(bodyText));
                else if (rt === 'arraybuffer' && typeof TextEncoder !== 'undefined') defGetter('response', new TextEncoder().encode(bodyText).buffer);
                else defGetter('response', bodyText);
              } catch (_) { defGetter('response', bodyText); }
              defGetter('readyState', 4);

              var rsc = new Event('readystatechange');
              if (typeof self.onreadystatechange === 'function') { try { self.onreadystatechange(rsc); } catch (_) {} }
              try { self.dispatchEvent(rsc); } catch (_) {}
              var le = new Event('load');
              if (typeof self.onload === 'function') { try { self.onload(le); } catch (_) {} }
              try { self.dispatchEvent(le); } catch (_) {}
              var lee = new Event('loadend');
              if (typeof self.onloadend === 'function') { try { self.onloadend(lee); } catch (_) {} }
              try { self.dispatchEvent(lee); } catch (_) {}
            } catch (_) {}
          }, 0);
          return; // do not call real send
        }
      } catch (_) {}
      return origSend.apply(this, arguments);
    };
  }

  patchFetch();
  patchXHR();

  var real = undefined;
  var patchedCache = null;

  function patchAdv(adv) {
    if (!adv) return;
    // Pass `true` to onClose so the game's "wasShown" check passes — many
    // games gate the reward-grant on it instead of just onRewarded().
    adv.showFullscreenAdv = function (opts) {
      var cb = (opts && opts.callbacks) || {};
      try { cb.onOpen && cb.onOpen(); } catch (_) {}
      Promise.resolve().then(function () { try { cb.onClose && cb.onClose(true); } catch (_) {} });
      ylog('sdk', 'showFullscreenAdv auto-closed');
    };
    adv.showRewardedVideo = function (opts) {
      var cb = (opts && opts.callbacks) || {};
      try { cb.onOpen && cb.onOpen(); } catch (_) {}
      if (REWARDED_MODE === 'auto') {
        try { cb.onRewarded && cb.onRewarded(); } catch (_) {}
        ylog('sdk', 'showRewardedVideo: reward granted (auto)');
      } else {
        try { cb.onError && cb.onError({ code: 'NO_REWARD' }); } catch (_) {}
      }
      Promise.resolve().then(function () { try { cb.onClose && cb.onClose(REWARDED_MODE === 'auto'); } catch (_) {} });
    };
    adv.showBannerAdv = function () { return Promise.resolve({ stickyAdvIsShowing: false, reason: 'OK' }); };
    adv.hideBannerAdv = function () { return Promise.resolve({ stickyAdvIsShowing: false }); };
    adv.getBannerAdvStatus = function () { return Promise.resolve({ stickyAdvIsShowing: false }); };
  }

  // Local persistence for granted-free purchases. Per-iframe-origin via
  // localStorage — survives page reloads but does not sync across games.
  // Most games maintain their own progression state via ysdk.getStorage()
  // anyway; we just need purchase() to resolve and getPurchases() to return
  // a consistent list for restore-purchases flows.
  var FREE_PURCHASES_KEY = '__yga_free_purchases__';
  function readFreePurchases() {
    try { return JSON.parse(localStorage.getItem(FREE_PURCHASES_KEY) || '[]'); }
    catch (_) { return []; }
  }
  function writeFreePurchases(arr) {
    try { localStorage.setItem(FREE_PURCHASES_KEY, JSON.stringify(arr)); } catch (_) {}
  }

  function patchPayments(payments) {
    if (!payments || !FREE_PURCHASES) return;
    payments.purchase = function (opts) {
      // Yandex SDK accepts `payments.purchase({id, developerPayload})` per
      // their docs, but some games pass the productID as a bare string,
      // others use camelCase `productID`, others wrap in `payload`. Try
      // every shape we've observed in the wild.
      var input = opts;
      if (typeof input === 'string') input = { id: input };
      if (!input || typeof input !== 'object') input = {};
      var id = input.id || input.productID || input.product_id ||
               input.productId || input.product || 'unknown';
      var devPayload = input.developerPayload || input.developer_payload ||
                       input.payload || '';
      var rawDump;
      try { rawDump = JSON.stringify(input).slice(0, 200); } catch (_) { rawDump = '<unstringifiable>'; }
      var purchase = {
        productID: id,
        purchaseToken: '__yga_free_' + Date.now() + '_' + Math.random().toString(36).slice(2, 8),
        developerPayload: devPayload,
        signature: '__yga_free_signature__'
      };
      var arr = readFreePurchases();
      arr.push(purchase);
      writeFreePurchases(arr);
      ylog('sdk', 'purchase args=' + rawDump + ' -> id=' + id);
      return Promise.resolve(purchase);
    };
    payments.getPurchases = function () {
      var arr = readFreePurchases();
      ylog('sdk', 'getPurchases: ' + arr.length + ' free items');
      return Promise.resolve(arr);
    };
    payments.consumePurchase = function (token) {
      var arr = readFreePurchases().filter(function (p) { return p.purchaseToken !== token; });
      writeFreePurchases(arr);
      return Promise.resolve();
    };
    // Leave getCatalog as-is — the real product list is informational only;
    // games iterate it to render the buy menu and call purchase(id) on tap.
    // If the real call fails (e.g. payments not initialized), provide an
    // empty-but-valid response so the menu just shows nothing.
    var origGetCatalog = payments.getCatalog;
    payments.getCatalog = function () {
      if (typeof origGetCatalog !== 'function') return Promise.resolve([]);
      return origGetCatalog.apply(this, arguments).catch(function () { return []; });
    };
  }

  function makePatched() {
    if (patchedCache || !real) return patchedCache;
    var proto = Object.getPrototypeOf(real) || Object.prototype;
    var p = Object.create(proto);
    for (var k in real) {
      try { p[k] = real[k]; } catch (_) {}
    }
    p.init = function (opts) {
      var optsDump;
      try { optsDump = JSON.stringify(opts || {}).slice(0, 120); } catch (_) { optsDump = '<unstringifiable>'; }
      ylog('sdk', 'YaGames.init begin opts=' + optsDump);
      var t0 = Date.now();
      return real.init.call(real, opts).then(function (ysdk) {
        ylog('sdk', 'YaGames.init resolved in ' + (Date.now() - t0) + 'ms');
        try { patchAdv(ysdk && ysdk.adv); } catch (_) {}
        // Wrap getPayments so the returned Payments object grants every
        // purchase for free without a real Yandex Plus / RU Bank check.
        try {
          if (ysdk && typeof ysdk.getPayments === 'function') {
            var origGetPayments = ysdk.getPayments.bind(ysdk);
            ysdk.getPayments = function () {
              return origGetPayments.apply(this, arguments).then(function (payments) {
                try { patchPayments(payments); } catch (_) {}
                return payments;
              }).catch(function () {
                // Real getPayments rejected (sometimes when the SDK can't
                // reach Yandex's payment backend). Hand the game a fully
                // stubbed payments object so it can keep granting items.
                var stub = {};
                patchPayments(stub);
                stub.getCatalog = function () { return Promise.resolve([]); };
                return stub;
              });
            };
          }
        } catch (_) {}
        return ysdk;
      }).catch(function (err) {
        ylog('sdk', 'YaGames.init REJECTED in ' + (Date.now() - t0) + 'ms: ' + (err && err.message || err));
        throw err;
      });
    };
    patchedCache = p;
    return p;
  }

  var __yga_get_count__ = 0;
  Object.defineProperty(window, 'YaGames', {
    configurable: true,
    get: function () {
      __yga_get_count__++;
      if (__yga_get_count__ <= 3) {
        ylog('sdk', 'YaGames get #' + __yga_get_count__ + ' real=' + (real ? typeof real : 'null') +
                    ' init=' + (real && typeof real.init));
      }
      return real ? makePatched() : undefined;
    },
    set: function (v) {
      var t = (v && typeof v) || 'null';
      var hasInit = !!(v && typeof v.init === 'function');
      ylog('sdk', 'YaGames set: ' + t + ' hasInit=' + hasInit);
      real = v;
      patchedCache = null;
    },
  });
})();
