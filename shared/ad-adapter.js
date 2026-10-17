(function installInWindow(win) {
  'use strict';
  if (win.__UGamesAdapter && win.__UGamesAdapter.version === 1) {
    return;
  }
  const state = {
    version: 1,
    status: 'waiting',
    intercepted: { fullscreen: 0, rewarded: 0, banner: 0, portal: 0, purchase: 0 },
    callbackErrors: 0,
    payments: {
      mode: 'local-free',
      signedRequested: false,
      signatureAvailable: false,
      storage: 'memory',
      consumed: 0,
      lastError: null,
    },
  };
  Object.defineProperty(win, '__UGamesAdapter', { value: state, configurable: false });
  const initSeen = new WeakSet();
  const providersSeen = new WeakSet();
  const paymentSdks = new WeakMap();
  const paymentLedgers = new Map();
  const watched = new WeakMap();
  const objectAPI = win.Object || Object;
  const reflectAPI = win.Reflect || Reflect;
  const defineProperty = objectAPI.defineProperty;

  function invoke(callbacks, name, value) {
    if (!callbacks || typeof callbacks[name] !== 'function') {
      return;
    }
    try {
      callbacks[name](value);
    } catch (_) {
      state.callbackErrors++;
    }
  }
  function completeFullscreen(options) {
    state.intercepted.fullscreen++;
    const callbacks = options && (options.callbacks || options);
    win.setTimeout(function () {
      invoke(callbacks, 'onClose', false);
    }, 0);
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
  function unsupported(interfaceName = 'advertisement') {
    if (state.status !== 'unsupported') {
      state.status = 'unsupported';
      try {
        if (win.__UGamesProtection && typeof win.__UGamesProtection.unsupported === 'function') {
          win.__UGamesProtection.unsupported();
        } else if (
          win.webkit &&
          win.webkit.messageHandlers &&
          win.webkit.messageHandlers.ugamesProtection
        ) {
          win.webkit.messageHandlers.ugamesProtection.postMessage('unsupported');
        }
      } catch (_) {}
      if (typeof win.stop === 'function') {
        win.stop();
      }
    }
    throw new Error('UGames cannot protect this ' + interfaceName + ' interface');
  }
  // Match the SDK's purchaseData/getter/toJSON contract without manufacturing a signature.
  class LocalPurchase {
    constructor(receipt) {
      this.purchaseData = { ...receipt };
    }
    get productID() {
      return this.purchaseData.productID;
    }
    get purchaseToken() {
      return this.purchaseData.purchaseToken;
    }
    get developerPayload() {
      return this.purchaseData.developerPayload;
    }
    toJSON() {
      return { ...this.purchaseData };
    }
  }
  function paymentError(code, message) {
    state.payments.lastError = code;
    const error = new Error(message);
    error.code = code;
    return error;
  }
  function protectPayments(sdk, signed) {
    state.payments.signedRequested ||= !!signed;
    let config = paymentSdks.get(sdk);
    if (!config) {
      const game = sdk.environment?.app?.id || win.location?.hostname || 'default';
      const key = 'ugames.free-purchases.v1.' + game;
      let ledger = paymentLedgers.get(key);
      if (!ledger) {
        let purchases = [];
        try {
          const saved = JSON.parse(win.localStorage.getItem(key) || '[]');
          if (Array.isArray(saved)) {
            purchases = saved.filter(
              (item) =>
                item &&
                typeof item.productID === 'string' &&
                typeof item.purchaseToken === 'string' &&
                item.purchaseToken.startsWith('ugames-free-') &&
                typeof item.developerPayload === 'string',
            );
          }
          state.payments.storage = 'persistent';
        } catch (_) {}
        ledger = { purchases, sequence: 0, pending: new Map() };
        paymentLedgers.set(key, ledger);
      }
      config = {
        facades: new WeakMap(),
        local: new WeakMap(),
        getPaymentsSeen: new WeakSet(),
        availabilitySeen: new WeakSet(),
      };
      paymentSdks.set(sdk, config);
      function save() {
        try {
          win.localStorage.setItem(key, JSON.stringify(ledger.purchases));
          state.payments.storage = 'persistent';
          ledger.pending.clear();
        } catch (_) {
          state.payments.storage = 'memory';
        }
      }
      function withLedger(action) {
        function run() {
          try {
            const saved = JSON.parse(win.localStorage.getItem(key) || '[]');
            if (Array.isArray(saved)) {
              const current = new Map();
              for (const receipt of saved) {
                if (
                  receipt &&
                  typeof receipt.productID === 'string' &&
                  typeof receipt.purchaseToken === 'string' &&
                  receipt.purchaseToken.startsWith('ugames-free-') &&
                  typeof receipt.developerPayload === 'string'
                ) {
                  current.set(receipt.purchaseToken, receipt);
                }
              }
              // Retain local changes if a previous storage write failed.
              for (const [token, receipt] of ledger.pending) {
                if (receipt) {
                  current.set(token, receipt);
                } else {
                  current.delete(token);
                }
              }
              ledger.purchases = Array.from(current.values());
            }
          } catch (_) {}
          return action();
        }
        const locks = win.navigator?.locks;
        if (typeof locks?.request === 'function') {
          let entered = false;
          return locks
            .request(key, () => {
              entered = true;
              return run();
            })
            .catch((error) => {
              if (entered) {
                throw error;
              }
              return run();
            });
        }
        return run();
      }
      function createFacade(loadCatalog) {
        const methods = {
          async purchase(data) {
            if (typeof data === 'string') {
              data = { id: data };
            }
            if (!data || typeof data.id !== 'string' || !data.id.trim()) {
              throw paymentError('INVALID_PRODUCT_ID', 'UGames purchase requires a product ID');
            }
            const payload = data.developerPayload || '';
            if (typeof payload !== 'string') {
              throw paymentError('INVALID_DEVELOPER_PAYLOAD', 'developerPayload must be a string');
            }
            return withLedger(() => {
              const unique = win.crypto?.randomUUID
                ? win.crypto.randomUUID()
                : Date.now() + '-' + ++ledger.sequence + '-' + Math.random().toString(36).slice(2);
              const receipt = {
                productID: data.id,
                purchaseToken: 'ugames-free-' + unique,
                developerPayload: payload,
              };
              ledger.purchases.push(receipt);
              ledger.pending.set(receipt.purchaseToken, receipt);
              save();
              state.intercepted.purchase++;
              state.payments.lastError = null;
              return new LocalPurchase(receipt);
            });
          },
          async getPurchases() {
            return withLedger(() => ledger.purchases.map((receipt) => new LocalPurchase(receipt)));
          },
          async consumePurchase(token) {
            return withLedger(() => {
              const index = ledger.purchases.findIndex(
                (receipt) => receipt.purchaseToken === token,
              );
              if (index < 0) {
                throw paymentError('UNKNOWN_LOCAL_PURCHASE', 'Unknown UGames local purchase');
              }
              ledger.purchases.splice(index, 1);
              ledger.pending.set(token, null);
              save();
              state.payments.consumed++;
              state.payments.lastError = null;
            });
          },
          async getCatalog() {
            try {
              const products = await loadCatalog();
              return products.map((product) => ({
                ...product,
                id: product.id,
                title: product.title,
                description: product.description,
                imageURI: product.imageURI,
                priceCurrencyCode: product.priceCurrencyCode,
                price: 'Бесплатно',
                priceValue: '0',
                getPriceCurrencyImage: (...args) =>
                  typeof product.getPriceCurrencyImage === 'function'
                    ? product.getPriceCurrencyImage.apply(product, args)
                    : '',
              }));
            } catch (error) {
              state.payments.lastError = 'CATALOG_UNAVAILABLE';
              throw error;
            }
          },
        };
        const facade = { ...methods };
        config.local.set(facade, methods);
        return facade;
      }
      function patchPayments(payments) {
        if (!payments || typeof payments !== 'object') {
          return payments;
        }
        const methods = config.local.get(payments);
        if (methods) {
          // Restore local entry points if a game republishes or overwrites its payment API.
          for (const [name, replacement] of Object.entries(methods)) {
            if (payments[name] !== replacement) {
              try {
                payments[name] = replacement;
                if (payments[name] !== replacement) {
                  throw new Error('immutable local payment API');
                }
              } catch (_) {
                state.payments.lastError = 'IMMUTABLE_PAYMENT_API';
                unsupported('payment');
              }
            }
          }
          return payments;
        }
        let facade = config.facades.get(payments);
        if (!facade) {
          facade = createFacade(() => {
            if (typeof payments.getCatalog !== 'function') {
              throw paymentError('CATALOG_UNAVAILABLE', 'UGames product catalog is unavailable');
            }
            return payments.getCatalog();
          });
          config.facades.set(payments, facade);
        }
        return patchPayments(facade);
      }
      function wrapGetPayments(original) {
        if (typeof original !== 'function' || config.getPaymentsSeen.has(original)) {
          return original;
        }
        let fallback;
        function getPayments(options) {
          state.payments.signedRequested ||= !!(options?.signed ?? config.initSigned);
          const direct = patchPayments(sdk.payments);
          if (direct) {
            return Promise.resolve(direct);
          }
          if (!fallback) {
            const receiver = this,
              args = arguments;
            let catalogProvider;
            fallback = createFacade(async () => {
              // Only metadata needs the provider. Local purchase/consume never initialize payments.
              if (!catalogProvider) {
                catalogProvider = Promise.resolve().then(() => original.apply(receiver, args));
                catalogProvider = catalogProvider.catch((error) => {
                  catalogProvider = null;
                  throw error;
                });
              }
              const payments = await catalogProvider;
              return payments.getCatalog();
            });
          }
          return Promise.resolve(patchPayments(fallback));
        }
        config.getPaymentsSeen.add(getPayments);
        return getPayments;
      }
      function wrapAvailability(original) {
        if (typeof original !== 'function' || config.availabilitySeen.has(original)) {
          return original;
        }
        function isAvailableMethod(method) {
          if (
            [
              'getPayments',
              'payments.purchase',
              'payments.getPurchases',
              'payments.consumePurchase',
              'payments.getCatalog',
            ].includes(method)
          ) {
            return Promise.resolve(true);
          }
          return original.apply(this, arguments);
        }
        config.availabilitySeen.add(isAvailableMethod);
        return isAvailableMethod;
      }
      config.initSigned = !!signed;
      config.patch = patchPayments;
      observeProperty(sdk, 'payments', patchPayments);
      observeProperty(sdk, 'getPayments', wrapGetPayments);
      observeProperty(sdk, 'isAvailableMethod', wrapAvailability);
    }
    config.initSigned = !!signed;
    config.patch(sdk.payments);
  }
  function patchSdk(sdk, signed) {
    if (!sdk) {
      return sdk;
    }
    win.__UGamesOfflineRuntime?.trackSDK(sdk);
    try {
      protectPayments(sdk, signed);
    } catch (_) {
      unsupported('payment');
    }
    if (sdk.adv) {
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
            if (adv[name] !== replacement) {
              throw new Error('immutable advertisement API');
            }
          }
        }
      } catch (_) {
        unsupported();
      }
    }
    state.status = 'active';
    return sdk;
  }
  function wrapInit(original) {
    if (typeof original !== 'function' || initSeen.has(original)) {
      return original;
    }
    function init() {
      const result = original.apply(this, arguments);
      const signed = arguments[0]?.signed;
      const patch = (sdk) => patchSdk(sdk, signed);
      return result && typeof result.then === 'function' ? result.then(patch) : patch(result);
    }
    initSeen.add(init);
    return init;
  }
  // Preserve descriptor semantics while protecting synchronous SDK publication.
  // Only observed SDK properties are transformed; unrelated definitions pass through.
  function protectedDescriptor(object, key, descriptor) {
    const transform = watched.get(object)?.get(key);
    if (!transform) {
      return descriptor;
    }
    const result = { ...descriptor };
    if ('value' in result) {
      result.value = transform(result.value);
    }
    if (typeof result.get === 'function') {
      const get = result.get;
      result.get = function () {
        return transform(get.call(this));
      };
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
        defineProperty(protectedProperties, key, {
          value: protectedDescriptor(object, key, descriptors[key]),
          enumerable: true,
        });
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
    if (!properties) {
      properties = new Map();
      watched.set(object, properties);
    }
    properties.set(key, transform);
    const descriptor = Object.getOwnPropertyDescriptor(object, key);
    if (descriptor && !descriptor.configurable) {
      const original = object[key];
      const replacement = transform(original);
      if (replacement !== original) {
        try {
          object[key] = replacement;
        } catch (_) {
          unsupported();
        }
        if (object[key] !== replacement) {
          unsupported();
        }
      }
      return;
    }
    let current = descriptor && descriptor.get ? descriptor.get.call(object) : object[key];
    current = transform(current);
    defineProperty(object, key, {
      configurable: true,
      enumerable: descriptor ? descriptor.enumerable : true,
      get() {
        return descriptor && descriptor.get ? transform(descriptor.get.call(object)) : current;
      },
      set(value) {
        if (descriptor && descriptor.set) {
          descriptor.set.call(object, value);
        } else {
          current = transform(value);
        }
      },
    });
  }
  function hookProvider(provider) {
    if (!provider || (typeof provider !== 'object' && typeof provider !== 'function')) {
      return provider;
    }
    if (!providersSeen.has(provider)) {
      observeProperty(provider, 'init', wrapInit);
      providersSeen.add(provider);
    }
    if (typeof provider.init === 'function') {
      const original = provider.init;
      const replacement = wrapInit(original);
      if (original !== replacement) {
        try {
          provider.init = replacement;
        } catch (_) {
          unsupported();
        }
        if (provider.init !== replacement) {
          unsupported();
        }
      }
    }
    return provider;
  }
  observeProperty(win, 'YaGames', hookProvider);
  hookProvider(win.YaGames);
  let timer = win.setInterval(function () {
    hookProvider(win.YaGames);
  }, 250);
  if (typeof win.addEventListener === 'function') {
    win.addEventListener('pagehide', function () {
      win.clearInterval(timer);
      timer = null;
    });
    win.addEventListener('pageshow', function () {
      if (timer === null) {
        timer = win.setInterval(function () {
          hookProvider(win.YaGames);
        }, 250);
      }
    });
  }
  const rules = win.__UGamesRules;
  function allowedDestination(value, target, source) {
    if (value === 'about:blank') {
      return true;
    }
    try {
      const url = new win.URL(value, doc.baseURI);
      if (url.href === 'about:blank') {
        return true;
      }
      const offline = win.__UGamesOfflineConfig;
      if (offline) {
        const entry = new win.URL(offline.url);
        return (
          url.protocol === (offline.scheme || entry.protocol) &&
          url.hostname === entry.hostname &&
          !url.username &&
          !url.password &&
          !url.port &&
          (!target || ['_self', '_top', '_parent'].includes(target.toLowerCase()))
        );
      }
      if (url.protocol !== 'https:' || url.username || url.password || url.port) {
        return false;
      }
      if (
        (/^(?:www\.)?yandex\.(?:ru|com)$/.test(url.hostname) &&
          /^\/games(?:\/|$)/.test(url.pathname)) ||
        (/^passport\.yandex\.(?:ru|com)$/.test(url.hostname) &&
          /^\/(?:auth|registration|pwl-yandex)(?:\/|$)/.test(url.pathname)) ||
        (/^sso\.passport\.yandex\.(?:ru|com)$/.test(url.hostname) &&
          /^\/prepare\/?$/.test(url.pathname)) ||
        (url.hostname === 'sso.ya.ru' && /^\/sync\/?$/.test(url.pathname))
      ) {
        return true;
      }
      // A game may navigate within its own frame, but cannot replace the app surface.
      const localTarget = !target || target.toLowerCase() === '_self';
      if (localTarget && /\.(?:games\.yandex\.net|games\.s3\.yandex\.net)$/.test(url.hostname)) {
        return true;
      }
      const origin = new win.URL(source || doc.URL);
      return (
        localTarget &&
        url.origin === origin.origin &&
        !/^(?:(?:www|passport|sso\.passport)\.)?yandex\.(?:ru|com)$/.test(url.hostname) &&
        url.hostname !== 'sso.ya.ru'
      );
    } catch (_) {
      return false;
    }
  }
  if (typeof win.open === 'function') {
    const originalOpen = win.open;
    try {
      win.open = function open() {
        const destination = arguments[0];
        if (
          destination != null &&
          destination !== '' &&
          !allowedDestination(destination, '_blank')
        ) {
          return null;
        }
        const popup = originalOpen.apply(this, arguments);
        if (
          popup &&
          (destination == null ||
            destination === '' ||
            String(destination).startsWith('about:blank'))
        ) {
          try {
            if (rules && !popup.__UGamesRules) {
              popup.__UGamesRules = rules;
            }
            installInWindow(popup);
          } catch (_) {
            /* Cross-origin windows remain protected by native document-start injection. */
          }
        }
        return popup;
      };
    } catch (_) {}
  }
  const doc = win.document;
  if (doc && typeof doc.addEventListener === 'function') {
    if (win.navigation && typeof win.navigation.addEventListener === 'function') {
      win.navigation.addEventListener('navigate', function (event) {
        const main = win === win.top;
        const destination = event.destination.url;
        if (!main && destination === 'about:srcdoc') {
          return;
        }
        if (!allowedDestination(destination, main ? '_top' : '_self') && event.cancelable) {
          event.preventDefault();
        }
      });
    }
    const navigationRoots = new WeakSet();
    function protectNavigation(root) {
      if (navigationRoots.has(root)) {
        return;
      }
      navigationRoots.add(root);
      function intercept(event) {
        const path =
          typeof event.composedPath === 'function' ? event.composedPath() : [event.target];
        const element = path.find(
          (node) =>
            node.matches && node.matches(event.type === 'submit' ? 'form' : 'a[href],area[href]'),
        );
        if (!element) {
          return;
        }
        const form = event.type === 'submit';
        const submitter = form ? event.submitter : null;
        const value = form
          ? submitter?.hasAttribute('formaction')
            ? submitter.formAction ||
              new win.URL(submitter.getAttribute('formaction'), doc.baseURI).href
            : element.action
          : element.href;
        const target =
          (submitter?.getAttribute('formtarget') ?? element.target) ||
          doc.querySelector('base[target]')?.target ||
          '';
        if (!allowedDestination(value, target)) {
          event.preventDefault();
          event.stopImmediatePropagation();
        }
      }
      for (const event of ['click', 'auxclick', 'submit']) {
        root.addEventListener(event, intercept, true);
      }
    }
    protectNavigation(doc);
    if (win.HTMLFormElement) {
      const submit = win.HTMLFormElement.prototype.submit;
      win.HTMLFormElement.prototype.submit = function () {
        if (
          allowedDestination(this.action, this.target || doc.querySelector('base[target]')?.target)
        ) {
          return submit.apply(this, arguments);
        }
      };
    }
    if (win.Element && typeof win.Element.prototype.attachShadow === 'function') {
      const attachShadow = win.Element.prototype.attachShadow;
      win.Element.prototype.attachShadow = function (options) {
        const root = attachShadow.call(this, options);
        protectNavigation(root);
        return root;
      };
    }
    for (const element of doc.querySelectorAll('*')) {
      if (element.shadowRoot) {
        protectNavigation(element.shadowRoot);
      }
    }
  }
  // Change presentation only: SDK names, links, resource URLs and user input stay intact.
  if (
    doc &&
    typeof doc.createTreeWalker === 'function' &&
    typeof win.MutationObserver === 'function'
  ) {
    const brand =
      /(^|[^\p{L}\p{N}_@/.-])(?:яндекс(?:а|у|ом|е)?(?:[\s\u00a0.·-]+игр(?:ы|а|ах|ам|ами)?)?|yandex(?:[\s\u00a0.·-]+games)?)(?![\p{L}\p{N}_@/-]|\.[\p{L}\p{N}])/giu;
    const labels = ['title', 'alt', 'aria-label', 'aria-description', 'placeholder'];
    const logoContainer = '.logo-link,.logotype,.domain-logo';
    const skipped =
      'script,style,noscript,textarea,input,[contenteditable]:not([contenteditable="false"])';
    const observedRoots = new WeakSet();
    const brandedImages = new WeakSet();
    const brandedGraphics = new WeakSet();
    const logo =
      win.__UGamesBranding?.assets.logo ||
      'data:image/svg+xml,' +
        encodeURIComponent(
          '<svg xmlns="http://www.w3.org/2000/svg" width="140" height="32" viewBox="0 0 140 32"><text x="2" y="24" fill="#888888" font-family="system-ui,sans-serif" font-size="26" font-weight="700">UGames</text></svg>',
        );
    function brandText(value) {
      return value.replace(brand, '$1UGames');
    }
    function isLogoURL(value) {
      try {
        const url = new win.URL(value, doc.baseURI);
        return (
          (url.hostname === 'static.games.yandex.net' &&
            /^\/opengraph\/[^/]+\/default\.png$/.test(url.pathname)) ||
          (url.hostname === 'yastatic.net' &&
            /^\/s3\/games-static\/(?:favicons\/yandex\/|static-data\/images\/(?:single-logo\/(?:games|yandex)\/|logo\/v\d+\/yandex\/))/.test(
              url.pathname,
            ))
        );
      } catch (_) {
        return false;
      }
    }
    function updateSplitText(element) {
      // Keep inline nodes and their handlers when a brand spans several text nodes.
      if (!element.firstElementChild || element.querySelector(skipped + ',svg,img')) {
        return;
      }
      const value = element.textContent;
      if (!value || brandText(value).trim() !== 'UGames') {
        return;
      }
      const walker = doc.createTreeWalker(element, 4);
      const nodes = [];
      while (walker.nextNode()) {
        nodes.push(walker.currentNode);
      }
      if (nodes.length > 1) {
        const replacement = brandText(value);
        if (nodes[0].data !== replacement) {
          nodes[0].data = replacement;
        }
        for (const node of nodes.slice(1)) {
          if (node.data !== '') {
            node.data = '';
          }
        }
      }
    }
    function updateNode(node) {
      const element = node.nodeType === 1 ? node : node.parentElement;
      if (!element || element.closest(skipped)) {
        // Placeholders are presentation; input values are owned by the user.
        if (element && element.matches('input,textarea') && node === element) {
          for (const name of labels) {
            const value = element.getAttribute(name);
            if (value !== null && brandText(value) !== value) {
              element.setAttribute(name, brandText(value));
            }
          }
        }
        return;
      }
      if (node.nodeType === 3) {
        const replacement = brandText(node.data);
        if (replacement !== node.data) {
          node.data = replacement;
        }
        return;
      }
      if (node.nodeType !== 1) {
        return;
      }
      updateSplitText(element);
      if (
        element.tagName === 'META' &&
        element.matches(
          '[name="description"],[name="application-name"],[name="apple-mobile-web-app-title"],[name="twitter:title"],[name="twitter:description"],[property="og:title"],[property="og:description"],[property="og:site_name"]',
        )
      ) {
        const value = element.getAttribute('content');
        if (value !== null && brandText(value) !== value) {
          element.setAttribute('content', brandText(value));
        }
      }
      if (
        element.tagName === 'META' &&
        element.matches('[property="og:image"],[name="twitter:image"]')
      ) {
        if (isLogoURL(element.getAttribute('content'))) {
          brandedImages.add(element);
        }
        if (brandedImages.has(element) && element.getAttribute('content') !== logo) {
          element.setAttribute('content', logo);
        }
      }
      if (
        element.tagName === 'LINK' &&
        /^(?:icon|shortcut icon|apple-touch-icon|apple-touch-icon-precomposed)$/i.test(element.rel)
      ) {
        if (isLogoURL(element.href)) {
          brandedImages.add(element);
        }
        if (
          brandedImages.has(element) &&
          element.getAttribute('href') !== (win.__UGamesBranding?.assets.icon || logo)
        ) {
          element.setAttribute('href', win.__UGamesBranding?.assets.icon || logo);
          element.setAttribute('type', 'image/svg+xml');
        }
      }
      const description = labels.map((name) => element.getAttribute(name) || '').join(' ');
      const cssLogo = element.matches(
        '.Icon_type_logo,.Icon_type_logo-games,.Icon_type_logo-webapps',
      );
      if (
        cssLogo ||
        (element.localName === 'svg' &&
          (brandText(description) !== description || element.closest(logoContainer)))
      ) {
        brandedGraphics.add(element);
      }
      if (brandedGraphics.has(element)) {
        if (element.localName === 'svg') {
          if (win.__UGamesBranding?.assets.logo) {
            let image = element.querySelector('image[data-ugames-logo]');
            if (!image || element.childNodes.length !== 1) {
              image = doc.createElementNS('http://www.w3.org/2000/svg', 'image');
              image.setAttribute('data-ugames-logo', '');
              image.setAttribute('width', '140');
              image.setAttribute('height', '32');
              element.replaceChildren(image);
            }
            if (image.getAttribute('href') !== logo) {
              image.setAttribute('href', logo);
            }
          } else if (element.textContent !== 'UGames' || element.querySelector('path,use,image')) {
            const text = doc.createElementNS('http://www.w3.org/2000/svg', 'text');
            text.setAttribute('x', '2');
            text.setAttribute('y', '24');
            text.setAttribute('fill', 'currentColor');
            text.setAttribute('font-size', '26');
            text.setAttribute('font-family', 'system-ui,sans-serif');
            text.setAttribute('font-weight', '700');
            text.textContent = 'UGames';
            element.replaceChildren(text);
          }
          if (element.getAttribute('viewBox') !== '0 0 140 32') {
            element.setAttribute('viewBox', '0 0 140 32');
          }
        } else {
          if (element.textContent !== 'UGames') {
            element.textContent = 'UGames';
          }
          const mark = win.__UGamesBranding?.assets.icon;
          element.style.setProperty(
            'background-image',
            mark ? 'url("' + mark + '")' : 'none',
            'important',
          );
          element.style.setProperty('width', mark ? '32px' : 'auto', 'important');
          element.style.setProperty(
            'font',
            mark ? '0/0 system-ui,sans-serif' : '700 18px system-ui,sans-serif',
            'important',
          );
          element.style.setProperty('white-space', 'nowrap', 'important');
        }
        if (element.getAttribute('aria-label') !== 'UGames') {
          element.setAttribute('aria-label', 'UGames');
        }
      }
      if (element.tagName === 'SOURCE') {
        const image = element.closest('picture')?.querySelector('img');
        if (image && brandedImages.has(image)) {
          updateNode(image);
        }
      }
      if (element.tagName === 'IMG') {
        if (
          labels.some((name) => brandText(element.getAttribute(name) || '').trim() === 'UGames') ||
          element.closest(logoContainer) ||
          isLogoURL(element.getAttribute('src'))
        ) {
          brandedImages.add(element);
        }
        if (brandedImages.has(element)) {
          // Keep the existing node, layout classes and link event handlers.
          if (element.getAttribute('src') !== logo) {
            element.setAttribute('src', logo);
          }
          element.removeAttribute('srcset');
          if (element.alt !== 'UGames') {
            element.alt = 'UGames';
          }
          const picture = element.closest('picture');
          if (picture) {
            for (const source of picture.querySelectorAll('source')) {
              source.removeAttribute('srcset');
            }
          }
        }
      }
      for (const name of labels) {
        const value = element.getAttribute(name);
        if (value !== null && brandText(value) !== value) {
          element.setAttribute(name, brandText(value));
        }
      }
      if (element.shadowRoot) {
        observeBranding(element.shadowRoot);
      }
    }
    function updateTree(root) {
      updateNode(root);
      const walker = doc.createTreeWalker(root, 1 | 4);
      while (walker.nextNode()) {
        updateNode(walker.currentNode);
      }
    }
    function observeBranding(root) {
      if (observedRoots.has(root)) {
        return;
      }
      observedRoots.add(root);
      const observer = new win.MutationObserver(function (changes) {
        for (const change of changes) {
          if (change.type === 'childList') {
            updateNode(change.target);
            for (const node of change.addedNodes) {
              updateTree(node);
            }
          } else {
            if (change.type === 'characterData' && change.target.parentElement) {
              updateSplitText(change.target.parentElement);
            }
            updateNode(change.target);
          }
        }
      });
      observer.observe(root, {
        subtree: true,
        childList: true,
        characterData: true,
        attributes: true,
        attributeFilter: labels.concat([
          'src',
          'srcset',
          'class',
          'content',
          'href',
          'rel',
          'name',
          'property',
        ]),
      });
      updateTree(root);
    }
    observeBranding(doc);
    if (win.Element && typeof win.Element.prototype.attachShadow === 'function') {
      const attachShadow = win.Element.prototype.attachShadow;
      win.Element.prototype.attachShadow = function (options) {
        const root = attachShadow.call(this, options);
        observeBranding(root);
        return root;
      };
    }
  }
  if (rules && doc && typeof win.MutationObserver === 'function') {
    const observedAdRoots = new WeakSet();
    const hiddenAds = new WeakSet();
    const dismissedAds = new WeakSet();
    const adMarker =
      'a[href*="/games/_crpd/"], a[href*="/socialads-transparency-report"], a[href^="https://yandex.ru/an/count/"]';
    // These selectors belong to the portal shell, never to embedded game documents.
    const portalChrome = [
      '.page-description',
      '.left-panel__links',
      '.left-panel__copyright',
      '[data-testid="notifications-widget"]',
      '[data-testid="notification-button-container"]',
      '[data-testid="balance-button"]',
      '[data-testid="new-catalog-header-user-menu-button-menu-item-help"]',
    ].join(',');
    const adSlotWrappers = '.feed,.feed__section,.grid-list__game-item';
    const portalStyles = new WeakMap();
    function suppressPortalContent(root) {
      if (!win.document) {
        return;
      }
      const isPortal =
        /^(?:www\.)?yandex\.(?:ru|com)$/.test(win.location.hostname) &&
        /^\/games(?:\/|$)/.test(win.location.pathname);
      const targets = new Set();
      if (isPortal) {
        for (const element of root.querySelectorAll(portalChrome)) {
          targets.add(element.closest('.left-panel__block') || element);
        }
        for (const link of root.querySelectorAll('a[href]')) {
          try {
            const url = new win.URL(link.getAttribute('href'), doc.baseURI);
            if (
              /^(?:www\.)?yandex\.(?:ru|com)$/.test(url.hostname) &&
              /^\/(?:games\/(?:shop|promos)|support\/games|legal\/(?:games_termsofuse|confidential|recommendations)|project\/games\/for-developers)(?:\/|$)/.test(
                url.pathname,
              )
            ) {
              targets.add(link.closest('li,[role="menuitem"]') || link);
            }
          } catch (_) {}
        }
      }
      // Paid placements bypass the game SDK. Remove their whole card or grid slot.
      for (const link of root.querySelectorAll(
        '.game-card a[href],.play-similar-games-tile a[href]',
      )) {
        try {
          const source = new win.URL(link.getAttribute('href'), doc.baseURI).searchParams.get(
            'utm_source',
          );
          if (source === 'game_promo_catalog' || source === 'game_promo_similar_games') {
            const card = link.closest('.game-card,.play-similar-games-tile');
            targets.add(card.closest('.grid-list__game-item') || card);
          }
        } catch (_) {}
      }
      for (const badge of root.querySelectorAll('.game-badges__sticky-badge[title="Промо"]')) {
        const card = badge.closest('.game-card');
        if (card) {
          targets.add(card.closest('.grid-list__game-item') || card);
        }
      }
      let previous = portalStyles.get(root);
      if (!previous) {
        previous = new Map();
        portalStyles.set(root, previous);
      }
      function containsOnlyAds(container) {
        let hasAd = false;
        for (const node of container.childNodes) {
          if (node.nodeType === 3 && node.textContent.trim()) {
            return false;
          }
          if (node.nodeType !== 1 || ['SCRIPT', 'STYLE', 'TEMPLATE'].includes(node.tagName)) {
            continue;
          }
          if (
            targets.has(node) ||
            (hiddenAds.has(node) && !previous.has(node)) ||
            (node.matches(adSlotWrappers) && containsOnlyAds(node))
          ) {
            hasAd = true;
          } else {
            return false;
          }
        }
        return hasAd || previous.has(container);
      }
      // Collapse spacing owned by ad-only sections, and restore reused game sections below.
      if (isPortal) {
        for (const slot of root.querySelectorAll(adSlotWrappers)) {
          if ((!hiddenAds.has(slot) || previous.has(slot)) && containsOnlyAds(slot)) {
            targets.add(slot);
          }
        }
      }
      for (const [element, properties] of previous) {
        if (!targets.has(element)) {
          hiddenAds.delete(element);
          for (const [name, value, priority] of properties) {
            if (value) {
              element.style.setProperty(name, value, priority);
            } else {
              element.style.removeProperty(name);
            }
          }
          previous.delete(element);
        }
      }
      for (const element of targets) {
        if (!previous.has(element)) {
          previous.set(
            element,
            ['display', 'visibility'].map((name) => [
              name,
              element.style.getPropertyValue(name),
              element.style.getPropertyPriority(name),
            ]),
          );
        }
        hideAd(element);
      }
    }
    function hideAd(element) {
      hiddenAds.add(element);
      // Avoid triggering our style observer again when nothing has changed.
      for (const [name, value] of [
        ['display', 'none'],
        ['visibility', 'hidden'],
      ]) {
        if (
          element.style.getPropertyValue(name) !== value ||
          element.style.getPropertyPriority(name) !== 'important'
        ) {
          element.style.setProperty(name, value, 'important');
        }
      }
    }
    function dismissAd(root, container) {
      hideAd(container);
      // Closing an ad can synchronously detach its host; remember its outer slot first.
      suppressPortalContent(container.getRootNode());
      const close = root.querySelector('[data-fullscreen-element="close"]');
      if (close && !dismissedAds.has(close)) {
        dismissedAds.add(close);
        state.intercepted.portal++;
        close.click();
      }
    }
    function suppressPortalAds(root) {
      for (const fullscreen of root.querySelectorAll('[data-fullscreen-element="root"]')) {
        if (fullscreen.querySelector(adMarker)) {
          dismissAd(fullscreen, fullscreen);
        }
      }
      if (root.host && root.querySelector(adMarker)) {
        const container = root.host.closest('.csr-uniq1') || root.host;
        dismissAd(root, container);
      }
      const close = root.querySelector(
        '.play-modal.adv-focusable.play-modal_visible .close-button_type_adv-fullscreen',
      );
      if (close && !dismissedAds.has(close)) {
        dismissedAds.add(close);
        close.click();
      }
      for (const selector of rules.hiddenSelectors) {
        for (const element of root.querySelectorAll(selector)) {
          hideAd(element);
        }
      }
      for (const icon of root.querySelectorAll('.Icon_type_no-ads,.Icon_type_no-ads-mono')) {
        const control = icon.closest('button,a,[role="button"],[role="menuitem"]');
        if (control) {
          hideAd(control);
        }
      }
      suppressPortalContent(root);
      // Document observers cannot see changes inside shadow roots.
      for (const element of root.querySelectorAll('*')) {
        if (element.shadowRoot) {
          observeAdvertisingRoot(element.shadowRoot);
        }
      }
    }
    function observeAdvertisingRoot(root) {
      if (observedAdRoots.has(root)) {
        return;
      }
      observedAdRoots.add(root);
      const observer = new win.MutationObserver(function (changes) {
        let rescan = false;
        for (const change of changes) {
          if (change.type === 'attributes' && change.attributeName === 'style') {
            if (hiddenAds.has(change.target)) {
              hideAd(change.target);
            }
          } else {
            rescan = true;
          }
        }
        if (rescan) {
          suppressPortalAds(root);
        }
      });
      observer.observe(root, {
        subtree: true,
        childList: true,
        attributes: true,
        attributeFilter: [
          'class',
          'href',
          'title',
          'id',
          'data-testid',
          'data-fullscreen-element',
          'style',
        ],
      });
      suppressPortalAds(root);
    }
    if (win.Element && typeof win.Element.prototype.attachShadow === 'function') {
      const originalAttach = win.Element.prototype.attachShadow;
      win.Element.prototype.attachShadow = function attachShadow(options) {
        const root = originalAttach.call(this, options);
        observeAdvertisingRoot(root);
        return root;
      };
    }
    observeAdvertisingRoot(doc);
  }
})(window);
