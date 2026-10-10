'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');
const theme = fs.readFileSync(path.join(__dirname, '../portal-theme.js'), 'utf8');
const settle = () => new Promise((resolve) => setTimeout(resolve, 10));
const assets = { logo: 'data:image/svg+xml,UGames-logo', icon: 'data:image/svg+xml,UGames-icon' };
function page(t, html, url = 'https://yandex.ru/games/') {
  const dom = new JSDOM(html, { url, runScripts: 'outside-only' });
  t.after(() => dom.window.close());
  dom.window.__UGamesBranding = {
    assets,
    css: '[data-ugames-theme] button {font-family: system-ui, sans-serif;}',
  };
  dom.window.eval(theme);
  return dom.window;
}
test('installs local styling on portal pages and preserves game and authentication documents', (t) => {
  const win = page(t, '<button>Играть</button>');
  assert.equal(win.document.documentElement.dataset.ugamesTheme, 'violet-mint');
  assert.match(win.getComputedStyle(win.document.querySelector('button')).fontFamily, /system-ui/);
  for (const url of [
    'https://app-123.cdn.games.yandex.net/game/',
    'https://passport.yandex.ru/auth',
    'https://yandex.ru.evil.test/games/',
    'https://yandex.ru/support/games/',
  ]) {
    const other = page(t, '<button>Играть</button>', url);
    assert.equal(other.document.querySelector('#ugames-portal-theme'), null);
    assert.equal(other.document.documentElement.dataset.ugamesTheme, undefined);
  }
});
test('restores the theme after portal rerenders without replacing controls', async (t) => {
  const win = page(t, '<button>Играть</button>');
  let clicks = 0;
  const button = win.document.querySelector('button');
  button.addEventListener('click', () => clicks++);
  win.document.querySelector('#ugames-portal-theme').remove();
  win.document.documentElement.removeAttribute('data-ugames-theme');
  await settle();
  button.click();
  assert.equal(clicks, 1);
  assert.equal(win.document.querySelectorAll('#ugames-portal-theme').length, 1);
  assert.equal(win.document.documentElement.dataset.ugamesTheme, 'violet-mint');
});
test('styles late shadow roots and keeps the game canvas intact', async (t) => {
  const win = page(t, '<div id="host"></div><canvas id="game"></canvas>');
  const canvas = win.document.querySelector('canvas');
  const root = win.document.querySelector('#host').attachShadow({ mode: 'closed' });
  root.innerHTML = '<button>Играть</button>';
  await settle();
  assert.ok(root.querySelector('#ugames-portal-theme'));
  assert.equal(win.document.querySelector('canvas'), canvas);
});

test('replaces storefront category artwork and restores responsive sources without changing products', async (t) => {
  const win = page(
    t,
    '<a href="/games/shop/keys"><picture><source srcset="old.webp"><img id="shortcut" src="https://yastatic.net/s3/games-static/static-data/images/shop/shortcuts/game-keys.png"></picture></a><img id="product" src="https://example.test/product.png">',
    'https://yandex.ru/games/shop',
  );
  const image = win.document.querySelector('#shortcut');
  assert.equal(image.src, 'data:image/svg+xml,UGames-icon');
  assert.equal(win.document.querySelector('source').getAttribute('srcset'), null);
  image.src =
    'https://yastatic.net/s3/games-static/static-data/images/shop/shortcuts/game-keys.png';
  await settle();
  assert.equal(image.src, 'data:image/svg+xml,UGames-icon');
  assert.equal(win.document.querySelector('#product').src, 'https://example.test/product.png');
  assert.equal(win.document.querySelector('a').pathname, '/games/shop/keys');
});
