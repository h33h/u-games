'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');
const source = fs.readFileSync(path.join(__dirname, '../ad-adapter.js'), 'utf8');

function page(t, url = 'https://yandex.ru/games/', prepare = () => {}) {
  const dom = new JSDOM('<div id="host"></div>', { runScripts: 'outside-only', url });
  t.after(() => dom.window.close());
  const opened = [];
  dom.window.open = (...args) => {
    opened.push(args);
    return {};
  };
  dom.window.navigation = new dom.window.EventTarget();
  prepare(dom.window);
  dom.window.eval(source);
  return { win: dom.window, opened };
}

test('native offline catalogue can open only its cached games through main-frame Navigation API', (t) => {
  const cached = 'https://app-42.games.s3.yandex.net/42/build/index.html';
  for (const origin of ['https://yandex.ru/games/', 'ugames-offline://yandex.ru/games/']) {
    const { win } = page(t, origin, (w) => {
      w.__UGamesCachedCatalog = { version: 1, games: [{ url: cached, title: 'Game' }] };
    });
    for (const [url, allowed] of [
      [cached, true],
      [cached + '#level', true],
      ['https://app-43.games.yandex.net/index.html', false],
    ]) {
      const event = new win.Event('navigate', { cancelable: true });
      event.destination = { url };
      assert.equal(win.navigation.dispatchEvent(event), allowed, url);
    }
    assert.equal(win.open(cached), null);
  }
});

test('a page cannot enable cached-catalogue navigation privileges after protection starts', (t) => {
  const { win } = page(t);
  const url = 'https://app-42.games.s3.yandex.net/42/build/index.html';
  win.__UGamesCachedCatalog = { version: 1, games: [{ url }] };
  const event = new win.Event('navigate', { cancelable: true });
  event.destination = { url };
  assert.equal(win.navigation.dispatchEvent(event), false);
});

test('cancels scripted navigation events before an external document replaces the game', (t) => {
  const { win } = page(t);
  const event = new win.Event('navigate', { cancelable: true });
  event.destination = { url: 'https://external.example/' };
  assert.equal(win.navigation.dispatchEvent(event), false);
  const internal = new win.Event('navigate', { cancelable: true });
  internal.destination = { url: 'https://yandex.ru/games/app/123' };
  assert.equal(win.navigation.dispatchEvent(internal), true);
});

test('preserves the current Yandex ID login route for buttons, popups and form steps', (t) => {
  const { win, opened } = page(t);
  const url =
    'https://passport.yandex.ru/pwl-yandex/auth/add?retpath=https%3A%2F%2Fyandex.ru%2Fgames%2F';
  const event = new win.Event('navigate', { cancelable: true });
  event.destination = { url };
  assert.equal(win.navigation.dispatchEvent(event), true);
  win.open(url);
  assert.equal(opened.length, 1);
  const form = win.document.createElement('form');
  form.action = 'https://passport.yandex.ru/pwl-yandex/auth/verify';
  win.document.body.append(form);
  assert.equal(
    form.dispatchEvent(new win.Event('submit', { bubbles: true, cancelable: true })),
    true,
  );
  assert.equal(win.open('https://passport.yandex.ru/pwl-yandex-evil/auth'), null);
  assert.equal(win.open('https://passport.yandex.ru.evil.test/pwl-yandex/auth'), null);
});

test('completes Yandex ID SSO redirects and cookie synchronization forms', (t) => {
  const { win, opened } = page(t, 'https://passport.yandex.ru/pwl-yandex/auth/finished');
  for (const url of [
    'https://sso.passport.yandex.ru/prepare?uuid=fixture&goal=https%3A%2F%2Fya.ru%2F&finish=https%3A%2F%2Fyandex.ru%2Fgames%2F',
    'https://sso.passport.yandex.com/prepare?uuid=fixture',
    'https://sso.ya.ru/sync?uuid=fixture',
  ]) {
    const event = new win.Event('navigate', { cancelable: true });
    event.destination = { url };
    assert.equal(win.navigation.dispatchEvent(event), true, url);
    win.open(url);
  }
  assert.equal(opened.length, 3);
  const form = win.document.createElement('form');
  form.method = 'post';
  form.action = 'https://sso.ya.ru/sync?uuid=fixture';
  win.document.body.append(form);
  assert.equal(
    form.dispatchEvent(new win.Event('submit', { bubbles: true, cancelable: true })),
    true,
  );
  // Passport submits the cookie synchronization form with form.submit().
  let submitted = false;
  win._virtualConsole.on('jsdomError', (error) => {
    if (error.message.includes('HTMLFormElement.prototype.submit')) {
      submitted = true;
    }
  });
  form.submit();
  assert.equal(submitted, true);
});

