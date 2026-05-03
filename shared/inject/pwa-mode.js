// Layer: PWA-mode hints. Inject in main frame at documentStart.
// Reports the page as standalone PWA so Yandex's frontend (and games that check
// display-mode) treat the WebView as an installed PWA.
(function () {
  if (window.__yga_pwa_mode__) return;
  window.__yga_pwa_mode__ = true;

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
})();
