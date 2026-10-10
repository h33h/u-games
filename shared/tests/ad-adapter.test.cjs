'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const file = path.join(__dirname, '../ad-adapter.js');
const source = () => fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '';
const settle = () => new Promise(resolve => setTimeout(resolve, 5));

function environment(initial = {}) {
  const ticks = [];
  const context = vm.createContext({
    ...initial, setTimeout, clearTimeout, queueMicrotask,
    setInterval(fn) { ticks.push(fn); return ticks.length; },
    clearInterval() {}, console: { warn() {}, error() {} },
  });
  context.window = context;
  return {
    context,
    inject() { vm.runInContext(source(), context); },
    tick() { ticks.forEach(fn => fn()); },
  };
}

function sdkFixture() {
  let originalCalls = 0;
  const player = { getData: () => ({ level: 7 }) };
  const sdk = {
    getPlayer() { assert.equal(this, sdk); return player; },
    adv: {
      showFullscreenAdv() { originalCalls++; },
      showRewardedVideo() { originalCalls++; },
      showBannerAdv() { originalCalls++; return Promise.resolve({ stickyAdvIsShowing: true }); },
      hideBannerAdv() { originalCalls++; return Promise.resolve({ stickyAdvIsShowing: false }); },
      getBannerAdvStatus() { return Promise.resolve({ stickyAdvIsShowing: true }); },
    },
  };
  return { sdk, player, calls: () => originalCalls };
}

test('late SDK closes fullscreen asynchronously without showing an ad', async () => {
  const f = sdkFixture(), env = environment(), events = [];
  env.inject();
  env.context.YaGames = { init: () => Promise.resolve(f.sdk) };
  const sdk = await env.context.YaGames.init();
  sdk.adv.showFullscreenAdv({ callbacks: { onOpen: () => events.push('open'), onClose: value => events.push(['close', value]) } });
  assert.deepEqual(events, []);
  await settle();
  assert.deepEqual(events, [['close', false]]);
  assert.equal(f.calls(), 0);
});

test('reward emits open, one reward and close without original video', async () => {
  const f = sdkFixture(), env = environment({ YaGames: { init: () => Promise.resolve(f.sdk) } }), events = [];
  env.inject();
  const sdk = await env.context.YaGames.init();
  sdk.adv.showRewardedVideo({ callbacks: {
    onOpen: () => events.push(['open']), onRewarded: () => events.push(['reward']), onClose: v => events.push(['close', v]),
  } });
  assert.deepEqual(events, []);
  await settle();
  assert.deepEqual(events, [['open'], ['reward'], ['close', true]]);
  assert.equal(f.calls(), 0);
});

test('throwing game callback does not prevent close or invoke original ad', async () => {
  const f = sdkFixture(), env = environment({ YaGames: { init: () => Promise.resolve(f.sdk) } });
  env.inject();
  let closes = 0;
  const sdk = await env.context.YaGames.init();
  sdk.adv.showRewardedVideo({ callbacks: { onRewarded() { throw new Error('game callback'); }, onClose() { closes++; } } });
  await settle();
  assert.equal(closes, 1);
  assert.equal(f.calls(), 0);
});

test('reinjection never duplicates rewards; new user requests still earn their own', async () => {
  const f = sdkFixture(), env = environment({ YaGames: { init: () => Promise.resolve(f.sdk) } });
  env.inject(); env.inject();
  const sdk = await env.context.YaGames.init();
  env.inject(); env.tick();
  let rewards = 0, closes = 0;
  const options = { callbacks: { onRewarded() { rewards++; }, onClose() { closes++; } } };
  sdk.adv.showRewardedVideo(options);
  sdk.adv.showRewardedVideo(options);
  await settle();
  assert.equal(rewards, 2); assert.equal(closes, 2); assert.equal(f.calls(), 0);
});

test('init preserves arguments, receiver, player methods and fresh SDK instances', async () => {
  const a = sdkFixture(), b = sdkFixture(), seen = [], initOptions = { signed: true };
  const provider = { init(options) { assert.equal(this, provider); seen.push(options); return Promise.resolve(seen.length === 1 ? a.sdk : b.sdk); } };
  const env = environment({ YaGames: provider });
  env.inject();
  for (const f of [a, b]) {
    const sdk = await env.context.YaGames.init(initOptions);
    assert.equal(sdk, f.sdk); assert.equal(sdk.getPlayer(), f.player);
    sdk.adv.showFullscreenAdv({ callbacks: {} });
  }
  await settle();
  assert.deepEqual(seen, [initOptions, initOptions]);
  assert.equal(a.calls() + b.calls(), 0);
});

