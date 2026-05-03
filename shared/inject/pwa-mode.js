// Layer: PWA-mode hints + RESILIENT CSS loader. Inject in main frame at
// documentStart.
//
// Why this is more involved than a one-liner: Yandex Games' React runtime
// sometimes garbage-collects DOM nodes that aren't part of its virtual tree,
// including a freshly-created <style> we attach. To survive that we use
// document.adoptedStyleSheets (untouchable by React) AND a MutationObserver
// that re-attaches a backup <style> tag whenever it disappears.
(function () {
  if (window.__yga_pwa_mode__) return;
  window.__yga_pwa_mode__ = true;

  // standalone display-mode media-query override so games and the wrapper
  // think we're a real PWA install.
  var orig = window.matchMedia ? window.matchMedia.bind(window) : null;
  if (orig) {
    window.matchMedia = function (q) {
      if (typeof q === 'string' &&
          (q.indexOf('display-mode: standalone') !== -1 ||
           q.indexOf('display-mode: fullscreen') !== -1 ||
           q.indexOf('display-mode: minimal-ui') !== -1)) {
        return {
          matches: true, media: q, onchange: null,
          addEventListener: function () {}, removeEventListener: function () {},
          addListener: function () {}, removeListener: function () {},
          dispatchEvent: function () { return true; }
        };
      }
      return orig(q);
    };
  }

  try {
    Object.defineProperty(window.navigator, 'standalone', {
      configurable: true,
      get: function () { return true; }
    });
  } catch (_) {}

  // The PWA-CSS payload is concatenated into this stub by the platform
  // injector right before the IIFE. We expose it here as a local symbol so
  // both adoptedStyleSheets and the <style>-tag fallback can use it.
  var CSS = window.__yga_pwa_css_payload__ || '';

  function adopt() {
    if (typeof CSSStyleSheet === 'undefined' || !document.adoptedStyleSheets) return false;
    try {
      var sheet = new CSSStyleSheet();
      sheet.replaceSync(CSS);
      document.adoptedStyleSheets = [].concat(document.adoptedStyleSheets || [], [sheet]);
      return true;
    } catch (_) { return false; }
  }

  var STYLE_ID = '__yga_pwa_style__';
  function ensureStyleTag() {
    if (document.getElementById(STYLE_ID)) return;
    var head = document.head || document.documentElement;
    if (!head) return;
    var s = document.createElement('style');
    s.id = STYLE_ID;
    s.textContent = CSS;
    head.appendChild(s);
  }

  adopt();
  ensureStyleTag();

  // Auto-dismiss the .app-drawer "Play now" intermediate sheet. CSS already
  // hides the visual chrome, but the React state for the drawer stays "open"
  // and may keep adding/removing siblings. Programmatically clicking the
  // primary CTA inside the drawer is what actually removes the node.
  // Locale-agnostic: grab the largest visible <button> inside the drawer
  // (the CTA is always full-width, ~360px on mobile).
  function autoDismissDrawer() {
    var drawer = document.querySelector('.app-drawer');
    if (!drawer) return;
    var buttons = drawer.querySelectorAll('button');
    var best = null;
    var bestWidth = 0;
    for (var i = 0; i < buttons.length; i++) {
      var b = buttons[i];
      var w = b.offsetWidth || 0;
      if (w > bestWidth && w >= 200) { best = b; bestWidth = w; }
    }
    if (best) { try { best.click(); } catch (_) {} }
  }

  // Re-attach style + try to auto-dismiss the drawer on every DOM change.
  // MutationObserver fires very frequently during React boot, so debounce
  // dismiss attempts via rAF.
  var dismissPending = false;
  function scheduleDismiss() {
    if (dismissPending) return;
    dismissPending = true;
    requestAnimationFrame(function () {
      dismissPending = false;
      autoDismissDrawer();
    });
  }

  if (typeof MutationObserver === 'function' && document.documentElement) {
    new MutationObserver(function () {
      ensureStyleTag();
      scheduleDismiss();
    }).observe(document.documentElement, { childList: true, subtree: true });
  } else {
    setInterval(function () { ensureStyleTag(); autoDismissDrawer(); }, 250);
  }
})();
