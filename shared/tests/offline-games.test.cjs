'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');
const file = path.join(__dirname, '../offline-games.js');
const source = () => (fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '');
const adapter = fs.readFileSync(path.join(__dirname, '../ad-adapter.js'), 'utf8');
const gameURL = 'https://app-42.games.s3.yandex.net/42/build/index.html';
const unityURL =
  'https://app-414204.games.s3.yandex.net/414204/9l0528q36x2mx1l2gpmc07ewpzj1t5me/index.html';

function page(t, { url = gameURL, config, prepare = () => {} } = {}) {
  const dom = new JSDOM('<title>Test game</title><canvas></canvas>', {
    url,
    runScripts: 'outside-only',
  });
  t.after(() => dom.window.close());
  const win = dom.window;
  const reports = [];
  win.__UGamesOffline = { postMessage: (message) => reports.push(JSON.parse(message)) };
  if (config) {
    win.__UGamesOfflineConfig = { gameId: '42', url: gameURL, ...config };
  }
  Object.defineProperty(win.document, 'readyState', { value: 'complete', configurable: true });
  win.performance.getEntriesByType = () => [];
  prepare(win);
  win.eval(source());
  return { win, reports };
}

test('reports loaded game assets and storage without saving catalog or API traffic', (t) => {
  const { win, reports } = page(t, {
    prepare(w) {
      w.localStorage.setItem('level', '7');
      w.performance.getEntriesByType = () => [
        { name: gameURL.replace('index.html', 'Build/game.wasm.br'), initiatorType: 'fetch' },
        { name: gameURL.replace('index.html', 'Build/game.data.br'), initiatorType: 'fetch' },
        { name: 'https://yandex.ru/games/api/player?token=private', initiatorType: 'fetch' },
        { name: 'https://an.yandex.ru/count', initiatorType: 'img' },
        { name: 'https://passport.yandex.ru/auth', initiatorType: 'iframe' },
      ];
    },
  });
  assert.equal(typeof win.__UGamesOfflineCapture, 'function');
  win.__UGamesOfflineCapture();
  const report = reports.at(-1);
  assert.equal(report.version, 1);
  assert.equal(report.url, gameURL);
  assert.equal(report.ready, true);
  assert.deepEqual(report.resources, [
    gameURL,
    gameURL.replace('index.html', 'Build/game.wasm.br'),
    gameURL.replace('index.html', 'Build/game.data.br'),
  ]);
  assert.equal(report.storage.level, '7');
  const catalog = page(t, { url: 'https://yandex.ru/games/' });
  catalog.win.__UGamesOfflineCapture?.();
  assert.equal(catalog.reports.length, 0);
});

test('catalogue artwork and titles are remembered passively before a game is opened', (t) => {
  const { win, reports } = page(t, {
    url: 'https://yandex.ru/games/',
    prepare(w) {
      w.document.body.innerHTML =
        '<a class="game-card" href="/games/app/toca-boca-302466?utm_source=home#play"><img src="https://avatars.mds.yandex.net/get-games/123/cover/default.jpg"><span class="game-card__title">Тока Бока</span></a>';
    },
  });
  const link = win.document.querySelector('a');
  const event = new win.Event('pointerdown', { bubbles: true, cancelable: true });
  link.dispatchEvent(event);
  assert.equal(event.defaultPrevented, false);
  assert.deepEqual(reports, [
    {
      version: 1,
      type: 'catalog',
      gameId: '302466',
      url: 'https://yandex.ru/games/app/302466',
      title: 'Тока Бока',
      cover: 'https://avatars.mds.yandex.net/get-games/123/cover/default.jpg',
    },
  ]);
  link.dispatchEvent(new win.Event('pointerdown', { bubbles: true }));
  assert.equal(reports.length, 1);
});

test('catalogue metadata never persists account avatars, external links or game API URLs', (t) => {
  const { win, reports } = page(t, {
    url: 'https://yandex.ru/games/',
    prepare(w) {
      w.document.body.innerHTML =
        '<a href="/games/app/42"><img alt="Game" src="https://avatars.mds.yandex.net/get-yapic/private/avatar"></a><a href="https://evil.test/games/app/43">Other</a><a href="/games/api/player?token=private">Account</a>';
    },
  });
  for (const link of win.document.querySelectorAll('a')) {
    link.dispatchEvent(new win.Event('pointerdown', { bubbles: true }));
  }
  assert.equal(reports.length, 1);
  assert.equal(reports[0].title, 'Game');
  assert.equal(reports[0].cover, undefined);
  assert.equal(reports[0].url, 'https://yandex.ru/games/app/42');
});

