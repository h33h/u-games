'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');
const source = fs.readFileSync(path.join(__dirname, '../ad-adapter.js'), 'utf8');
const settle = () => new Promise((resolve) => setTimeout(resolve, 10));

function page(t, html) {
  const dom = new JSDOM(html, { runScripts: 'outside-only', url: 'https://yandex.ru/games/' });
  t.after(() => dom.window.close());
  dom.window.eval(source);
  return dom.window;
}

test('rebrands visible text, title and accessible labels without changing URLs or game code', (t) => {
  const win = page(
    t,
    `<title>Яндекс\u00a0Игры — каталог</title>
    <a href="https://yandex.ru/games/" title="Yandex Games">Яндекс Игры</a>
    <p>Игры от Яндекса и YANDEX. https://yandex.ru/games/</p>
    <button aria-label="Войти через Яндекс">Войти</button>
    <input placeholder="Поиск в Яндекс Играх" value="Яндекс">
    <div contenteditable="true">Яндекс</div>
    <script>window.provider = 'Yandex';</script><style>.yandex { color: red; }</style>`,
  );
  const doc = win.document;
  assert.equal(doc.title, 'UGames — каталог');
  assert.equal(doc.querySelector('a').textContent, 'UGames');
  assert.equal(doc.querySelector('a').title, 'UGames');
  assert.equal(doc.querySelector('a').href, 'https://yandex.ru/games/');
  assert.equal(
    doc.querySelector('p').textContent,
    'Игры от UGames и UGames. https://yandex.ru/games/',
  );
  assert.equal(doc.querySelector('button').getAttribute('aria-label'), 'Войти через UGames');
  assert.equal(doc.querySelector('input').placeholder, 'Поиск в UGames');
  assert.equal(doc.querySelector('input').value, 'Яндекс');
  assert.equal(doc.querySelector('[contenteditable]').textContent, 'Яндекс');
  assert.equal(doc.querySelector('script').textContent, "window.provider = 'Yandex';");
  assert.equal(doc.querySelector('style').textContent, '.yandex { color: red; }');
});

test('replaces portal logo artwork while preserving the clickable catalog link and unrelated images', (t) => {
  const win = page(
    t,
    `<a class="logo-link" title="yandex" href="/games/"><span><img alt="Яндекс Игры" src="logo.png" srcset="logo@2x.png 2x"></span></a><img id="game" alt="Гонки" src="game.png">`,
  );
  const doc = win.document;
  const logo = doc.querySelector('.logo-link img');
  assert.match(decodeURIComponent(logo.src), /UGames/);
  assert.equal(logo.alt, 'UGames');
  assert.equal(logo.getAttribute('srcset'), null);
  assert.equal(doc.querySelector('a').href, 'https://yandex.ru/games/');
  assert.equal(doc.querySelector('#game').getAttribute('src'), 'game.png');
});

test('rebrands late nodes, edited text, updated labels and logos without replacing controls', async (t) => {
  const win = page(t, '<button>Играть</button>');
  const button = win.document.querySelector('button');
  let clicks = 0;
  button.addEventListener('click', () => clicks++);
  button.firstChild.data = 'Яндекс Игры';
  button.setAttribute('title', 'Yandex');
  const container = win.document.createElement('div');
  container.innerHTML = '<p>Яндекс</p><img alt="Yandex Games" src="logo.png">';
  win.document.body.append(container);
  await settle();
  assert.equal(button.textContent, 'UGames');
  assert.equal(button.title, 'UGames');
  assert.equal(container.querySelector('p').textContent, 'UGames');
  const logo = container.querySelector('img');
  logo.src = 'restored-logo.png';
  await settle();
  assert.match(decodeURIComponent(logo.src), /UGames/);
  button.click();
  assert.equal(clicks, 1);
});

test('rebrands existing and newly attached shadow roots including closed roots', async (t) => {
  const win = page(t, '<div id="host"></div>');
  const shadow = win.document.querySelector('#host').attachShadow({ mode: 'closed' });
  shadow.innerHTML = '<span>Яндекс Игры</span>';
  await settle();
  assert.equal(shadow.textContent, 'UGames');
  const host = win.document.createElement('div');
  const existing = host.attachShadow({ mode: 'open' });
  existing.innerHTML = '<span>Yandex Games</span>';
  win.document.body.append(host);
  await settle();
  assert.equal(existing.textContent, 'UGames');
});

