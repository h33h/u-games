'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');
const source = fs.readFileSync(path.join(__dirname, '../ad-adapter.js'), 'utf8');
const rules = JSON.parse(fs.readFileSync(path.join(__dirname, '../ad-rules.json'), 'utf8'));
const settle = () => new Promise((resolve) => setTimeout(resolve, 10));
function page(t, html, prepare = () => {}, url = 'https://yandex.ru/games/') {
  const dom = new JSDOM(html, { runScripts: 'outside-only', url });
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

test('collapses entire carousel, sticky and ad removal promotion placements', (t) => {
  const win = page(
    t,
    `<div id="carousel" data-testid="feed-block-carousel" style="padding-bottom:26px"><div class="banner-carousel-critical-catalog-module__root--salted"><div data-testid="banner-carousel-container"></div></div></div>
    <aside id="sticky" class="adv-sticky-banner__desktop-wrapper" style="width:315px"><div class="adv-sticky-banner"></div></aside>
    <div id="landscape" class="adv-sticky-banner__landscape-wrapper" style="height:100px"></div>
    <div id="button-slot" class="adv-sticky-banner-manager-critical-game-module__disableAdButtonSlot--salted"></div>
    <div id="upsell" class="promo-noads-price-placement-critical-game-module__root--salted"><button>Отключить рекламу</button></div>
    <div id="rotate" class="rotate-banner">Поверните экран</div><button id="login">Войти</button>`,
  );
  for (const id of ['carousel', 'sticky', 'landscape', 'button-slot', 'upsell']) {
    hidden(win.document.getElementById(id));
  }
  for (const id of ['rotate', 'login']) {
    assert.notEqual(win.getComputedStyle(win.document.getElementById(id)).display, 'none');
  }
});

test('collapses ad-only feed and grid wrappers while preserving mixed game sections', (t) => {
  const win = page(
    t,
    `<main><div id="feed" class="feed" style="padding:24px"><div id="section" class="feed__section"><div data-testid="feed-banner-1"></div></div></div>
    <div id="mixed" class="feed__section"><div data-testid="feed-grid-banner"></div><button id="game">Играть</button></div>
    <ul><li id="tile" class="grid-list__game-item"><div data-testid="feed-grid-banner"></div></li><li id="organic" class="grid-list__game-item">Игра</li></ul></main>`,
  );
  for (const id of ['feed', 'section', 'tile']) {
    hidden(win.document.getElementById(id));
  }
  for (const id of ['mixed', 'game', 'organic']) {
    assert.notEqual(win.getComputedStyle(win.document.getElementById(id)).display, 'none');
  }
  assert.notEqual(win.getComputedStyle(win.document.querySelector('main')).display, 'none');
});

test('restores a collapsed feed wrapper when the portal reuses it for games', async (t) => {
  const win = page(
    t,
    '<div id="feed" class="feed" style="display:flex"><div id="section" class="feed__section" style="visibility:visible"><div data-testid="feed-banner-1"></div></div></div>',
  );
  const feed = win.document.getElementById('feed');
  const section = win.document.getElementById('section');
  hidden(feed);
  hidden(section);
  section.innerHTML = '<button>Играть</button>';
  let clicks = 0;
  section.firstElementChild.addEventListener('click', () => clicks++);
  await settle();
  assert.equal(feed.style.display, 'flex');
  assert.equal(section.style.visibility, 'visible');
  assert.notEqual(win.getComputedStyle(section).display, 'none');
  section.firstElementChild.click();
  assert.equal(clicks, 1);
});

test('collapses late ad-only shadow slots without changing game document layout', async (t) => {
  const win = page(t, '<div id="host"></div>');
  const root = win.document.getElementById('host').attachShadow({ mode: 'closed' });
  root.innerHTML = '<div class="feed__section"><div data-testid="feed-banner-1"></div></div>';
  await settle();
  hidden(root.firstElementChild);
  const game = page(
    t,
    '<div class="feed__section"><div data-testid="feed-banner-1"></div></div>',
    () => {},
    'https://app-123.cdn.games.yandex.net/game/',
  );
  assert.equal(game.document.querySelector('.feed__section').style.display, '');
});

test('collapses the outer feed slot when a closed shadow ad is dismissed', async (t) => {
  const win = page(
    t,
    '<div class="feed"><div id="slot" class="feed__section" style="height:300px"><div id="host"></div></div><button id="game">Играть</button></div>',
  );
  const root = win.document.getElementById('host').attachShadow({ mode: 'closed' });
  root.innerHTML =
    '<a href="https://yandex.ru/games/_crpd/123">Реклама</a><button data-fullscreen-element="close">Закрыть</button>';
  await settle();
  hidden(win.document.getElementById('slot'));
  assert.notEqual(win.getComputedStyle(win.document.querySelector('.feed')).display, 'none');
  assert.notEqual(win.getComputedStyle(win.document.getElementById('game')).display, 'none');
});

test('removes paid similar-game cards and their slots while preserving organic suggestions', (t) => {
  const win = page(
    t,
    '<div class="play-similar-games"><div class="horizontal-container__list"><div id="paid" class="play-similar-games-tile"><a class="play-similar-games-tile__image" href="/games/app/123?utm_source=game_promo_similar_games">Промо</a></div><div id="organic" class="play-similar-games-tile"><a href="/games/app/456#referrer=similar">Другая игра</a></div></div></div>',
  );
  hidden(win.document.getElementById('paid'));
  assert.notEqual(win.getComputedStyle(win.document.getElementById('organic')).display, 'none');
  assert.notEqual(
    win.getComputedStyle(win.document.querySelector('.play-similar-games')).display,
    'none',
  );
});

test('restores similar-game tiles when a rerender reuses a paid tile for an organic game', async (t) => {
  const win = page(
    t,
    '<div id="tile" class="play-similar-games-tile" style="display:inline-flex"><a href="/games/app/123?utm_source=game_promo_similar_games">Промо</a></div>',
  );
  const tile = win.document.getElementById('tile');
  hidden(tile);
  tile.firstElementChild.href = '/games/app/456#referrer=similar';
  await settle();
  assert.equal(tile.style.display, 'inline-flex');
});

test('keeps suppressing explicit sponsored Yandex cards in embedded game documents', (t) => {
  const win = page(
    t,
    '<div class="feed__section"><div id="paid" class="game-card"><a href="https://yandex.ru/games/app/123?utm_source=game_promo_catalog">Промо</a></div></div>',
    () => {},
    'https://app-123.cdn.games.yandex.net/game/',
  );
  hidden(win.document.getElementById('paid'));
  assert.equal(win.document.querySelector('.feed__section').style.display, '');
});

for (const timing of ['sync', 'async']) {
  test(`keeps an empty ad slot collapsed after its shadow host is removed ${timing}`, async (t) => {
    const win = page(
      t,
      '<div id="slot" class="feed__section" style="height:300px"><div id="host"></div></div>',
    );
    const host = win.document.getElementById('host');
    const slot = win.document.getElementById('slot');
    const root = host.attachShadow({ mode: 'closed' });
    root.innerHTML =
      '<a href="https://yandex.ru/games/_crpd/123">Реклама</a><button data-fullscreen-element="close">Закрыть</button>';
    root.querySelector('button').addEventListener('click', () => {
      if (timing === 'sync') {
        host.remove();
      } else {
        win.setTimeout(() => host.remove(), 0);
      }
    });
    await settle();
    assert.equal(host.isConnected, false);
    hidden(slot);
    slot.innerHTML = '<button>Играть</button>';
    await settle();
    assert.notEqual(win.getComputedStyle(slot).display, 'none');
  });
}