test('catalogue cover links find the existing caption beside the artwork', (t) => {
  const { win, reports } = page(t, {
    url: 'https://yandex.ru/games/',
    prepare(w) {
      w.document.body.innerHTML =
        '<div class="game-card"><div class="game-card__graphic"><a href="/games/app/42"><img class="game-image" src="https://avatars.mds.yandex.net/get-games/42/cover.jpg"></a></div><div class="game-card__description">Playground</div></div>';
    },
  });
  win.document.querySelector('img').dispatchEvent(new win.Event('pointerdown', { bubbles: true }));
  assert.equal(reports[0]?.title, 'Playground');
});

test('a game portal page reports its own OpenGraph metadata without collecting portal resources', (t) => {
  const { win, reports } = page(t, {
    url: 'https://yandex.com/games/app/42?lang=ru',
    prepare(w) {
      w.document.head.innerHTML =
        '<meta property="og:title" content="Playground"><meta property="og:image" content="https://avatars.mds.yandex.net/get-games/42/cover/default.webp">';
    },
  });
  win.__UGamesOfflineCapture();
  assert.deepEqual(reports, [
    {
      version: 1,
      type: 'catalog',
      gameId: '42',
      url: 'https://yandex.com/games/app/42',
      title: 'Playground',
      cover: 'https://avatars.mds.yandex.net/get-games/42/cover/default.webp',
    },
  ]);
  assert.equal(reports[0].resources, undefined);
});

test('catalogue capture installs at document start before html or head exists', (t) => {
  const { win, reports } = page(t, {
    url: 'https://yandex.ru/games/app/42',
    prepare(w) {
      w.document.documentElement.remove();
      Object.defineProperty(w.document, 'readyState', { value: 'loading', configurable: true });
    },
  });
  const html = win.document.createElement('html');
  html.innerHTML = '<head><meta property="og:title" content="Loaded game"></head><body></body>';
  win.document.appendChild(html);
  win.document.dispatchEvent(new win.Event('DOMContentLoaded'));
  assert.equal(reports.at(-1).title, 'Loaded game');
  assert.equal(typeof win.__UGamesOfflineCapture, 'function');
});

test('includes assets loaded after the first report and does not claim a loading document is ready', (t) => {
  const { win, reports } = page(t, {
    prepare(w) {
      Object.defineProperty(w.document, 'readyState', { value: 'loading', configurable: true });
    },
  });
  assert.equal(typeof win.__UGamesOfflineCapture, 'function');
  win.__UGamesOfflineCapture();
  assert.equal(reports.at(-1).ready, false);
  Object.defineProperty(win.document, 'readyState', { value: 'complete' });
  win.performance.getEntriesByType = () => [{ name: new URL('next-level.json', gameURL).href }];
  win.__UGamesOfflineCapture();
  assert.ok(reports.at(-1).resources.includes(new URL('next-level.json', gameURL).href));
});

test('offline SDK initializes without a portal and keeps player progress across reloads', async (t) => {
  const config = { storage: { level: '7', 'ugames.offline.data': '{"level":7}' } };
  const { win } = page(t, { config });
  assert.equal(typeof win.YaGames?.init, 'function');
  win.eval(adapter);
  const sdk = await win.YaGames.init();
  const player = await sdk.getPlayer();
  assert.equal((await player.getData()).level, 7);
  await player.setData({ level: 8 });
  assert.equal(JSON.parse(win.localStorage.getItem('ugames.offline.data')).level, 8);
  win.eval(source());
  assert.equal(win.localStorage.getItem('level'), '7');
  assert.equal((await (await win.YaGames.init()).getPlayer()).getMode(), 'lite');
  assert.equal((await player.getData()).level, 8);
  assert.equal(sdk.environment.app.id, '42');
  assert.deepEqual(Array.from((await sdk.getAllGames()).games), []);
  assert.deepEqual(Array.from((await sdk.features.GamesAPI.getAllGames()).games), []);
  assert.equal((await sdk.feedback.canReview()).value, false);
});

