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
            result.request.isPWA = true;
            result.request.hidePaymentsAndCurrency = true;
          }
        }
      }
    } catch (_) {}
    return result;
  };
})();
