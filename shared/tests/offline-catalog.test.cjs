'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { JSDOM } = require('jsdom');
const { buildShared } = require('../../scripts/build-shared.cjs');

const modulePath = path.join(__dirname, '../offline-catalog.js');
const source = () => (fs.existsSync(modulePath) ? fs.readFileSync(modulePath, 'utf8') : '');
const url = 'https://app-42.games.s3.yandex.net/42/build/index.html#level';
const cover = 'https://yandex.ru/games/.ugames-cache-cover/' + 'a'.repeat(64);
const placeholder = 'data:image/svg+xml;base64,PHN2Zy8+';

function page(t, config, prepare = () => {}) {
  const dom = new JSDOM('<!doctype html><title>UGames</title><body></body>', {
    url: 'https://yandex.ru/games/',
    runScripts: 'outside-only',
  });
  t.after(() => dom.window.close());
  const win = dom.window;
  win.__UGamesBranding = {
    assets: { logo: placeholder, 'cover-placeholder': placeholder },
    css: 'body { color: white; }',
  };
  if (config) {
    win.__UGamesCachedCatalog = config;
  }
  Object.defineProperty(win.document, 'readyState', { value: 'complete', configurable: true });
  prepare(win);
  win.eval(source());
  return win;
}

test('offline catalogue uses the normal game cards and opens original game URLs', (t) => {
  const win = page(t, {
    version: 1,
    games: [
      { url, title: 'Тока Бока', cover },
      { url: 'https://app-7.cdn.games.yandex.net/7/index.html', title: 'Playground' },
    ],
  });
  const links = Array.from(win.document.querySelectorAll('.game-card__link'));
  assert.equal(links.length, 2);
  assert.equal(links[0].href, url);
  assert.equal(links[0].textContent.trim(), 'Тока Бока');
  assert.equal(links[0].querySelector('img').src, cover);
  assert.equal(links[1].querySelector('img').src, placeholder);
  assert.equal(win.document.querySelectorAll('button,iframe,script[src],link[href]').length, 0);
  assert.equal(win.document.querySelector('h1').textContent, 'Игры');
  assert.equal(win.document.querySelector('header img').alt, 'UGames');
});

test('a normal online game or catalogue receives no extra offline interface', (t) => {
  const win = page(t, undefined, (w) => {
    w.document.body.innerHTML = '<canvas></canvas>';
  });
  assert.equal(win.document.body.innerHTML, '<canvas></canvas>');
  assert.equal(win.__UGamesOfflineCatalog, undefined);
});

test('unsafe game targets are omitted and game titles remain plain text', (t) => {
  const title = '<img src=x onerror="window.injected=true">';
  const win = page(t, {
    version: 1,
    games: [
      { url: 'javascript:alert(1)', title: 'Bad' },
      { url: 'https://evil.test/game/index.html', title: 'Other' },
      { url: 'https://user:password@app-42.games.yandex.net/index.html', title: 'Credentials' },
      { url: 'https://app-42.games.yandex.net:8443/index.html', title: 'Port' },
      { url, title },
    ],
  });
  assert.equal(win.document.querySelectorAll('.game-card__link').length, 1);
  assert.equal(win.document.querySelector('.game-card__title').textContent, title);
  assert.equal(win.document.querySelectorAll('[onerror]').length, 0);
  assert.equal(win.injected, undefined);
});

test('remote artwork is not requested and failed local covers use the bundled placeholder', (t) => {
  const local = 'ugames-offline://yandex.ru/games/_covers/' + 'b'.repeat(64);
  const win = page(t, {
    version: 1,
    games: [
      { url, title: 'Local', cover: local },
      {
        url: url.replace('42', '43'),
        title: 'Remote',
        cover: 'https://avatars.mds.yandex.net/get-games/43/cover.jpg',
      },
    ],
  });
  const images = win.document.querySelectorAll('.game-card__image');
  assert.equal(images[0].src, local);
  assert.equal(images[1].src, placeholder);
  images[0].dispatchEvent(new win.Event('error'));
  assert.equal(images[0].src, placeholder);
  images[0].dispatchEvent(new win.Event('error'));
  assert.equal(images[0].src, placeholder);
});

test('empty cache stays in the catalogue without save, delete, library or setup controls', (t) => {
  const win = page(t, { version: 1, games: [] });
  assert.ok(win.document.querySelector('[role="status"]').textContent.includes('интернет'));
  assert.equal(win.document.querySelectorAll('button,input,[role="menu"]').length, 0);
  assert.equal(win.document.querySelector('header a').href, 'https://yandex.ru/games/');
});

test('native catalogue refresh replaces cards without duplicating document or styles', (t) => {
  const win = page(t, { version: 1, games: [{ url, title: 'Before' }] });
  win.eval(source());
  win.__UGamesCachedCatalog = { version: 1, games: [{ url, title: 'After' }] };
  assert.equal(typeof win.__UGamesOfflineCatalog?.render, 'function');
  win.__UGamesOfflineCatalog.render();
  assert.equal(win.document.querySelectorAll('.game-card__link').length, 1);
  assert.equal(win.document.querySelector('.game-card__title').textContent, 'After');
  assert.equal(win.document.querySelectorAll('h1').length, 1);
  assert.equal(win.document.querySelectorAll('style[data-ugames-cached-catalog-style]').length, 1);
});

test('catalogue renderer waits for the document body at native document start', (t) => {
  const win = page(t, { version: 1, games: [{ url, title: 'Loaded' }] }, (w) => {
    Object.defineProperty(w.document, 'readyState', { value: 'loading', configurable: true });
    w.document.body.remove();
  });
  win.document.documentElement.appendChild(win.document.createElement('body'));
  win.document.dispatchEvent(new win.Event('DOMContentLoaded'));
  assert.equal(win.document.querySelector('.game-card__title').textContent, 'Loaded');
});

test('the complete native script keeps one catalogue theme and permits its cached card navigation', (t) => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'ugames-catalog-bundle-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  fs.symlinkSync(path.join(__dirname, '..'), path.join(directory, 'shared'), 'dir');
  buildShared(directory);
  const bundle = fs.readFileSync(
    path.join(directory, 'ios/UGames/Resources/ad-adapter.js'),
    'utf8',
  );
  for (const origin of ['https://yandex.ru/games/', 'ugames-offline://yandex.ru/games/']) {
    const dom = new JSDOM('<!doctype html><title>UGames</title><body></body>', {
      url: origin,
      runScripts: 'outside-only',
    });
    t.after(() => dom.window.close());
    const win = dom.window;
    Object.defineProperty(win.document, 'readyState', { value: 'complete' });
    win.__UGamesCachedCatalog = { version: 1, games: [{ url, title: 'Игра' }] };
    win.navigation = new win.EventTarget();
    win.eval(bundle);
    assert.equal(win.document.querySelectorAll('style').length, 1);
    const card = win.document.querySelector('.game-card__link');
    assert.equal(card.href, url);
    const event = new win.Event('navigate', { cancelable: true });
    event.destination = { url: card.href };
    assert.equal(win.navigation.dispatchEvent(event), true);
  }
});