test('offline Unity SDK waits for the YG2 loader startup handler before booting once', async (t) => {
  let startUnityInstance;
  let starts = 0;
  const { win } = page(t, {
    url: unityURL,
    config: { gameId: '414204', url: unityURL, storage: {} },
    prepare(w) {
      w.document.querySelector('canvas').id = 'unity-canvas';
      w.StartUnityInstance_IfUnloaded = () => startUnityInstance();
      w.InitYSDK = async () => {
        await w.YaGames.init();
        w.StartUnityInstance_IfUnloaded();
      };
    },
  });
  win.eval(adapter);
  let startupError;
  const initialized = win.InitYSDK().catch((error) => {
    startupError = error;
  });
  let sdkReady = false;
  const sdk = win.YaGames.init().then((value) => {
    sdkReady = true;
    return value;
  });
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(sdkReady, false, 'SDK readiness must not race the Unity loader');
  assert.equal(startupError, undefined);

  const unrelated = win.document.createElement('script');
  unrelated.src = 'scripts/other.loader.js';
  win.document.body.appendChild(unrelated);
  await Promise.resolve();
  unrelated.dispatchEvent(new win.Event('load'));
  await Promise.resolve();
  assert.equal(sdkReady, false, 'only the game Build loader can release initialization');

  const loader = win.document.createElement('script');
  loader.src = 'Build/sprunki-sanbox.loader.js';
  loader.onload = () => {
    startUnityInstance = () => starts++;
  };
  win.document.body.appendChild(loader);
  await Promise.resolve();
  win.createUnityInstance = () => {};
  loader.dispatchEvent(new win.Event('load'));
  await initialized;
  assert.equal(startupError, undefined);
  assert.equal(starts, 1);
  assert.equal((await sdk).environment.app.id, '414204');
  loader.dispatchEvent(new win.Event('load'));
  await win.YaGames.init();
  assert.equal(starts, 1);
});

test('offline Unity SDK accepts an already loaded YG2 loader', async (t) => {
  const { win } = page(t, {
    url: unityURL,
    config: { gameId: '414204', url: unityURL, storage: {} },
    prepare(w) {
      w.document.querySelector('canvas').id = 'unity-canvas';
      w.InitYSDK = () => {};
      w.StartUnityInstance_IfUnloaded = () => {};
      w.createUnityInstance = () => {};
    },
  });
  assert.equal((await win.YaGames.init()).environment.app.id, '414204');
});

test('offline Unity SDK rejects a failed YG2 loader instead of signaling readiness', async (t) => {
  const { win } = page(t, {
    url: unityURL,
    config: { gameId: '414204', url: unityURL, storage: {} },
    prepare(w) {
      w.document.querySelector('canvas').id = 'unity-canvas';
      w.InitYSDK = () => {};
      w.StartUnityInstance_IfUnloaded = () => {};
      const loader = w.document.createElement('script');
      loader.src = 'Build/game.loader.js';
      w.document.body.appendChild(loader);
    },
  });
  const rejected = assert.rejects(win.YaGames.init(), /Unity loader failed/);
  win.document.querySelector('script').dispatchEvent(new win.Event('error'));
  await rejected;
});

test('unloading a page cancels pending offline Unity initialization', async (t) => {
  const { win } = page(t, {
    url: unityURL,
    config: { gameId: '414204', url: unityURL, storage: {} },
    prepare(w) {
      w.document.querySelector('canvas').id = 'unity-canvas';
      w.InitYSDK = () => {};
      w.StartUnityInstance_IfUnloaded = () => {};
    },
  });
  const rejected = assert.rejects(win.YaGames.init(), { name: 'AbortError' });
  win.dispatchEvent(new win.PageTransitionEvent('pagehide', { persisted: false }));
  await rejected;
});

