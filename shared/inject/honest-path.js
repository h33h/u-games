// Layer 1: honest-path. Inject in main frame (yandex.com) at documentStart.
// Hooks JSON.parse so when React reads __appData__/__playPageData__ scripts,
// we rewrite the ad-related fields BEFORE the frontend acts on them.
// Result: Yandex's own frontend skips loading GPT/Prebid/sticky banner.
(function () {
  if (window.__yga_honest_path__) return;
  window.__yga_honest_path__ = true;

  var origParse = JSON.parse;
  JSON.parse = function (text, reviver) {
    var result = origParse.call(this, text, reviver);
    try {
      if (result && typeof result === 'object') {
        // __appData__ shape: has advPartnerInfo
        if (result.advPartnerInfo) {
          result.advPartnerInfo.advEnabledByPartner = false;
          result.advPartnerInfo.blockedPlacements = 99;
          result.advPartnerInfo.advDelay = 0;
          result.allAdvBlocks = {};
          if (Array.isArray(result.featureFlags)) {
            result.featureFlags = result.featureFlags.filter(function (f) {
              return typeof f === 'string' && f.indexOf('adv_') === -1 && f.indexOf('adblock_') === -1;
            });
          }
          if (result.clientFeatures) {
            result.clientFeatures.isDistrib = true;
          }
        }
        // __playPageData__ shape: has playerInfo with hasYaPlus
        if (result.playerInfo && 'hasYaPlus' in result.playerInfo) {
          result.playerInfo.hasYaPlus = true;
          if ('isAdvStickyBannerEnabled' in result) result.isAdvStickyBannerEnabled = false;
          if (result.request) {
            result.request.withWorldWideAdv = false;
            // Do NOT force isPWA = true here. Yandex's SSR uses isPWA to
            // decide how to construct __playPageData__.gameSrc.
            result.request.hidePaymentsAndCurrency = true;
          }
          // Yandex's MOBILE SSR omits the `?sdk=/sdk/_/v2.<hash>.js` query
          // from gameSrc (it expects the Yandex Games PWA / native app to
          // inject the SDK natively). Our WebView wrapper isn't that PWA,
          // so without the query the iframe never loads YaGames and any
          // SDK-using title (Construct 3 / GamePush titles like 388978)
          // crashes on `YaGames.init`. We re-add the query using sdkHash
          // from playPageData. Desktop SSR already includes `?sdk=`, in
          // which case our `indexOf('sdk=') === -1` guard skips the patch.
          try {
            var src = result.gameSrc;
            var hash = result.sdkHash;
            if (typeof src === 'string' && hash && src.indexOf('sdk=') === -1) {
              var sdkPath = '/sdk/_/v2.' + hash + '.js';
              var hashIdx = src.indexOf('#');
              var base = hashIdx >= 0 ? src.substring(0, hashIdx) : src;
              var frag = hashIdx >= 0 ? src.substring(hashIdx) : '';
              var sep = base.indexOf('?') >= 0 ? '&' : '?';
              result.gameSrc = base + sep + 'sdk=' + encodeURIComponent(sdkPath) + frag;
              try {
                if (typeof window.__yga_log === 'function') {
                  window.__yga_log('sdk', 'gameSrc patched: ?sdk=' + sdkPath);
                }
              } catch (_) {}
            }
          } catch (_) {}
          // Extract Yandex's authoritative orientation hint. Lives at
          // __playPageData__.gameData.features.orientation (and a duplicate
          // at gameSettings.features.orientation). Values observed:
          // "landscape" / "portrait" / undefined-for-rotatable-games.
          // The native shell shows the rotate-overlay based on this.
          try {
            var orientHint =
              (result.gameData && result.gameData.features && result.gameData.features.orientation) ||
              (result.gameSettings && result.gameSettings.features && result.gameSettings.features.orientation);
            if (orientHint && typeof window.__yga_log === 'function') {
              window.__yga_log('orient', String(orientHint) + ' (playPageData.features)');
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
    return result;
  };
})();
