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
            // decide how to construct __playPageData__.gameSrc — when
            // isPWA is true, the iframe URL is emitted without the
            // `?sdk=/sdk/_/v2.xxx.js` query parameter (the assumption
            // being that a real PWA install would host the SDK locally).
            // Without that query the iframe HTML never injects the
            // YaGames SDK <script> tag, window.YaGames is never assigned,
            // and any title that uses the SDK (Construct 3 / GamePush
            // games like 388978) crashes on YaGames.init.
            result.request.hidePaymentsAndCurrency = true;
          }
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
