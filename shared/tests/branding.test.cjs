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
