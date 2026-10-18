'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');

const entry = 'https://app-448583.cdn.games.yandex.net/build/index.html';
const cloud = 'https://storage.yandexcloud.net/game-assets/Addressables/1.4/';
const source = fs.readFileSync(path.join(__dirname, '../offline-games.js'), 'utf8');

test('captures public external game bundles, version hashes and static runtime files', (t) => {
  const dom = new JSDOM('<title>Game</title>', { url: entry, runScripts: 'outside-only' });
  t.after(() => dom.window.close());
  const win = dom.window;
  const resources = [
    cloud + 'catalog_0.1.0.hash',
    cloud + 'catalog_0.1.0.bin',
    cloud + 'scene_a0ed365f.bundle',
    'https://yastatic.net/game-runtime/runtime.js',
  ];
  const reports = [];
  win.__UGamesOffline = { postMessage: (body) => reports.push(JSON.parse(body)) };
  win.performance.getEntriesByType = () =>
    resources.map((name) => ({ name, initiatorType: 'fetch', responseStatus: 200 }));
  win.eval(source);
  win.__UGamesOfflineCapture();
  assert.deepEqual(reports.at(-1).resources, [entry, ...resources]);
});

test('external capture excludes services, credentials, failed probes and unrelated hosts', (t) => {
  const dom = new JSDOM('<title>Game</title>', { url: entry, runScripts: 'outside-only' });
  t.after(() => dom.window.close());
  const win = dom.window;
  const rejected = [
    cloud + 'api/player.json',
    cloud + 'auth/session.json',
    cloud + 'catalog.json?token=private',
    cloud + 'level.bundle?access_token=private',
    cloud + 'catalog.bin?X-Amz-Signature=private',
    cloud + 'level.bundle?AWSAccessKeyId=private',
    cloud + 'catalog',
    'https://storage.yandexcloud.net.evil.test/game.bundle',
    'https://user:password@storage.yandexcloud.net/game.bundle',
    'https://yandex.ru/games/api/player.json',
    'https://an.yandex.ru/count.js',
  ];
  const reports = [];
  win.__UGamesOffline = { postMessage: (body) => reports.push(JSON.parse(body)) };
  win.performance.getEntriesByType = () => [
    ...rejected.map((name) => ({ name, responseStatus: 200 })),
    { name: cloud + 'optional.bundle', responseStatus: 404 },
  ];
  win.eval(source);
  win.__UGamesOfflineCapture();
  assert.deepEqual(reports.at(-1).resources, [entry]);
});

test('offline player exposes the authorization check used during Unity SDK initialization', async (t) => {
  const dom = new JSDOM('<title>Game</title>', { url: entry, runScripts: 'outside-only' });
  t.after(() => dom.window.close());
  const win = dom.window;
  win.__UGamesOfflineConfig = { gameId: '448583', url: entry, storage: {} };
  win.eval(source);
  const sdk = await win.YaGames.init();
  const player = await sdk.getPlayer();
  assert.equal(player.isAuthorized(), false);
  await player.setData({ level: 3 });
  assert.deepEqual(JSON.parse(JSON.stringify(await player.getData())), { level: 3 });
});
