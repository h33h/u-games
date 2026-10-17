'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');

const source = () => fs.readFileSync(path.join(__dirname, '../offline-games.js'), 'utf8');
const url = 'https://yandex.ru/games/app/gamers-mod-448583';
const image =
  'https://avatars.mds.yandex.net/get-games/2977039/2a0000019d8c5e89d6cb9aa4b47507149dc8/orig';
const thumbnail =
  'https://avatars.mds.yandex.net/get-games/2977039/2a0000019d8c5e89d6cb9aa4b47507149dc8/pjpg464x261';

function page(t, ...data) {
  const dom = new JSDOM('<title>UGames</title>', { url, runScripts: 'outside-only' });
  t.after(() => dom.window.close());
  const win = dom.window;
  const reports = [];
  win.__UGamesOffline = { postMessage: (message) => reports.push(JSON.parse(message)) };
  win.document.head.insertAdjacentHTML(
    'beforeend',
    '<meta property="og:title" content="Gamer\'s Mod - играть онлайн бесплатно на сервисе Яндекс Игры">' +
      '<meta property="og:image" content="https://static.games.yandex.net/opengraph/04b2aac23836fa74cd79be215c173b764f535fcb3388bbf8ba35347b467f7505.png?v=1792195200000">',
  );
  for (const value of data) {
    metadata(win, value);
  }
  win.eval(source());
  return { win, reports };
}

function metadata(win, data) {
  const script = win.document.createElement('script');
  script.type = 'application/ld+json';
  script.textContent = typeof data === 'string' ? data : JSON.stringify(data);
  win.document.head.appendChild(script);
}

test('direct game pages retain the matching structured game name and card artwork', (t) => {
  const { win, reports } = page(t, '{invalid JSON', {
    '@context': 'https://schema.org',
    '@graph': [
      { '@type': 'Organization', name: 'Яндекс Игры', image: 'https://yastatic.net/logo.png' },
      { '@type': 'VideoGame', url, name: "Gamer's Mod", image },
    ],
  });
  assert.deepEqual(reports, [
    {
      version: 1,
      type: 'catalog',
      gameId: '448583',
      url: 'https://yandex.ru/games/app/448583',
      title: "Gamer's Mod",
      cover: thumbnail,
    },
  ]);
  win.document.title = 'Gamer’s Mod — UGames';
  win.__UGamesOfflineCapture();
  assert.equal(reports.length, 1, 'branding changes must not replace structured game metadata');
});

test('unrelated and malformed structured metadata cannot become the current game cover', (t) => {
  const { win, reports } = page(t, '{invalid JSON');
  metadata(win, {
    '@graph': [
      {
        '@type': 'VideoGame',
        url: 'https://yandex.ru/games/app/42',
        name: 'Other game',
        image,
      },
      { '@type': 'WebPage', url, name: 'Portal', image },
    ],
  });
  win.__UGamesOfflineCapture();
  assert.equal(
    reports.at(-1).title,
    "Gamer's Mod - играть онлайн бесплатно на сервисе Яндекс Игры",
  );
  assert.equal(reports.at(-1).cover, undefined);
});

test('structured game artwork keeps the existing avatar CDN restrictions', (t) => {
  for (const unsafeImage of [
    'https://avatars.mds.yandex.net.evil.test/get-games/42/orig',
    'https://avatars.mds.yandex.net/get-yapic/private/avatar',
    'https://user:password@avatars.mds.yandex.net/get-games/42/orig',
  ]) {
    const { reports } = page(t, {
      '@graph': [{ '@type': 'VideoGame', url, name: "Gamer's Mod", image: unsafeImage }],
    });
    assert.equal(reports.at(-1).title, "Gamer's Mod");
    assert.equal(reports.at(-1).cover, undefined);
  }
});

test('structured artwork inserted after document start enriches the existing game capture', async (t) => {
  const { win, reports } = page(t);
  metadata(win, {
    '@graph': [{ '@type': 'VideoGame', url, name: "Gamer's Mod", image }],
  });
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(reports.at(-1).title, "Gamer's Mod");
  assert.equal(reports.at(-1).cover, thumbnail);
});
