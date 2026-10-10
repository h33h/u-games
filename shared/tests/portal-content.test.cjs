'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');
const source = fs.readFileSync(path.join(__dirname, '../ad-adapter.js'), 'utf8');
const rules = JSON.parse(fs.readFileSync(path.join(__dirname, '../ad-rules.json'), 'utf8'));
const settle = () => new Promise((resolve) => setTimeout(resolve, 10));

function page(t, html, url = 'https://yandex.ru/games/') {
  const dom = new JSDOM(html, { runScripts: 'outside-only', url });
  t.after(() => dom.window.close());
  dom.window.__UGamesRules = rules;
  dom.window.eval(source);
  return dom.window;
}

const portal = `<header>
  <form role="search"><input id="search" placeholder="Найти игру"></form>
  <a id="catalog" href="/games/catalog">Каталог игр</a>
  <a id="shop" href="/games/shop?source=header">Магазин</a>
  <button id="notifications" data-testid="notifications-widget">Уведомления</button>
  <button id="balance" data-testid="balance-button">Баланс</button>
  <button id="login">Войти</button>
  <nav><a id="profile" href="/games/user">Игровой профиль</a>
    <button id="help" data-testid="new-catalog-header-user-menu-button-menu-item-help">Помощь</button>
  </nav>
</header>
<aside class="left-panel">
  <ul><li id="promos"><a href="/games/promos">Скидки и акции</a></li>
    <li id="category"><a href="/games/category/puzzles">Головоломки</a></li></ul>
  <div id="links" class="left-panel__block"><nav class="left-panel__links">Разработчикам, Помощь, Пользовательское соглашение</nav></div>
  <div id="copyright" class="left-panel__block"><div class="left-panel__copyright">© Яндекс, адрес компании</div></div>
</aside>
<main><div id="game" class="game-card"><a href="/games/app/123">О сайте: игра</a></div>
  <iframe id="frame" src="https://game.example/play"></iframe>
  <section id="instructions">Об игре. Как играть: нажмите пробел</section>
  <div id="description" class="page-description">Информация о сайте</div>
</main>`;

test('keeps games, search, categories and progress login while hiding portal services', (t) => {
  const win = page(t, portal);
  for (const id of [
    'shop',
    'notifications',
    'balance',
    'help',
    'promos',
    'links',
    'copyright',
    'description',
  ]) {
    const element = win.document.getElementById(id);
    assert.equal(win.getComputedStyle(element).display, 'none', id);
  }
  for (const id of [
    'search',
    'catalog',
    'login',
    'profile',
    'category',
    'game',
    'frame',
    'instructions',
  ]) {
    const element = win.document.getElementById(id);
    assert.notEqual(win.getComputedStyle(element).display, 'none', id);
    assert.equal(element.closest('[style*="display: none"]'), null, id);
  }
});

test('cleans late portal content and survives SPA rendering and style resets', async (t) => {
  const win = page(t, '<main></main>');
  const main = win.document.querySelector('main');
  main.innerHTML =
    '<div class="page-description">О сайте</div><a id="link" href="/games/catalog">Каталог</a>';
  await settle();
  const description = main.querySelector('.page-description');
  assert.equal(win.getComputedStyle(description).display, 'none');
  description.style.setProperty('display', 'block', 'important');
  const link = main.querySelector('#link');
  link.href = 'https://yandex.ru/games/shop/';
  await settle();
  assert.equal(win.getComputedStyle(description).display, 'none');
  assert.equal(win.getComputedStyle(link).display, 'none');
});

test('cleans portal menus in shadow roots', async (t) => {
  const win = page(t, '<div id="host"></div>');
  const root = win.document.querySelector('#host').attachShadow({ mode: 'closed' });
  root.innerHTML = '<div class="page-description">О сайте</div><button id="play">Играть</button>';
  await settle();
  assert.equal(root.querySelector('.page-description').style.display, 'none');
  assert.equal(root.querySelector('#play').style.display, '');
});

test('restores a navigation slot when SPA rendering reuses it for a game category', async (t) => {
  const win = page(t, '<a id="link" href="/games/shop" style="display: inline-flex">Магазин</a>');
  const link = win.document.querySelector('#link');
  assert.equal(win.getComputedStyle(link).display, 'none');
  link.href = '/games/category/puzzles';
  await settle();
  assert.equal(win.getComputedStyle(link).display, 'inline-flex');
  assert.equal(link.style.visibility, '');
  link.style.display = 'block';
  await settle();
  assert.equal(win.getComputedStyle(link).display, 'block');
});

for (const url of [
  'https://game.example/play',
  'https://passport.yandex.ru/auth',
  'https://yandex.ru/support/games/',
]) {
  test(`does not remove game or authentication content at ${url}`, (t) => {
    const win = page(t, portal, url);
    assert.notEqual(
      win.getComputedStyle(win.document.querySelector('.page-description')).display,
      'none',
    );
    assert.notEqual(win.getComputedStyle(win.document.querySelector('#help')).display, 'none');
  });
}