test('back-forward cache preserves pending offline Unity initialization', async (t) => {
  const { win } = page(t, {
    url: unityURL,
    config: { gameId: '414204', url: unityURL, storage: {} },
    prepare(w) {
      w.document.querySelector('canvas').id = 'unity-canvas';
      w.InitYSDK = () => {};
      w.StartUnityInstance_IfUnloaded = () => {};
    },
  });
  let initializationError;
  let sdkReady = false;
  const initialized = win.YaGames.init().then(
    (sdk) => {
      sdkReady = true;
      return sdk;
    },
    (error) => {
      initializationError = error;
    },
  );
  win.dispatchEvent(new win.PageTransitionEvent('pagehide', { persisted: true }));
  await Promise.resolve();
  assert.equal(initializationError, undefined);
  assert.equal(sdkReady, false);
  win.dispatchEvent(new win.PageTransitionEvent('pageshow', { persisted: true }));
  const loader = win.document.createElement('script');
  loader.src = 'Build/sprunki-sanbox.loader.js';
  win.document.body.appendChild(loader);
  await Promise.resolve();
  win.createUnityInstance = () => {};
  loader.dispatchEvent(new win.Event('load'));
  assert.equal((await initialized).environment.app.id, '414204');
  assert.equal((await win.YaGames.init()).environment.app.id, '414204');
});

test('unknown Unity templates initialize immediately even with YG2 markers', async (t) => {
  const { win } = page(t, {
    config: { storage: {} },
    prepare(w) {
      w.document.querySelector('canvas').id = 'unity-canvas';
      w.InitYSDK = () => {};
      w.StartUnityInstance_IfUnloaded = () => {};
      const loader = w.document.createElement('script');
      loader.src = 'https://cdn.example.com/custom/game.loader.js';
      w.document.body.appendChild(loader);
    },
  });
  let sdkReady = false;
  const initialized = win.YaGames.init().then((sdk) => {
    sdkReady = true;
    return sdk;
  });
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(sdkReady, true, 'unverified loaders must not block the offline SDK');
  assert.equal((await initialized).environment.app.id, '42');
});

test('verified Unity game aliases wait for their own loader', async (t) => {
  for (const [host, id] of [
    ['app-451368.games.s3.yandex.net', '451368'],
    ['app-414204.cdn.games.yandex.net', '414204'],
    ['app-451368.cdn.games.yandex.net', '451368'],
  ]) {
    const url = `https://${host}/${id}/build/index.html`;
    const { win } = page(t, {
      url,
      config: { gameId: id, url, storage: {} },
      prepare(w) {
        w.document.querySelector('canvas').id = 'unity-canvas';
        w.InitYSDK = () => {};
        w.StartUnityInstance_IfUnloaded = () => {};
      },
    });
    let sdkReady = false;
    const initialized = win.YaGames.init().then((sdk) => {
      sdkReady = true;
      return sdk;
    });
    await Promise.resolve();
    assert.equal(sdkReady, false, host);
    const loader = win.document.createElement('script');
    loader.src = 'Build/game.loader.js';
    win.document.body.appendChild(loader);
    await Promise.resolve();
    win.createUnityInstance = () => {};
    loader.dispatchEvent(new win.Event('load'));
    assert.equal((await initialized).environment.app.id, id);
  }
});

test('offline SDK stays immediately available without every YG2 template marker', async (t) => {
  for (const missing of ['canvas', 'InitYSDK', 'StartUnityInstance_IfUnloaded', 'construct']) {
    const { win } = page(t, {
      url: unityURL,
      config: { gameId: '414204', url: unityURL, storage: {} },
      prepare(w) {
        if (missing === 'construct') {
          w.document.head.insertAdjacentHTML(
            'beforeend',
            '<meta name="generator" content="Scirra Construct">',
          );
          return;
        }
        if (missing !== 'canvas') {
          w.document.querySelector('canvas').id = 'unity-canvas';
        }
        if (missing !== 'InitYSDK') {
          w.InitYSDK = () => {};
        }
        if (missing !== 'StartUnityInstance_IfUnloaded') {
          w.StartUnityInstance_IfUnloaded = () => {};
        }
      },
    });
    assert.equal((await win.YaGames.init()).environment.app.id, '414204', missing);
  }
});

test('offline SDK cannot be replaced by a cached network SDK and rewards still complete once', async (t) => {
  const { win } = page(t, { config: { storage: {} } });
  assert.equal(typeof win.YaGames?.init, 'function');
  win.eval(adapter);
  win.YaGames = {
    init() {
      throw new Error('network SDK must not initialize');
    },
  };
  const sdk = await win.YaGames.init();
  let rewards = 0;
  await new Promise((resolve) =>
    sdk.adv.showRewardedVideo({
      callbacks: { onRewarded: () => rewards++, onClose: resolve },
    }),
  );
  assert.equal(rewards, 1);
  try {
    win.Object.defineProperty(win, 'YaGames', { value: { init: () => null } });
  } catch (_) {}
  assert.equal((await win.YaGames.init()).environment.app.id, '42');
});

