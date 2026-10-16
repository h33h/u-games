'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');
const theme = fs.readFileSync(path.join(__dirname, '../portal-theme.js'), 'utf8');
const settle = () => new Promise((resolve) => setTimeout(resolve, 10));
const assets = { logo: 'data:image/svg+xml,UGames-logo', icon: 'data:image/svg+xml,UGames-icon' };
const portalCSS = fs
  .readFileSync(path.join(__dirname, '../portal-theme.css'), 'utf8')
  .replace(/\{\{[^}]+\}\}/g, 'data:image/svg+xml,test');

function catalogCard(t) {
  const dom = new JSDOM(
    '<style>.game-card {background-color:transparent;border-radius:0}.game-card__graphic {position:relative;border-radius:13px}</style><div class="grid-list"><div class="grid-list__game-item"><div class="game-card"><div class="game-card__graphic"><a href="/games/app/123"><img class="game-image"></a></div><div class="game-card__description">Игра</div></div></div></div>',
    { url: 'https://yandex.ru/games/', runScripts: 'outside-only' },
  );
  t.after(() => dom.window.close());
  dom.window.__UGamesBranding = { assets, css: portalCSS };
  dom.window.eval(theme);
  return dom.window;
}

test('leaves catalog card wrappers transparent instead of painting boxes behind captions', (t) => {
  const win = catalogCard(t);
  assert.equal(
    win.getComputedStyle(win.document.querySelector('.game-card')).backgroundColor,
    'rgba(0, 0, 0, 0)',
  );
});

test('preserves the cover corner geometry rather than inheriting the square card wrapper', (t) => {
  const win = catalogCard(t);
  assert.equal(
    win.getComputedStyle(win.document.querySelector('.game-card__graphic')).borderRadius,
    '13px',
  );
});

test('reports the visible page background to both native shells after theme changes', async (t) => {
  const dom = new JSDOM(
    '<html style="background:#eeeeee"><body style="background:#171520"></body></html>',
    {
      url: 'https://yandex.ru/games/',
      runScripts: 'outside-only',
    },
  );
  t.after(() => dom.window.close());
  const win = dom.window;
  const android = [];
  const ios = [];
  win.__UGamesAppearance = { postMessage: (color) => android.push(color) };
  win.webkit = {
    messageHandlers: { ugamesAppearance: { postMessage: (color) => ios.push(color) } },
  };
  win.eval(theme);
  await settle();
  assert.equal(android.at(-1), '#171520');
  assert.equal(ios.at(-1), '#171520');
  win.document.body.style.backgroundColor = '#fafafa';
  await settle();
  assert.equal(android.at(-1), '#fafafa');
  assert.equal(ios.at(-1), '#fafafa');
  win.document.body.style.backgroundColor = 'transparent';
  await settle();
  assert.equal(android.at(-1), '#eeeeee');
  win.document.body.append(win.document.createElement('p'));
  await settle();
  assert.equal(android.length, 3);
});

test('embedded game frames cannot replace the shell background', async (t) => {
  const win = page(t, '<iframe></iframe>');
  const child = win.document.querySelector('iframe').contentWindow;
  let reports = 0;
  child.__UGamesAppearance = { postMessage: () => reports++ };
  child.eval(theme);
  await settle();
  assert.equal(reports, 0);
});
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

test('replaces default account artwork and restores personal avatars when the image is reused', async (t) => {
  const win = page(
    t,
    '<picture><source srcset="default.webp"><img class="user-account-pic__image" src="https://avatars.mds.yandex.net/get-yapic/0/0-0/islands-middle"></picture>',
  );
  const image = win.document.querySelector('img');
  assert.equal(image.src, assets.icon);
  assert.equal(win.document.querySelector('source').getAttribute('srcset'), null);
  image.src = 'https://avatars.mds.yandex.net/get-yapic/123/player/islands-middle';
  await settle();
  assert.equal(image.src, 'https://avatars.mds.yandex.net/get-yapic/123/player/islands-middle');
});

test('replaces portal illustrations in img and picture elements but preserves game artwork', async (t) => {
  const win = page(
    t,
    '<picture><source srcset="controller.webp"><img class="authorization__image" src="controller.png"></picture><img id="game" src="https://avatars.mds.yandex.net/get-games/123/orig">',
  );
  const image = win.document.querySelector('img');
  assert.equal(image.src, assets.icon);
  win.document.querySelector('source').srcset = 'old-controller.webp';
  await settle();
  assert.equal(win.document.querySelector('source').getAttribute('srcset'), null);
  assert.equal(
    win.document.querySelector('#game').src,
    'https://avatars.mds.yandex.net/get-games/123/orig',
  );
});

test('updates the game shell theme on history navigation without waiting for DOM changes', async (t) => {
  const win = page(t, '<main>Каталог</main>');
  win.history.pushState({}, '', '/games/app/123');
  await settle();
  assert.equal(win.document.documentElement.dataset.ugamesPage, 'game');
  win.history.replaceState({}, '', '/games/profile/me');
  await settle();
  assert.equal(win.document.documentElement.dataset.ugamesPage, 'catalog');
});