test('document-start injection rebrands content parsed later and blank popups', async (t) => {
  const win = page(t, '');
  const popup = new JSDOM('', { runScripts: 'outside-only' });
  t.after(() => popup.window.close());
  win.open = () => popup.window;
  // Install in a fresh parent so its popup hook sees the supplied open implementation.
  const parent = new JSDOM('', { runScripts: 'outside-only' });
  t.after(() => parent.window.close());
  parent.window.open = () => popup.window;
  parent.window.eval(source);
  parent.window.open('about:blank').document.body.innerHTML = '<h1>Yandex Games</h1>';
  win.document.body.innerHTML = '<h1>Яндекс Игры</h1>';
  await settle();
  assert.equal(win.document.querySelector('h1').textContent, 'UGames');
  assert.equal(popup.window.document.querySelector('h1').textContent, 'UGames');
});

test('replaces CSS and inline SVG portal logos without altering unrelated icons', (t) => {
  const win = page(
    t,
    `<span class="Icon Icon_type_logo-games" style="background-image: url(logo.svg)"></span>
    <svg aria-label="Яндекс Игры"><path d="M0 0h20v20z"/></svg>
    <svg id="game-icon" aria-label="Настройки"><path d="M0 0h10v10z"/></svg>`,
  );
  const icon = win.document.querySelector('.Icon_type_logo-games');
  assert.equal(icon.textContent, 'UGames');
  assert.equal(icon.style.backgroundImage, 'none');
  const logo = win.document.querySelector('svg');
  assert.equal(logo.querySelector('path'), null);
  assert.equal(logo.textContent, 'UGames');
  assert.ok(win.document.querySelector('#game-icon path'));
});

test('prevents responsive picture sources from restoring the original branded artwork', async (t) => {
  const win = page(
    t,
    '<picture><source srcset="logo.webp"><img alt="Yandex Games" src="logo.png"></picture>',
  );
  const source = win.document.querySelector('source');
  assert.equal(source.getAttribute('srcset'), null);
  await settle();
  source.setAttribute('srcset', 'restored.webp');
  await settle();
  assert.equal(source.getAttribute('srcset'), null);
});

test('rebrands dotted, hyphenated and split brand names while preserving controls', (t) => {
  const win = page(
    t,
    `<p>Яндекс.Игры / Yandex.Games / Яндекс-Игры / Yandex Games</p>
    <a href="/games/"><span>Ян</span><strong>декс</strong> <span>Игры</span></a>`,
  );
  const link = win.document.querySelector('a');
  assert.equal(win.document.querySelector('p').textContent, 'UGames / UGames / UGames / UGames');
  assert.equal(link.textContent, 'UGames');
  assert.equal(link.querySelectorAll('span').length, 2);
  assert.equal(link.href, 'https://yandex.ru/games/');
});

test('rebrands page metadata and icons and keeps navigation metadata intact', async (t) => {
  const win = page(
    t,
    `<meta property="og:title" content="Яндекс Игры — каталог">
    <meta property="og:site_name" content="Яндекс Игры">
    <meta property="og:url" content="https://yandex.ru/games/">
    <meta property="og:image" content="https://static.games.yandex.net/opengraph/ru/default.png">
    <meta name="twitter:image" content="https://example.test/game.png">
    <link rel="icon" href="https://yastatic.net/s3/games-static/favicons/yandex/favicon.ico">
    <link rel="apple-touch-icon" href="https://yastatic.net/s3/games-static/favicons/yandex/apple-touch-icon.png">`,
  );
  const doc = win.document;
  assert.equal(doc.querySelector('[property="og:title"]').content, 'UGames — каталог');
  assert.equal(doc.querySelector('[property="og:site_name"]').content, 'UGames');
  assert.equal(doc.querySelector('[property="og:url"]').content, 'https://yandex.ru/games/');
  assert.match(decodeURIComponent(doc.querySelector('[property="og:image"]').content), /UGames/);
  assert.equal(
    doc.querySelector('[name="twitter:image"]').content,
    'https://example.test/game.png',
  );
  for (const icon of doc.querySelectorAll('link')) {
    assert.match(decodeURIComponent(icon.href), /UGames/);
  }
  doc.querySelector('[property="og:title"]').content = 'Yandex Games';
  doc.querySelector('link').href = 'https://yastatic.net/s3/games-static/favicons/yandex/logo.svg';
  await settle();
  assert.equal(doc.querySelector('[property="og:title"]').content, 'UGames');
  assert.match(decodeURIComponent(doc.querySelector('link').href), /UGames/);
});

