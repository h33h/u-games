(function installInWindow(win) {
  'use strict';
  if (win.__UGamesAdapter && win.__UGamesAdapter.version === 1) return;
  const state = { version: 1, status: 'waiting', intercepted: { fullscreen: 0, rewarded: 0, banner: 0, portal: 0 }, callbackErrors: 0 };
  Object.defineProperty(win, '__UGamesAdapter', { value: state, configurable: false });
  const initSeen = new WeakSet();
  const providersSeen = new WeakSet();
  const watched = new WeakMap();
  const objectAPI = win.Object || Object;
  const reflectAPI = win.Reflect || Reflect;
  const defineProperty = objectAPI.defineProperty;

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
  function unsupported() {
    if (state.status !== 'unsupported') {
      state.status = 'unsupported';
      try {
        if (win.__UGamesProtection && typeof win.__UGamesProtection.unsupported === 'function') {
          win.__UGamesProtection.unsupported();
        } else if (win.webkit && win.webkit.messageHandlers && win.webkit.messageHandlers.ugamesProtection) {
          win.webkit.messageHandlers.ugamesProtection.postMessage('unsupported');
        }
      } catch (_) {}
      if (typeof win.stop === 'function') win.stop();
    }
    throw new Error('UGames cannot protect this advertisement interface');
  }
  function patchSdk(sdk) {
    if (!sdk || !sdk.adv) return sdk;
    try {
      const adv = sdk.adv;
      for (const [name, replacement] of [
        ['showFullscreenAdv', completeFullscreen],
        ['showRewardedVideo', completeRewarded],
        ['showBannerAdv', bannerHidden],
        ['hideBannerAdv', bannerHidden],
        ['getBannerAdvStatus', bannerHidden],
      ]) {
        if (typeof adv[name] === 'function' && adv[name] !== replacement) {
          adv[name] = replacement;
          if (adv[name] !== replacement) throw new Error('immutable advertisement API');
        }
      }
      state.status = 'active';
    } catch (_) { unsupported(); }
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
  // Preserve descriptor semantics while protecting synchronous SDK publication.
  // Only the two observed properties are transformed; unrelated definitions pass through.
  function protectedDescriptor(object, key, descriptor) {
    const transform = watched.get(object)?.get(key);
    if (!transform) return descriptor;
    const result = { ...descriptor };
    if ('value' in result) result.value = transform(result.value);
    if (typeof result.get === 'function') {
      const get = result.get;
      result.get = function () { return transform(get.call(this)); };
    }
    return result;
  }
  objectAPI.defineProperty = function (object, key, descriptor) {
    return defineProperty(object, key, protectedDescriptor(object, key, descriptor));
  };
  const defineProperties = objectAPI.defineProperties;
  objectAPI.defineProperties = function (object, descriptors) {
    const protectedProperties = {};
    for (const key of reflectAPI.ownKeys(descriptors)) {
      if (Object.prototype.propertyIsEnumerable.call(descriptors, key)) {
        defineProperty(protectedProperties, key, { value: protectedDescriptor(object, key, descriptors[key]), enumerable: true });
      }
    }
    return defineProperties(object, protectedProperties);
  };
  const reflectDefine = reflectAPI.defineProperty;
  reflectAPI.defineProperty = function (object, key, descriptor) {
    return reflectDefine(object, key, protectedDescriptor(object, key, descriptor));
  };
  function observeProperty(object, key, transform) {
    let properties = watched.get(object);
    if (!properties) { properties = new Map(); watched.set(object, properties); }
    properties.set(key, transform);
    const descriptor = Object.getOwnPropertyDescriptor(object, key);
    if (descriptor && !descriptor.configurable) {
      const original = object[key];
      const replacement = transform(original);
      if (replacement !== original) {
        try { object[key] = replacement; } catch (_) { unsupported(); }
        if (object[key] !== replacement) unsupported();
      }
      return;
    }
    let current = descriptor && descriptor.get ? descriptor.get.call(object) : object[key];
    current = transform(current);
    defineProperty(object, key, {
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
      observeProperty(provider, 'init', wrapInit);
      providersSeen.add(provider);
    }
    if (typeof provider.init === 'function') {
      const original = provider.init;
      const replacement = wrapInit(original);
      if (original !== replacement) {
        try { provider.init = replacement; } catch (_) { unsupported(); }
        if (provider.init !== replacement) unsupported();
      }
    }
    return provider;
  }
  observeProperty(win, 'YaGames', hookProvider);
  hookProvider(win.YaGames);
  let timer = win.setInterval(function () { hookProvider(win.YaGames); }, 250);
  if (typeof win.addEventListener === 'function') {
    win.addEventListener('pagehide', function () { win.clearInterval(timer); timer = null; });
    win.addEventListener('pageshow', function () {
      if (timer === null) timer = win.setInterval(function () { hookProvider(win.YaGames); }, 250);
    });
  }
  const rules = win.__UGamesRules;
  if (typeof win.open === 'function') {
    const originalOpen = win.open;
    try {
      win.open = function open() {
        const popup = originalOpen.apply(this, arguments);
        const destination = arguments[0];
        if (popup && (destination == null || destination === '' || String(destination).startsWith('about:blank'))) {
          try {
            if (rules && !popup.__UGamesRules) popup.__UGamesRules = rules;
            installInWindow(popup);
          } catch (_) { /* Cross-origin windows remain protected by native document-start injection. */ }
        }
        return popup;
      };
    } catch (_) {}
  }
  const doc = win.document;
  if (rules && doc && typeof win.MutationObserver === 'function') {
    const dismissedShadows = new WeakSet();
    const dismissedPortalRoots = new WeakSet();
    function observeAdvertisingShadow(root) {
      function suppressShadowAd() {
        const marker = root.querySelector('a[href*="/socialads-transparency-report"], a[href^="https://yandex.ru/an/count/"]');
        if (!marker) return;
        const container = root.host.closest('.csr-uniq1') || root.host;
        container.style.setProperty('display', 'none', 'important');
        container.style.setProperty('visibility', 'hidden', 'important');
        const close = root.querySelector('[data-fullscreen-element="close"]');
        if (close && !dismissedShadows.has(root)) {
          dismissedShadows.add(root);
          state.intercepted.portal++;
          close.click();
        }
      }
      const observer = new win.MutationObserver(suppressShadowAd);
      observer.observe(root, { childList: true, subtree: true, attributes: true, attributeFilter: ['href', 'data-fullscreen-element'] });
      suppressShadowAd();
    }
    if (win.Element && typeof win.Element.prototype.attachShadow === 'function') {
      const originalAttach = win.Element.prototype.attachShadow;
      win.Element.prototype.attachShadow = function attachShadow(options) {
        const root = originalAttach.call(this, options);
        observeAdvertisingShadow(root);
        return root;
      };
    }
    function suppressPortalAds() {
      for (const root of doc.querySelectorAll('[data-fullscreen-element="root"]')) {
        const marker = root.querySelector('a[href*="/games/_crpd/"], a[href*="/socialads-transparency-report"], a[href^="https://yandex.ru/an/count/"]');
        if (!marker) continue;
        root.style.setProperty('visibility', 'hidden', 'important');
        root.style.setProperty('display', 'none', 'important');
        const close = root.querySelector('[data-fullscreen-element="close"]');
        if (close && !dismissedPortalRoots.has(root)) {
          dismissedPortalRoots.add(root);
          state.intercepted.portal++;
          close.click();
        }
      }
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
    observer.observe(doc, { subtree: true, childList: true, attributes: true, attributeFilter: ['class', 'href', 'data-fullscreen-element'] });
    suppressPortalAds();
  }
})(window);