test('rejects unrelated SSO paths and lookalike hosts', (t) => {
  const { win } = page(t, 'https://sso.passport.yandex.ru/prepare');
  for (const url of [
    'https://sso.passport.yandex.ru/profile',
    'https://sso.passport.yandex.ru/prepare-evil',
    'https://sso.passport.yandex.ru.evil.test/prepare',
    'https://sso.ya.ru/profile',
    'https://sso.ya.ru/sync-evil',
    'https://sso.ya.ru.evil.test/sync',
    'http://sso.ya.ru/sync',
    'https://sso.ya.ru:444/sync',
  ]) {
    const event = new win.Event('navigate', { cancelable: true });
    event.destination = { url };
    assert.equal(win.navigation.dispatchEvent(event), false, url);
    assert.equal(win.open(url), null, url);
    const form = win.document.createElement('form');
    form.action = url;
    win.document.body.append(form);
    assert.equal(
      form.dispatchEvent(new win.Event('submit', { bubbles: true, cancelable: true })),
      false,
      url,
    );
  }
});

test('blocks external popups, app schemes and lookalike domains before creating a window', (t) => {
  const { win, opened } = page(t);
  for (const url of [
    'https://example.com',
    'https://yandex.ru.evil.test/games/',
    'https://yandex.ru/support/games/',
    'https://passport.yandex.ru/profile',
    'intent://game',
    'mailto:hello@example.com',
    'data:text/html,hello',
  ]) {
    assert.equal(win.open(url), null, url);
  }
  assert.equal(opened.length, 0);
  win.open('/games/app/123');
  assert.equal(opened.length, 1);
  win.open('https://passport.yandex.ru/auth?retpath=https://yandex.ru/games/');
  assert.equal(opened.length, 2);
});

test('blocks links before game click handlers run, including shadow-root links', (t) => {
  const { win } = page(t, 'https://game.example/play');
  const root = win.document.querySelector('#host').attachShadow({ mode: 'closed' });
  const link = win.document.createElement('a');
  link.href = 'https://developer.example';
  root.append(link);
  let clicks = 0;
  link.addEventListener('click', () => clicks++);
  const event = new win.MouseEvent('click', { bubbles: true, cancelable: true, composed: true });
  assert.equal(link.dispatchEvent(event), false);
  assert.equal(event.defaultPrevented, true);
  assert.equal(clicks, 0);
});

test('preserves in-game links but blocks game URLs escaping to top or a new window', (t) => {
  const { win } = page(t, 'https://game.example/play');
  const link = win.document.createElement('a');
  link.href = '/levels/2';
  win.document.body.append(link);
  // Prevent jsdom navigation after observing our capture listener.
  let blocked;
  let clicks = 0;
  link.addEventListener('click', (e) => {
    clicks++;
    blocked = e.defaultPrevented;
    e.preventDefault();
  });
  link.dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }));
  assert.equal(blocked, false);
  assert.equal(clicks, 1);
  for (const target of ['_top', '_parent', '_blank', 'external-window']) {
    link.target = target;
    const event = new win.MouseEvent('click', { bubbles: true, cancelable: true });
    link.dispatchEvent(event);
    assert.equal(event.defaultPrevented, true);
    assert.equal(clicks, 1);
  }
});

test('blocks external form submissions while preserving the catalog search form', (t) => {
  const { win } = page(t);
  const form = win.document.createElement('form');
  form.action = 'https://external.example';
  win.document.body.append(form);
  assert.equal(
    form.dispatchEvent(new win.Event('submit', { bubbles: true, cancelable: true })),
    false,
  );
  form.action = '/games/search';
  assert.equal(
    form.dispatchEvent(new win.Event('submit', { bubbles: true, cancelable: true })),
    true,
  );
});

test('blocks submitter overrides and programmatic form.submit', (t) => {
  const { win } = page(t);
  const form = win.document.createElement('form');
  form.action = '/games/search';
  form.method = 'post';
  const button = win.document.createElement('button');
  button.setAttribute('formaction', 'https://external.example');
  form.append(button);
  win.document.body.append(form);
  assert.equal(
    form.dispatchEvent(
      new win.SubmitEvent('submit', { bubbles: true, cancelable: true, submitter: button }),
    ),
    false,
  );
  form.action = 'https://external.example';
  // jsdom emits an error if its real submit method is called.
  let submitted = false;
  win._virtualConsole.on('jsdomError', () => {
    submitted = true;
  });
  form.submit();
  assert.equal(submitted, false);
});
