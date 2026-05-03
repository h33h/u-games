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

  // Re-attach if React removes the tag during reconciliation.
  if (typeof MutationObserver === 'function' && document.documentElement) {
    new MutationObserver(function () {
      ensureStyleTag();
    }).observe(document.documentElement, { childList: true, subtree: true });
  } else {
    setInterval(ensureStyleTag, 250);
  }
})();