test('replaces unlabelled portal artwork without rebranding game thumbnails', async (t) => {
  const win = page(
    t,
    `<a class="logo-link" href="/games/"><svg><use href="#portal-logo"/></svg></a>
    <img id="logo" src="https://yastatic.net/s3/games-static/static-data/images/single-logo/games/short_color_bgdark_ru.png">
    <img id="thumbnail" alt="Игра Яндекс" src="https://avatars.mds.yandex.net/get-games/123/orig">`,
  );
  const doc = win.document;
  assert.equal(doc.querySelector('svg').textContent, 'UGames');
  assert.equal(doc.querySelector('svg use'), null);
  assert.match(decodeURIComponent(doc.querySelector('#logo').src), /UGames/);
  assert.equal(
    doc.querySelector('#thumbnail').src,
    'https://avatars.mds.yandex.net/get-games/123/orig',
  );
  doc.querySelector('svg').innerHTML = '<path d="M0 0h20v20z"/>';
  await settle();
  assert.equal(doc.querySelector('svg path'), null);
  assert.equal(doc.querySelector('svg').textContent, 'UGames');
});

test('rebrands textarea labels while preserving user text', (t) => {
  const win = page(
    t,
    '<textarea placeholder="Отзывы о Яндекс Играх" aria-label="Яндекс Игры">Яндекс</textarea>',
  );
  const input = win.document.querySelector('textarea');
  assert.equal(input.placeholder, 'Отзывы о UGames');
  assert.equal(input.getAttribute('aria-label'), 'UGames');
  assert.equal(input.value, 'Яндекс');
});

test('uses bundled wordmark and compact app mark without disturbing links', (t) => {
  const dom = new JSDOM(
    '<a class="logo-link" href="/games/"><img alt="Яндекс Игры" src="logo.png"></a><link rel="icon" href="https://yastatic.net/s3/games-static/favicons/yandex/logo.svg">',
    { runScripts: 'outside-only', url: 'https://yandex.ru/games/' },
  );
  t.after(() => dom.window.close());
  dom.window.__UGamesBranding = {
    assets: { logo: 'data:image/svg+xml,UGames-wordmark', icon: 'data:image/svg+xml,UGames-mark' },
  };
  dom.window.eval(source);
  assert.equal(dom.window.document.querySelector('img').src, 'data:image/svg+xml,UGames-wordmark');
  assert.equal(dom.window.document.querySelector('link').href, 'data:image/svg+xml,UGames-mark');
  assert.equal(dom.window.document.querySelector('a').href, 'https://yandex.ru/games/');
});

test('split brand normalization stops producing DOM mutations once settled', async (t) => {
  const dom = new JSDOM('<a><span>Ян</span><strong>декс</strong> <span>Игры</span></a>', {
    runScripts: 'outside-only',
    url: 'https://yandex.ru/games/',
  });
  t.after(() => dom.window.close());
  const realObserver = dom.window.MutationObserver;
  let callbacks = 0;
  dom.window.MutationObserver = class extends realObserver {
    constructor(callback) {
      super((records, observer) => {
        callbacks++;
        // Bound the regression so an event-loop starvation bug can be reported.
        if (callbacks > 20) {
          observer.disconnect();
          return;
        }
        callback(records, observer);
      });
    }
  };
  dom.window.eval(source);
  await settle();
  assert.equal(dom.window.document.querySelector('a').textContent, 'UGames');
  assert.ok(callbacks < 20, 'brand normalization keeps scheduling observer callbacks');
});
