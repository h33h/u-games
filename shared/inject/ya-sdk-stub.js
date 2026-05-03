// Layer 2: SDK stub. Inject in iframe (app-*.games.s3.yandex.net) at documentStart.
// Catches direct calls to ysdk.adv.* from inside the game bundle and replies
// with onClose(false) so the game thinks an ad was attempted but skipped.
// Wraps real YaGames so non-adv methods (player, storage, getStorage, environment,
// auth, payments, leaderboards, features.*) keep working unchanged.
(function () {
  // Origin guard: only run inside game iframes, no-op on yandex.com itself
  try {
    if (location.host.indexOf('games.s3.yandex.net') === -1) return;
  } catch (_) { return; }

  if (window.__yga_stub__) return;
  window.__yga_stub__ = true;

  // Build flag: 'skip' (don't grant rewards) or 'auto' (always grant)
  var REWARDED_MODE = 'skip';

  var real = undefined;
  var patchedCache = null;

  function patchAdv(adv) {
    if (!adv) return;
    adv.showFullscreenAdv = function (opts) {
      var cb = (opts && opts.callbacks) || {};
      try { cb.onOpen && cb.onOpen(); } catch (_) {}
      Promise.resolve().then(function () { try { cb.onClose && cb.onClose(false); } catch (_) {} });
    };
    adv.showRewardedVideo = function (opts) {
      var cb = (opts && opts.callbacks) || {};
      try { cb.onOpen && cb.onOpen(); } catch (_) {}
      if (REWARDED_MODE === 'auto') {
        try { cb.onRewarded && cb.onRewarded(); } catch (_) {}
      } else {
        try { cb.onError && cb.onError({ code: 'NO_REWARD' }); } catch (_) {}
      }
      Promise.resolve().then(function () { try { cb.onClose && cb.onClose(false); } catch (_) {} });
    };
    adv.showBannerAdv = function () { return Promise.resolve({ stickyAdvIsShowing: false, reason: 'OK' }); };
    adv.hideBannerAdv = function () { return Promise.resolve({ stickyAdvIsShowing: false }); };
    adv.getBannerAdvStatus = function () { return Promise.resolve({ stickyAdvIsShowing: false }); };
  }

  function makePatched() {
    if (patchedCache || !real) return patchedCache;
    var proto = Object.getPrototypeOf(real) || Object.prototype;
    var p = Object.create(proto);
    for (var k in real) {
      try { p[k] = real[k]; } catch (_) {}
    }
    p.init = function (opts) {
      return real.init.call(real, opts).then(function (ysdk) {
        try { patchAdv(ysdk && ysdk.adv); } catch (_) {}
        return ysdk;
      });
    };
    patchedCache = p;
    return p;
  }

  Object.defineProperty(window, 'YaGames', {
    configurable: true,
    get: function () { return real ? makePatched() : undefined; },
    set: function (v) { real = v; patchedCache = null; }
  });
})();
