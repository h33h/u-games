'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');
const source = fs.readFileSync(path.join(__dirname, '../ad-adapter.js'), 'utf8');
const rules = JSON.parse(fs.readFileSync(path.join(__dirname, '../ad-rules.json'), 'utf8'));
const settle = () => new Promise((resolve) => setTimeout(resolve, 10));
function page(t, html, prepare = () => {}) {
  const dom = new JSDOM(html, { runScripts: 'outside-only', url: 'https://yandex.ru/games/' });
  t.after(() => dom.window.close());
  dom.window.__UGamesRules = rules;
  prepare(dom.window);
  dom.window.eval(source);
  return dom.window;
}
function hidden(element) {
  assert.equal(element.style.getPropertyValue('display'), 'none');
  assert.equal(element.style.getPropertyPriority('display'), 'important');
}

test('hides catalog ad tiles and feed placeholders while preserving regular games', (t) => {
  const win = page(
    t,
    `<ul><li id="ad" class="grid-list__game-item grid-list__game-item_adv"><div data-testid="feed-grid-banner"></div></li><li id="game" class="grid-list__game-item"><a href="/games/app/123">Играть</a></li></ul><div id="feed" data-testid="feed-banner-0"></div>`,
  );
  hidden(win.document.querySelector('#ad'));
  hidden(win.document.querySelector('#feed'));
  assert.equal(win.document.querySelector('#game').style.display, '');
});

test('removes the whole sponsored card slot rather than only its link or badge', (t) => {
  const win = page(
    t,
    `<ul><li id="sponsored" class="grid-list__game-item"><div class="game-card"><a href="/games/app/123?utm_source=game_promo_catalog&yclid=42">Промо</a></div></li><li id="organic" class="grid-list__game-item"><div class="game-card"><a href="/games/app/456#referrer=promo&promo_type=discount">Скидка</a></div></li></ul><div id="badged" class="game-card"><div class="game-badges__sticky-badge" title="Промо"></div></div>`,
  );
  hidden(win.document.querySelector('#sponsored'));
  hidden(win.document.querySelector('#badged'));
  assert.equal(win.document.querySelector('#organic').style.display, '');
});

test('suppresses late ad markers and restores protection when a page resets inline styles', async (t) => {
  const win = page(t, '<div id="card" class="game-card"><a href="/games/app/123">Играть</a></div>');
  const card = win.document.querySelector('#card');
  card.querySelector('a').href = '/games/app/123?utm_source=game_promo_catalog';
  await settle();
  hidden(card);
  card.style.setProperty('display', 'block', 'important');
  await settle();
  hidden(card);
});

test('hides ad subscription menu controls without hiding unrelated navigation', (t) => {
  const win = page(
    t,
    '<nav><button id="ads"><span class="Icon_type_no-ads"></span>Отключить рекламу</button><button id="back">Назад</button></nav>',
  );
  hidden(win.document.querySelector('#ads'));
  assert.equal(win.document.querySelector('nav').style.display, '');
  assert.equal(win.document.querySelector('#back').style.display, '');
});

for (const mode of ['open', 'closed']) {
  test(`suppresses catalog ads in newly attached ${mode} shadow roots`, async (t) => {
    const win = page(t, '<div id="host"></div>');
    const root = win.document.querySelector('#host').attachShadow({ mode });
    root.innerHTML =
      '<div id="ad" data-testid="feed-banner-1"></div><button id="game">Играть</button>';
    await settle();
    hidden(root.querySelector('#ad'));
    assert.equal(root.querySelector('#game').style.display, '');
  });
}

test('suppresses ads in existing shadow roots and roots inserted after injection', async (t) => {
  let existing;
  const win = page(t, '<div id="host"></div>', (w) => {
    existing = w.document.querySelector('#host').attachShadow({ mode: 'open' });
    existing.innerHTML = '<div id="ad" data-testid="feed-banner-0"></div>';
  });
  hidden(existing.querySelector('#ad'));
  const host = win.document.createElement('div');
  const root = host.attachShadow({ mode: 'open' });
  root.innerHTML = '<div id="ad" class="grid-list__game-item_adv"></div>';
  win.document.body.append(host);
  await settle();
  hidden(root.querySelector('#ad'));
});

test('closes an existing shadow fullscreen ad once so portal navigation can resume', async (t) => {
  let root,
    closes = 0;
  const win = page(t, '<div id="host"></div>', (w) => {
    root = w.document.querySelector('#host').attachShadow({ mode: 'open' });
    root.innerHTML =
      '<a href="https://yandex.ru/games/_crpd/123">Реклама</a><button data-fullscreen-element="close">Закрыть</button>';
    root.querySelector('button').addEventListener('click', () => closes++);
  });
  await settle();
  hidden(win.document.querySelector('#host'));
  assert.equal(closes, 1);
});

test('hides the promotional carousel including store advertisements without hiding the game catalog', (t) => {
  const win = page(
    t,
    '<div id="promo" data-testid="banner-carousel-container"><a href="https://yandex.ru/games/shop">За покупками</a><button>Рекламная подборка</button></div><div id="catalog" class="game-card"><a href="/games/app/123">Играть</a></div>',
  );
  hidden(win.document.querySelector('#promo'));
  assert.equal(win.document.querySelector('#catalog').style.display, '');
});
