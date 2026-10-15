'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');
const source = fs.readFileSync(path.join(__dirname, '../ad-adapter.js'), 'utf8');

function page(t, url = 'https://yandex.ru/games/') {
  const dom = new JSDOM('<div id="host"></div>', { runScripts: 'outside-only', url });
  t.after(() => dom.window.close());
  const opened = [];
  dom.window.open = (...args) => {
    opened.push(args);
    return {};
  };
  dom.window.navigation = new dom.window.EventTarget();
  dom.window.eval(source);
  return { win: dom.window, opened };
}

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
