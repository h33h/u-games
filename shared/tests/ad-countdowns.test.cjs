'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');

const file = path.join(__dirname, '../ad-countdowns.js');
const source = () => (fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '');
const gameURL = 'https://app-405184.games.s3.yandex.net/405184/build/index.html';
const settle = () => new Promise((resolve) => setTimeout(resolve, 5));

function page(t, html = '', prepare = () => {}, url = gameURL) {
  const dom = new JSDOM(html, { runScripts: 'outside-only', url });
  t.after(() => dom.window.close());
  prepare(dom.window);
  dom.window.eval(source());
  return dom.window;
}

function hidden(element) {
  assert.equal(element.style.getPropertyValue('display'), 'none');
  assert.equal(element.style.getPropertyPriority('display'), 'important');
}

test('hides explicit ad countdown markers without hiding gameplay or controls', (t) => {
  const win = page(
    t,
    `<main><canvas id="game"></canvas><div id="ad" data-ad-countdown>3 сек</div>
    <span id="timer">3 сек</span><button id="button" class="ad-countdown">Реклама через 3 сек</button>
    <div id="mixed" class="ad-countdown"><canvas></canvas><button>Играть</button></div></main>`,
  );
  hidden(win.document.getElementById('ad'));
  for (const selector of ['main', '#game', '#timer', '#button', '#mixed']) {
    assert.equal(win.document.querySelector(selector).style.display, '');
  }
});

test('hides unmarked ad text only when it clearly announces a short countdown', (t) => {
  const win = page(
    t,
    `<div id="ru">Реклама через <span>3</span> сек.</div>
    <p id="en">Ad starts in 5 seconds</p><span id="break">Ad Break In.. 2</span>
    <p id="game">Раунд начнётся через 3 сек</p><p id="other">Реклама отключена на 60 сек</p>
    <button id="control"><span id="control-text">Реклама через 3 сек</span></button>`,
  );
  for (const id of ['ru', 'en', 'break']) {
    hidden(win.document.getElementById(id));
  }
  for (const id of ['game', 'other', 'control', 'control-text']) {
    assert.equal(win.document.getElementById(id).style.display, '');
  }
  assert.equal(win.document.body.style.display, '');
});

test('suppresses dynamic countdown text and restores a reused game label', async (t) => {
  const win = page(t, '<p id="label" style="display:inline-flex">Раунд: 3 сек</p>');
  const label = win.document.getElementById('label');
  label.firstChild.data = 'Реклама через 3 сек';
  await settle();
  hidden(label);
  label.style.setProperty('display', 'block', 'important');
  await settle();
  hidden(label);
  label.textContent = 'Раунд: 2 сек';
  await settle();
  assert.equal(label.style.display, 'inline-flex');
  assert.equal(label.style.getPropertyPriority('display'), '');
});

test('observes existing open and newly attached closed shadow countdowns', async (t) => {
  let existing;
  const win = page(t, '<div id="host"></div><div id="new"></div>', (w) => {
    existing = w.document.getElementById('host').attachShadow({ mode: 'open' });
    existing.innerHTML = '<p id="ad">Реклама через 3 сек</p>';
  });
  hidden(existing.querySelector('#ad'));
  const root = win.document.getElementById('new').attachShadow({ mode: 'closed' });
  root.innerHTML = '<span class="ad-countdown">3 сек</span><button>Играть</button>';
  await settle();
  hidden(root.querySelector('span'));
  assert.equal(root.querySelector('button').style.display, '');
});

test('the DOM label adapter never rewrites a game counter', (t) => {
  const runtime = {
    projectName: 'SprunkiPG',
    globalVars: { Ads_timer: 17, Score: 9 },
    objects: { Text2: {}, InstantGamesBridge: {} },
    addEventListener() {},
    removeEventListener() {},
  };
  const win = page(
    t,
    '<p>Реклама через 2 сек</p>',
    (w) => {
      w.c3_runtimeInterface = { _GetLocalRuntime: () => ({ GetIRuntime: () => runtime }) };
    },
    'https://app-405184.games.s3.yandex.net/405184/build/index.html',
  );
  assert.equal(runtime.globalVars.Ads_timer, 17);
  assert.equal(runtime.globalVars.Score, 9);
  hidden(win.document.querySelector('p'));
});

test('restores label protection after returning to a cached document', async (t) => {
  const win = page(t, '<p style="display:inline-flex">Реклама через 2 сек</p>');
  const label = win.document.querySelector('p');
  win.dispatchEvent(new win.PageTransitionEvent('pagehide', { persisted: true }));
  label.textContent = 'Раунд: 2 сек';
  win.dispatchEvent(new win.PageTransitionEvent('pageshow', { persisted: true }));
  await settle();
  assert.equal(label.style.display, 'inline-flex');
  label.textContent = 'Реклама через 1 сек';
  await settle();
  hidden(label);
});

test('reinjection keeps the same observer wrappers and leaves browser clocks intact', (t) => {
  let clocks;
  const win = page(t, '', (w) => {
    clocks = [w.setTimeout, w.setInterval, w.Date, w.performance.now];
  });
  const attachShadow = win.Element.prototype.attachShadow;
  win.eval(source());
  assert.equal(win.Element.prototype.attachShadow, attachShadow);
  assert.deepEqual([win.setTimeout, win.setInterval, win.Date, win.performance.now], clocks);
});