test('mirrors successful cloud reads and writes for the offline player', async (t) => {
  const { win } = page(t);
  const onlinePlayer = {
    getData: async () => ({ level: 3, coins: 20 }),
    setData: async () => {},
    getStats: async () => ({ wins: 2 }),
    setStats: async () => {},
  };
  win.YaGames = { init: async () => ({ getPlayer: async () => onlinePlayer }) };
  win.eval(adapter);
  const player = await (await win.YaGames.init()).getPlayer();
  await player.getData();
  assert.equal(JSON.parse(win.localStorage.getItem('ugames.offline.data')).level, 3);
  await player.setData({ level: 4 });
  assert.deepEqual(JSON.parse(win.localStorage.getItem('ugames.offline.data')), {
    level: 4,
    coins: 20,
  });
  await player.getStats();
  assert.equal(JSON.parse(win.localStorage.getItem('ugames.offline.stats')).wins, 2);
});

test('maps offline fetch and XHR to saved scheme while leaving blobs untouched', async (t) => {
  const requests = [];
  const { win } = page(t, {
    config: { scheme: 'ugames-offline:', storage: {} },
    prepare(w) {
      w.fetch = async (url, options) => {
        requests.push([url, options]);
        return {};
      };
      w.XMLHttpRequest.prototype.open = function (...args) {
        requests.push(args);
      };
    },
  });
  await win.fetch(new URL('Build/game.wasm', gameURL), { method: 'GET' });
  await win.fetch('blob:https://example.com/id');
  const xhr = new win.XMLHttpRequest();
  xhr.open('GET', gameURL.replace('index.html', 'level.json'), true);
  assert.equal(
    String(requests[0][0]),
    'ugames-offline://app-42.games.s3.yandex.net/42/build/Build/game.wasm',
  );
  assert.equal(requests[1][0], 'blob:https://example.com/id');
  assert.equal(requests[2][1], 'ugames-offline://app-42.games.s3.yandex.net/42/build/level.json');
});

test('restores storage only once so a subsequent launch does not revert offline progress', (t) => {
  const { win } = page(t, { config: { storage: { level: '1' } } });
  assert.equal(win.localStorage.getItem('level'), '1');
  win.localStorage.setItem('level', '2');
  // A new document gets the same persistent storage and the original download snapshot.
  const saved = Object.fromEntries(Object.entries(win.localStorage));
  const next = page(t, {
    config: { storage: { level: '1' } },
    prepare(w) {
      for (const [key, value] of Object.entries(saved)) {
        w.localStorage.setItem(key, value);
      }
    },
  });
  assert.equal(next.win.localStorage.getItem('level'), '2');
});

test('offline capture normalizes custom-scheme resource URLs to original HTTPS', (t) => {
  const { win, reports } = page(t, {
    config: { storage: {}, scheme: 'ugames-offline:' },
    prepare(w) {
      w.performance.getEntriesByType = () => [
        { name: 'ugames-offline://app-42.games.s3.yandex.net/42/build/game.js' },
      ];
    },
  });
  win.__UGamesOfflineCapture();
  assert.ok(
    reports.at(-1).resources.includes('https://app-42.games.s3.yandex.net/42/build/game.js'),
  );
});

test('Construct packages include files from the export manifest before they are first used', async (t) => {
  const { win, reports } = page(t, {
    prepare(w) {
      w.document.head.insertAdjacentHTML(
        'beforeend',
        '<meta name="generator" content="Scirra Construct">',
      );
      w.fetch = async (url) => {
        assert.equal(String(url), 'https://app-42.games.s3.yandex.net/42/build/offline.json');
        return {
          ok: true,
          json: async () => ({
            fileList: [
              'media/next-level.webm',
              'scripts/c3runtime.js',
              'https://passport.yandex.ru/auth',
            ],
          }),
        };
      };
    },
  });
  win.__UGamesOfflineCapture();
  await new Promise((resolve) => setImmediate(resolve));
  const report = reports.at(-1);
  assert.ok(
    report.resources.includes('https://app-42.games.s3.yandex.net/42/build/media/next-level.webm'),
  );
  assert.ok(
    report.resources.includes('https://app-42.games.s3.yandex.net/42/build/scripts/c3runtime.js'),
  );
  assert.ok(!report.resources.includes('https://passport.yandex.ru/auth'));
  assert.equal(report.ready, true);
});

