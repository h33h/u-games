(function installOfflineGames(win) {
  'use strict';
  if (win.__UGamesOfflineRuntime || !win.document) {
    return;
  }
  const doc = win.document;
  const config = win.__UGamesOfflineConfig;
  const gameHost = /\.(?:games\.yandex\.net|games\.s3\.yandex\.net)$/;
  const entry = new win.URL(config?.url || win.location.href);
  const isGame = gameHost.test(entry.hostname);
  const prefix = 'ugames.offline.';
  let environment = config?.environment || {};
  let gameReady = false;
  let storage;
  let captureTimer;
  let packageState = 'unknown';
  let packageFiles = [];
  let packageOverflow = false;
  let packageURL;

  function memoryStorage() {
    const values = new Map();
    const methods = {
      get length() {
        return values.size;
      },
      key(index) {
        return Array.from(values.keys())[index] ?? null;
      },
      getItem(key) {
        return values.get(String(key)) ?? null;
      },
      setItem(key, value) {
        values.set(String(key), String(value));
        scheduleCapture();
      },
      removeItem(key) {
        values.delete(String(key));
        scheduleCapture();
      },
      clear() {
        values.clear();
        scheduleCapture();
      },
    };
    return new Proxy(methods, {
      get(target, key) {
        return key in target ? target[key] : methods.getItem(key);
      },
      set(_target, key, value) {
        methods.setItem(key, value);
        return true;
      },
      ownKeys() {
        return Array.from(values.keys());
      },
      getOwnPropertyDescriptor(_target, key) {
        return values.has(key)
          ? { value: values.get(key), enumerable: true, configurable: true }
          : undefined;
      },
      deleteProperty(_target, key) {
        methods.removeItem(key);
        return true;
      },
    });
  }
  try {
    storage = win.localStorage;
    if (config) {
      storage.setItem(prefix + 'probe', '1');
      storage.removeItem(prefix + 'probe');
    }
  } catch (_) {
    storage = memoryStorage();
    if (config) {
      try {
        Object.defineProperty(win, 'localStorage', { value: storage });
      } catch (_) {}
    }
  }
  function read(name, fallback = {}) {
    try {
      return JSON.parse(storage.getItem(prefix + name)) ?? fallback;
    } catch (_) {
      return fallback;
    }
  }
  function write(name, value) {
    try {
      storage.setItem(prefix + name, JSON.stringify(value));
    } catch (_) {}
    scheduleCapture();
  }
  function unavailable() {
    const error = new Error('Эта функция требует подключения к интернету.');
    error.code = 'OFFLINE_UNAVAILABLE';
    return Promise.reject(error);
  }
  function scheduleCapture() {
    if (config && !captureTimer) {
      captureTimer = win.setTimeout(() => {
        captureTimer = null;
        capture();
      }, 200);
    }
  }
  function mirror(object, name, update) {
    const original = object?.[name];
    if (typeof original !== 'function') {
      return;
    }
    try {
      object[name] = function (...args) {
        const result = original.apply(this, args);
        function remember(value) {
          update(value, args);
          return value;
        }
        return result && typeof result.then === 'function'
          ? result.then(remember)
          : remember(result);
      };
    } catch (_) {}
  }
  const players = new WeakSet();
  const sdks = new WeakSet();
  function trackPlayer(player) {
    if (!player || players.has(player)) {
      return player;
    }
    players.add(player);
    for (const [get, set, key] of [
      ['getData', 'setData', 'data'],
      ['getStats', 'setStats', 'stats'],
    ]) {
      mirror(player, get, (value) => {
        if (value && typeof value === 'object') {
          write(key, { ...read(key), ...value });
        }
      });
      mirror(player, set, (_value, args) => {
        write(key, { ...read(key), ...args[0] });
      });
    }
    mirror(player, 'incrementStats', (_value, args) => {
      const stats = read('stats');
      for (const [key, value] of Object.entries(args[0] || {})) {
        stats[key] = (Number(stats[key]) || 0) + value;
      }
      write('stats', stats);
    });
    return player;
  }
  function trackSDK(sdk) {
    if (!isGame || !sdk || sdks.has(sdk)) {
      return;
    }
    sdks.add(sdk);
    try {
      environment = JSON.parse(JSON.stringify(sdk.environment || environment));
    } catch (_) {}
    mirror(sdk, 'getPlayer', (player) => trackPlayer(player));
    mirror(sdk, 'getFlags', (flags) => write('flags', flags));
    const payments = new WeakSet();
    mirror(sdk, 'getPayments', (value) => {
      if (value && !payments.has(value)) {
        payments.add(value);
        mirror(value, 'getCatalog', (catalog) => write('catalog', catalog));
      }
    });
    mirror(sdk.features?.LoadingAPI, 'ready', () => {
      gameReady = true;
      capture();
    });
  }
  Object.defineProperty(win, '__UGamesOfflineRuntime', { value: { trackSDK } });

  if (config && isGame) {
    const marker = prefix + 'restored.' + config.gameId;
    try {
      if (!storage.getItem(marker)) {
        for (const [key, value] of Object.entries(config.storage || {})) {
          if (typeof value === 'string' && storage.getItem(key) === null) {
            storage.setItem(key, value);
          }
        }
        storage.setItem(marker, '1');
      }
    } catch (_) {}
    const nothing = () => {};
    const resolved = () => Promise.resolve();
    const select = (key, keys) => {
      const data = read(key);
      return Promise.resolve(
        Array.isArray(keys)
          ? Object.fromEntries(
              keys.filter((name) => name in data).map((name) => [name, data[name]]),
            )
          : data,
      );
    };
    const player = {
      getData: (keys) => select('data', keys),
      setData: (data) => {
        write('data', { ...read('data'), ...data });
        return Promise.resolve();
      },
      getStats: (keys) => select('stats', keys),
      setStats: (stats) => {
        write('stats', { ...read('stats'), ...stats });
        return Promise.resolve();
      },
      incrementStats: (increments) => {
        const stats = read('stats');
        for (const [key, value] of Object.entries(increments)) {
          stats[key] = (Number(stats[key]) || 0) + value;
        }
        write('stats', stats);
        return Promise.resolve();
      },
      getMode: () => 'lite',
      getUniqueID: () => 'ugames-offline-' + config.gameId,
      getName: () => 'Игрок',
      getPhoto: () => '',
      getPayingStatus: () => 'unknown',
    };
    const mobile = /Android|iPhone|iPod/i.test(win.navigator.userAgent);
    const tablet = /iPad/i.test(win.navigator.userAgent);
    const appID = String(
      environment.app?.id || entry.hostname.match(/^app-(\d+)\./)?.[1] || config.gameId,
    );
    const fullScreen = { status: 'off', request: resolved, exit: resolved };
    const sdk = {
      environment: {
        ...environment,
        app: { ...environment.app, id: appID },
        i18n: { lang: 'ru', tld: 'ru', ...environment.i18n },
        browser: { lang: win.navigator.language || 'ru', ...environment.browser },
        payload: environment.payload || '',
      },
      deviceInfo: {
        type: tablet ? 'tablet' : mobile ? 'mobile' : 'desktop',
        isMobile: () => mobile,
        isTablet: () => tablet,
        isDesktop: () => !mobile && !tablet,
        isTV: () => false,
      },
      features: {
        LoadingAPI: { ready: nothing },
        GameplayAPI: { start: nothing, stop: nothing },
        GamesAPI: {
          getAllGames: () => Promise.resolve({ games: [], developerURL: '' }),
          getGameByID: unavailable,
        },
      },
      adv: {
        showFullscreenAdv: nothing,
        showRewardedVideo: nothing,
        showBannerAdv: resolved,
        hideBannerAdv: resolved,
        getBannerAdvStatus: () => Promise.resolve({ stickyAdvIsShowing: false }),
      },
      getPlayer: () => Promise.resolve(player),
      getStorage: () => Promise.resolve(storage),
      getFlags: () => Promise.resolve(read('flags')),
      getPayments: () =>
        Promise.resolve({ getCatalog: () => Promise.resolve(read('catalog', [])) }),
      getLeaderboards: () =>
        Promise.resolve({
          getLeaderboardEntries: unavailable,
          getLeaderboardPlayerEntry: unavailable,
          setLeaderboardScore: unavailable,
          getLeaderboardDescription: unavailable,
        }),
      leaderboards: {
        getEntries: unavailable,
        getPlayerEntry: unavailable,
        setScore: unavailable,
        getDescription: unavailable,
      },
      feedback: {
        canReview: () => Promise.resolve({ value: false, reason: 'OFFLINE' }),
        requestReview: unavailable,
      },
      shortcut: {
        canShowPrompt: () => Promise.resolve({ canShow: false }),
        showPrompt: unavailable,
      },
      auth: { openAuthDialog: unavailable },
      screen: { fullscreen: fullScreen },
      clipboard: { writeText: unavailable },
      getAllGames: () => Promise.resolve({ games: [], developerURL: '' }),
      getGameByID: unavailable,
      isAvailableMethod: (name) =>
        Promise.resolve(['getPlayer', 'getFlags', 'getStorage', 'getPayments'].includes(name)),
      serverTime: () => Date.now(),
      on: nothing,
      off: nothing,
      dispatchEvent: nothing,
    };
    const verifiedUnityTemplate =
      /^app-(?:414204|451368)\.(?:games\.s3\.yandex\.net|cdn\.games\.yandex\.net)$/.test(
        entry.hostname,
      );
    let unitySDKReady;
    function initOfflineSDK() {
      if (unitySDKReady) {
        return unitySDKReady;
      }
      if (
        !verifiedUnityTemplate ||
        !doc.querySelector('#unity-canvas') ||
        typeof win.InitYSDK !== 'function' ||
        typeof win.StartUnityInstance_IfUnloaded !== 'function' ||
        typeof win.createUnityInstance === 'function'
      ) {
        return Promise.resolve(sdk);
      }
      unitySDKReady = new Promise((resolve, reject) => {
        const scripts = new Set();
        const buildPath = new win.URL('Build/', entry).pathname;
        let observer;
        let settled = false;
        function finish(error) {
          if (settled) {
            return;
          }
          settled = true;
          observer?.disconnect();
          win.removeEventListener('pagehide', abort);
          for (const script of scripts) {
            script.removeEventListener('load', loaded);
            script.removeEventListener('error', failed);
          }
          if (error) {
            reject(error);
          } else {
            resolve(sdk);
          }
        }
        function loaded() {
          if (typeof win.createUnityInstance === 'function') {
            finish();
          } else {
            failed();
          }
        }
        function failed() {
          finish(new Error('Unity loader failed to initialize.'));
        }
        function abort(event) {
          if (event.persisted) {
            return;
          }
          const error = new Error('Unity initialization was interrupted.');
          error.name = 'AbortError';
          finish(error);
        }
        function observeScripts() {
          for (const script of doc.querySelectorAll('script[src]')) {
            if (scripts.has(script)) {
              continue;
            }
            const url = new win.URL(script.src, entry);
            if (
              url.host !== entry.host ||
              !url.pathname.startsWith(buildPath) ||
              !/^[^/]+\.loader\.js$/.test(url.pathname.slice(buildPath.length))
            ) {
              continue;
            }
            scripts.add(script);
            // The YG2 template's earlier onload handler defines its Unity startup function.
            script.addEventListener('load', loaded);
            script.addEventListener('error', failed);
          }
        }
        observer = new win.MutationObserver(observeScripts);
        observer.observe(doc.documentElement, {
          childList: true,
          subtree: true,
          attributes: true,
          attributeFilter: ['src'],
        });
        win.addEventListener('pagehide', abort);
        observeScripts();
      });
      return unitySDKReady;
    }
    const provider = { init: initOfflineSDK };
    // A bundled SDK may still assign YaGames; initialization must remain independent of the portal.
    Object.defineProperty(win, 'YaGames', {
      configurable: false,
      get: () => provider,
      set: nothing,
    });
    const workers = win.navigator.serviceWorker;
    if (workers) {
      try {
        workers.register = unavailable;
      } catch (_) {}
    }
    if (config.scheme) {
      function localURL(value) {
        const text = String(value);
        return /^https?:\/\//i.test(text) ? text.replace(/^https?:/i, config.scheme) : text;
      }
      if (typeof win.fetch === 'function') {
        const fetch = win.fetch;
        win.fetch = function (input, options) {
          if (win.Request && input instanceof win.Request) {
            return fetch.call(this, new win.Request(localURL(input.url), input), options);
          }
          return fetch.call(this, localURL(input), options);
        };
      }
      if (win.XMLHttpRequest) {
        const open = win.XMLHttpRequest.prototype.open;
        win.XMLHttpRequest.prototype.open = function (method, url, ...rest) {
          return open.call(this, method, localURL(url), ...rest);
        };
      }
    }
  }

  function nativeReport(report) {
    const body = JSON.stringify(report);
    if (body.length > 2 * 1024 * 1024) {
      return;
    }
    try {
      if (typeof win.__UGamesOffline?.postMessage === 'function') {
        win.__UGamesOffline.postMessage(body);
      } else {
        win.webkit?.messageHandlers?.ugamesOffline?.postMessage(body);
      }
    } catch (_) {}
  }
  function discoverPackage() {
    if (
      packageState !== 'unknown' ||
      config ||
      typeof win.fetch !== 'function' ||
      !/construct/i.test(doc.querySelector('meta[name="generator"]')?.content || '')
    ) {
      return;
    }
    packageState = 'loading';
    packageURL = new win.URL('offline.json', entry).href;
    win
      .fetch(packageURL, { credentials: 'omit' })
      .then((response) => (response.ok ? response.json() : null))
      .then((manifest) => {
        if (Array.isArray(manifest?.fileList) && manifest.fileList.length <= 4096) {
          packageFiles = manifest.fileList.filter((file) => typeof file === 'string');
          packageFiles.push('offline.json');
        } else if (Array.isArray(manifest?.fileList)) {
          packageOverflow = true;
        }
      })
      .catch(() => {})
      .finally(() => {
        packageState = 'complete';
        capture();
      });
  }
  function capture() {
    if (!isGame) {
      for (const frame of doc.querySelectorAll('iframe')) {
        try {
          frame.contentWindow?.postMessage({ type: 'ugames-offline-capture' }, '*');
        } catch (_) {}
      }
      return;
    }
    discoverPackage();
    const entryResource = new win.URL(entry.href);
    entryResource.hash = '';
    const urls = new Set([entryResource.href]);
    let resourceOverflow = packageOverflow;
    function add(value) {
      try {
        let url = new win.URL(value, entry);
        if (config?.scheme && url.protocol === config.scheme) {
          url = new win.URL(url.href.replace(config.scheme, 'https:'));
        }
        if (
          url.protocol !== 'https:' ||
          url.username ||
          url.password ||
          url.port ||
          !gameHost.test(url.hostname) ||
          /\/(?:sdk(?:\.js|\/)|api\/)/i.test(url.pathname)
        ) {
          return;
        }
        url.hash = '';
        if (urls.size < 4096) {
          urls.add(url.href);
        } else if (!urls.has(url.href)) {
          resourceOverflow = true;
        }
      } catch (_) {}
    }
    for (const resource of win.performance.getEntriesByType?.('resource') || []) {
      // Optional manifest discovery and failed feature probes are not game dependencies.
      // A valid export manifest is added explicitly below after successful parsing.
      if (resource.name !== packageURL && !(resource.responseStatus >= 400)) {
        add(resource.name);
      }
    }
    for (const file of packageFiles) {
      add(file);
    }
    for (const node of doc.querySelectorAll(
      'script[src],link[rel="stylesheet"][href],img[src],audio[src],video[src],source[src]',
    )) {
      add(node.src || node.href);
    }
    const saved = {};
    try {
      for (let index = 0; index < storage.length; index++) {
        const key = storage.key(index);
        if (key !== null) {
          saved[key] = storage.getItem(key);
        }
      }
    } catch (_) {}
    nativeReport({
      version: 1,
      url: entry.href,
      title: doc.title,
      resources: Array.from(urls),
      storage: saved,
      environment,
      ready:
        doc.readyState === 'complete' &&
        !resourceOverflow &&
        packageState !== 'loading' &&
        (gameReady || urls.size > 1 || !!config),
    });
  }
  win.__UGamesOfflineCapture = capture;
  if (!isGame) {
    return;
  }
  win.performance.setResourceTimingBufferSize?.(8192);
  win.addEventListener('message', (event) => {
    if (event.data?.type === 'ugames-offline-capture') {
      capture();
    }
  });
  win.addEventListener('load', capture);
  let interval = win.setInterval(capture, 3000);
  win.addEventListener('pagehide', () => {
    capture();
    win.clearInterval(interval);
    interval = null;
  });
  win.addEventListener('pageshow', () => {
    if (interval === null) {
      interval = win.setInterval(capture, 3000);
    }
  });
})(window);
