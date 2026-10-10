(function installInWindow(win) {
  'use strict';
  if (win.__UGamesAdapter && win.__UGamesAdapter.version === 1) return;
  const state = { version: 1, status: 'waiting', intercepted: { fullscreen: 0, rewarded: 0, banner: 0 }, callbackErrors: 0 };
  Object.defineProperty(win, '__UGamesAdapter', { value: state, configurable: false });
  const sdkSeen = new WeakSet();
  const initSeen = new WeakSet();
  const providersSeen = new WeakSet();

  function invoke(callbacks, name, value) {
    if (!callbacks || typeof callbacks[name] !== 'function') return;
    try { callbacks[name](value); } catch (_) { state.callbackErrors++; }
  }
  function completeFullscreen(options) {
    state.intercepted.fullscreen++;
    const callbacks = options && (options.callbacks || options);
    win.setTimeout(function () { invoke(callbacks, 'onClose', false); }, 0);
  }
  function completeRewarded(options) {
    state.intercepted.rewarded++;
    const callbacks = options && (options.callbacks || options);
    win.setTimeout(function () {
      invoke(callbacks, 'onOpen');
      invoke(callbacks, 'onRewarded');
      invoke(callbacks, 'onClose', true);
    }, 0);
  }
  function bannerHidden() {
    state.intercepted.banner++;
    return Promise.resolve({ stickyAdvIsShowing: false });
  }
  function patchSdk(sdk) {
    if (!sdk || !sdk.adv || sdkSeen.has(sdk)) return sdk;
    try {
      const adv = sdk.adv;
      for (const [name, replacement] of [
        ['showFullscreenAdv', completeFullscreen],
        ['showRewardedVideo', completeRewarded],
        ['showBannerAdv', bannerHidden],
        ['hideBannerAdv', bannerHidden],
        ['getBannerAdvStatus', bannerHidden],
      ]) {
        if (typeof adv[name] === 'function') {
          adv[name] = replacement;
          if (adv[name] !== replacement) throw new Error('immutable advertisement API');
        }
      }
      sdkSeen.add(sdk);
      state.status = 'active';
    } catch (_) {
      state.status = 'unsupported';
    }
    return sdk;
  }
  function wrapInit(original) {
    if (typeof original !== 'function' || initSeen.has(original)) return original;
    function init() {
      const result = original.apply(this, arguments);
      return result && typeof result.then === 'function' ? result.then(patchSdk) : patchSdk(result);
    }
    initSeen.add(init);
    return init;
  }
  function observeProperty(object, key, transform) {
    const descriptor = Object.getOwnPropertyDescriptor(object, key);
    if (descriptor && (!descriptor.configurable || descriptor.writable === false)) {
      if (typeof object[key] === 'function') {
        try { object[key] = transform(object[key]); } catch (_) {}
      }
      return;
    }
    let current = descriptor && descriptor.get ? descriptor.get.call(object) : object[key];
    current = transform(current);
    Object.defineProperty(object, key, {
      configurable: true,
      enumerable: descriptor ? descriptor.enumerable : true,
      get() { return descriptor && descriptor.get ? transform(descriptor.get.call(object)) : current; },
      set(value) {
        if (descriptor && descriptor.set) descriptor.set.call(object, value);
        else current = transform(value);
      },
    });
  }
  function hookProvider(provider) {
    if (!provider || (typeof provider !== 'object' && typeof provider !== 'function')) return provider;
    if (!providersSeen.has(provider)) {
      providersSeen.add(provider);
      try { observeProperty(provider, 'init', wrapInit); } catch (_) {}
    }
    if (typeof provider.init === 'function') {
      try { provider.init = wrapInit(provider.init); } catch (_) {}
    }
    return provider;
  }
  try { observeProperty(win, 'YaGames', hookProvider); } catch (_) {}
  hookProvider(win.YaGames);
  let timer = win.setInterval(function () { hookProvider(win.YaGames); }, 250);
  if (typeof win.addEventListener === 'function') {
    win.addEventListener('pagehide', function () { win.clearInterval(timer); timer = null; });
    win.addEventListener('pageshow', function () {
      if (timer === null) timer = win.setInterval(function () { hookProvider(win.YaGames); }, 250);
    });
  }
  const rules = win.__UGamesRules;
  const doc = win.document;
  if (rules && doc && typeof win.MutationObserver === 'function') {
    function suppressPortalAds() {
      const close = doc.querySelector('.play-modal.adv-focusable.play-modal_visible .close-button_type_adv-fullscreen');
      if (close) close.click();
      for (const selector of rules.hiddenSelectors) {
        for (const element of doc.querySelectorAll(selector)) {
          element.style.setProperty('display', 'none', 'important');
          element.style.setProperty('visibility', 'hidden', 'important');
        }
      }
    }
    const observer = new win.MutationObserver(suppressPortalAds);
    observer.observe(doc, { subtree: true, childList: true, attributes: true, attributeFilter: ['class'] });
    suppressPortalAds();
  }
})(window);