test('opaque offline origins expose working game storage and send updated progress to native', async (t) => {
  const { win, reports } = page(t, {
    url: 'ugames-offline://app-42.games.s3.yandex.net/42/build/index.html',
    config: { storage: { level: '3' }, scheme: 'ugames-offline:' },
  });
  assert.equal(win.localStorage.getItem('level'), '3');
  win.localStorage.setItem('level', '4');
  win.__UGamesOfflineCapture();
  assert.equal(reports.at(-1).storage.level, '4');
  const sdk = await win.YaGames.init();
  await (await sdk.getPlayer()).setData({ coins: 9 });
  win.__UGamesOfflineCapture();
  assert.equal(JSON.parse(reports.at(-1).storage['ugames.offline.data']).coins, 9);
});

test('native storage identifiers do not replace the original SDK app ID', async (t) => {
  const { win } = page(t, { config: { gameId: 'native-snapshot-hash', storage: {} } });
  const sdk = await win.YaGames.init();
  assert.equal(sdk.environment.app.id, '42');
});

test('saved games can navigate to their own offline documents without opening live sites', (t) => {
  const { win } = page(t, {
    url: 'ugames-offline://app-42.games.s3.yandex.net/42/build/index.html',
    config: { storage: {}, scheme: 'ugames-offline:' },
    prepare(w) {
      w.navigation = new w.EventTarget();
    },
  });
  win.eval(adapter);
  for (const [url, allowed] of [
    ['ugames-offline://app-42.games.s3.yandex.net/42/build/next.html', true],
    ['ugames-offline://app-99.games.s3.yandex.net/other.html', false],
    ['https://yandex.ru/games/', false],
  ]) {
    const event = new win.Event('navigate', { cancelable: true });
    event.destination = { url };
    assert.equal(win.navigation.dispatchEvent(event), allowed, url);
  }
});

test('oversized packages are never reported ready after silently dropping assets', async (t) => {
  for (const count of [4095, 5000]) {
    const { win, reports } = page(t, {
      prepare(w) {
        w.document.head.insertAdjacentHTML(
          'beforeend',
          '<meta name="generator" content="Scirra Construct">',
        );
        w.fetch = async () => ({
          ok: true,
          json: async () => ({
            fileList: Array.from({ length: count }, (_, index) => `media/${index}.webm`),
          }),
        });
      },
    });
    win.__UGamesOfflineCapture();
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(
      reports.at(-1).ready,
      false,
      `${count} media files plus entry and manifest exceed the limit`,
    );
  }
});

test('missing optional Construct manifest does not become a mandatory failed download', async (t) => {
  const { win, reports } = page(t, {
    prepare(w) {
      w.document.head.insertAdjacentHTML(
        'beforeend',
        '<meta name="generator" content="Scirra Construct">',
      );
      w.performance.getEntriesByType = () => [
        { name: new URL('offline.json', gameURL).href },
        { name: new URL('optional.json', gameURL).href, responseStatus: 404 },
        { name: new URL('main.js', gameURL).href, responseStatus: 200 },
      ];
      w.fetch = async () => ({ ok: false, status: 404 });
    },
  });
  win.__UGamesOfflineCapture();
  await new Promise((resolve) => setImmediate(resolve));
  assert.deepEqual(reports.at(-1).resources, [gameURL, new URL('main.js', gameURL).href]);
  assert.equal(reports.at(-1).ready, true);
});

test('keeps the navigation fragment while storing the entry resource only once', (t) => {
  const { win, reports } = page(t, {
    url: gameURL + '#level=7',
    prepare(w) {
      w.performance.getEntriesByType = () => [{ name: gameURL }];
    },
  });
  win.__UGamesOfflineCapture();
  assert.equal(reports.at(-1).url, gameURL + '#level=7');
  assert.deepEqual(reports.at(-1).resources, [gameURL]);
});