test('init rejection is preserved', async () => {
  const error = new Error('provider unavailable');
  const env = environment({ YaGames: { init: () => Promise.reject(error) } });
  env.inject();
  await assert.rejects(env.context.YaGames.init(), e => e === error);
});

test('late init method and nonconfigurable provider are patched on polling tick', async () => {
  const f = sdkFixture(), env = environment();
  Object.defineProperty(env.context, 'YaGames', { value: {}, configurable: false, writable: true });
  env.inject();
  env.context.YaGames.init = () => Promise.resolve(f.sdk);
  env.tick();
  const sdk = await env.context.YaGames.init();
  sdk.adv.showFullscreenAdv({});
  await settle();
  assert.equal(f.calls(), 0);
});

test('banner methods return hidden state and never call provider', async () => {
  const f = sdkFixture(), env = environment({ YaGames: { init: () => Promise.resolve(f.sdk) } });
  env.inject();
  const sdk = await env.context.YaGames.init();
  for (const method of ['showBannerAdv', 'hideBannerAdv', 'getBannerAdvStatus']) {
    const status = await sdk.adv[method]();
    assert.equal(status.stickyAdvIsShowing, false);
  }
  assert.equal(f.calls(), 0);
});

test('blank popup is protected before its opener writes a game SDK into it', async () => {
  const child = environment(), f = sdkFixture();
  const parent = environment({ open(url) { assert.equal(url, 'about:blank'); return child.context; } });
  parent.inject();
  const popup = parent.context.open('about:blank');
  popup.YaGames = { init: () => Promise.resolve(f.sdk) };
  const sdk = await popup.YaGames.init();
  let rewards = 0;
  sdk.adv.showRewardedVideo({ callbacks: { onRewarded() { rewards++; } } });
  await settle();
  assert.equal(rewards, 1);
  assert.equal(f.calls(), 0);
});

test('immutable ad API rejects init and notifies native shell instead of returning unsafe SDK', async () => {
  const f = sdkFixture();
  Object.freeze(f.sdk.adv);
  let notifications = 0;
  const env = environment({
    YaGames: { init: () => Promise.resolve(f.sdk) },
    __UGamesProtection: { unsupported() { notifications++; } },
  });
  env.inject();
  await assert.rejects(env.context.YaGames.init(), /advertisement interface/);
  assert.equal(notifications, 1);
  assert.equal(env.context.__UGamesAdapter.status, 'unsupported');
  assert.equal(f.calls(), 0);
});

test('immutable init stops the page and notifies native protection', () => {
  const f = sdkFixture();
  let notified = 0, stopped = 0;
  const provider = {};
  Object.defineProperty(provider, 'init', { value: () => f.sdk });
  const env = environment({ YaGames: provider, stop() { stopped++; }, __UGamesProtection: { unsupported() { notified++; } } });
  assert.throws(() => env.inject(), /advertisement interface/);
  assert.equal(notified, 1);
  assert.equal(stopped, 1);
  assert.equal(env.context.__UGamesAdapter.status, 'unsupported');
});

test('same SDK is protected again after its adv object or methods change', async () => {
  const first = sdkFixture(), second = sdkFixture();
  const env = environment({ YaGames: { init: () => first.sdk } });
  env.inject();
  env.context.YaGames.init();
  first.sdk.adv = second.sdk.adv;
  env.context.YaGames.init().adv.showRewardedVideo({});
  // An original callable can be replaced even without replacing adv itself.
  let original = 0;
  first.sdk.adv.showFullscreenAdv = () => original++;
  env.context.YaGames.init().adv.showFullscreenAdv({});
  await settle();
  assert.equal(second.calls(), 0);
  assert.equal(original, 0);
});

for (const publish of ['defineProperty', 'defineProperties', 'reflect']) {
  test(`SDK published by ${publish} is protected before the first polling tick`, async () => {
    const f = sdkFixture(), env = environment({ fixture: f.sdk });
    env.inject();
    const expression = publish === 'defineProperty'
      ? "Object.defineProperty(window, 'YaGames', {value: provider, configurable: true});"
      : publish === 'defineProperties'
      ? "Object.defineProperties(window, {YaGames: {value: provider, configurable: true}});"
      : "Reflect.defineProperty(window, 'YaGames', {value: provider, configurable: true});";
    vm.runInContext(`var provider = {init: function(){return fixture;}}; ${expression} YaGames.init().adv.showFullscreenAdv({});`, env.context);
    await settle();
    assert.equal(f.calls(), 0);
  });
}