test('recognizes portal illustrations supplied only by responsive picture sources', async (t) => {
  const win = page(
    t,
    '<picture><source srcset="https://yastatic.net/s3/games-static/static-data/images/art/purple_close.png 2x"><img src="placeholder.gif"></picture>',
  );
  const image = win.document.querySelector('img');
  assert.equal(image.src, assets.icon);
  assert.equal(win.document.querySelector('source').getAttribute('srcset'), null);
  const picture = win.document.createElement('picture');
  picture.innerHTML = '<img src="placeholder.gif">';
  win.document.body.append(picture);
  await settle();
  picture.insertAdjacentHTML(
    'afterbegin',
    '<source srcset="https://yastatic.net/s3/games-static/static-data/images/shop/shortcuts/game-keys.webp 2x">',
  );
  await settle();
  assert.equal(picture.querySelector('img').src, assets.icon);
});

test('replaces inline CSS artwork without discarding gradients or custom player backgrounds', async (t) => {
  const win = page(
    t,
    '<div id="art" style="background-image:linear-gradient(black, transparent), url(https://yastatic.net/s3/games-static/static-data/images/art/purple_close.png)"></div>',
  );
  const element = win.document.querySelector('#art');
  assert.ok(element.style.backgroundImage.includes(assets.icon));
  assert.match(element.style.backgroundImage, /linear-gradient/);
  element.style.backgroundImage =
    'url(https://avatars.mds.yandex.net/get-games/123/player-background)';
  await settle();
  assert.match(element.style.backgroundImage, /123\/player-background/);
});

test('replaces portal illustrations embedded in SVG image nodes', (t) => {
  const win = page(
    t,
    '<svg><image href="https://yastatic.net/s3/games-static/static-data/images/art/purple_close.png"/></svg>',
  );
  assert.equal(win.document.querySelector('image').getAttribute('href'), assets.icon);
});

test('uses a local fallback for failed covers and accepts a later successful source', async (t) => {
  const win = page(
    t,
    '<a href="/games/app/123"><img class="game-image" alt="Головоломка" src="https://example.test/missing.webp" srcset="https://example.test/missing@2x.webp 2x"></a>',
  );
  const image = win.document.querySelector('img');
  image.dispatchEvent(new win.Event('error'));
  await settle();
  assert.equal(image.src, assets.icon);
  assert.equal(image.getAttribute('srcset'), null);
  assert.equal(image.alt, 'Головоломка');
  assert.equal(win.document.querySelector('a').pathname, '/games/app/123');
  image.src = 'https://example.test/working.webp';
  await settle();
  assert.equal(image.src, 'https://example.test/working.webp');
});

test('allows responsive pictures to recover from a failed cover', async (t) => {
  const win = page(
    t,
    '<picture><source srcset="https://example.test/missing.webp"><img class="game-image" src="https://example.test/missing.png"></picture>',
  );
  const image = win.document.querySelector('img');
  image.dispatchEvent(new win.Event('error'));
  await settle();
  const source = win.document.querySelector('source');
  source.srcset = 'https://example.test/recovered.webp 2x';
  await settle();
  assert.equal(source.srcset, 'https://example.test/recovered.webp 2x');
  assert.equal(image.hasAttribute('data-ugames-image-fallback'), false);
});

test('lets responsive sources replace a themed default avatar with a personal avatar', async (t) => {
  for (const picture of [false, true]) {
    const win = page(
      t,
      picture
        ? '<picture><source srcset="https://avatars.mds.yandex.net/get-yapic/0/0-0/islands-middle 2x"><img src="placeholder.gif"></picture>'
        : '<img src="placeholder.gif" srcset="https://avatars.mds.yandex.net/get-yapic/0/0-0/islands-middle 2x">',
    );
    const image = win.document.querySelector('img');
    assert.equal(image.src, assets.icon);
    const responsive = win.document.querySelector('source') || image;
    responsive.srcset = 'https://avatars.mds.yandex.net/get-yapic/123/player/islands-200 2x';
    await settle();
    assert.equal(
      responsive.srcset,
      'https://avatars.mds.yandex.net/get-yapic/123/player/islands-200 2x',
    );
  }
});

test('replaces CSS logos and proxied relative art while preserving lookalike source hosts', (t) => {
  const win = page(
    t,
    '<div id="logo" style="background-image:url(https://yastatic.net/s3/games-static/static-data/images/logo/v2/yandex/ru/logo-light.png)"></div><picture><source srcset="/games/cdn/games-static/static-data/images/art/purple_close.webp 2x"><img id="art" src="placeholder.gif"></picture><img id="unrelated" src="https://yastatic.net.evil.test/s3/games-static/static-data/images/art/purple_close.png">',
  );
  assert.ok(win.document.querySelector('#logo').style.backgroundImage.includes(assets.logo));
  assert.equal(win.document.querySelector('#art').src, assets.icon);
  assert.equal(
    win.document.querySelector('#unrelated').src,
    'https://yastatic.net.evil.test/s3/games-static/static-data/images/art/purple_close.png',
  );
});
