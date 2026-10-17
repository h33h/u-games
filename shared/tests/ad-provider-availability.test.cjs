'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const file = path.join(__dirname, '../ad-provider-availability.js');
const source = () => (fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '');

function environment(initial = {}) {
  const intervals = new Map();
  let nextTimer = 0;
  const context = vm.createContext({
    ...initial,
    setInterval(callback) {
      intervals.set(++nextTimer, callback);
      return nextTimer;
    },
    clearInterval(timer) {
      intervals.delete(timer);
    },
  });
  context.window = context;
  return {
    context,
    inject() {
      vm.runInContext(source(), context);
    },
    tick() {
      for (const callback of intervals.values()) {
        callback();
      }
    },
  };
}

// Mirrors PlaygamaBridge's empty #modules registry, prototype constants and
// SDK_NOT_INITIALIZED diagnostic. initialize loads options, then registers
// modules, and only afterward resolves with isInitialized set to true.
function playgamaFixture({ initialized = false, version = '2.3.0' } = {}) {
  let isInitialized = initialized;
  let advertisementReadsBeforeInit = 0;
  let resolvedOptions;
  let lastPromise;
  let initCalls = 0;
  let lastArgs;
  const modules = {};
  const events = [];
  const fetchedOptions = {
    advertisement: {
      interstitial: {
        disable: false,
        autoShow: ['game_ready', 'storage_set'],
        preloadOnStart: 'level_complete',
        placementFallback: 'default',
      },
      banner: { disable: false },
      rewarded: { disable: false, preloadOnStart: 'reward' },
      minimumDelayBetweenInterstitial: 60,
    },
    payments: [{ id: 'coins', price: 10 }],
    player: { id: 'player-7', level: 4 },
  };
  const showResult = { request: 'original-provider-result' };
  const advertisement = {
    get isInterstitialSupported() {
      return resolvedOptions?.advertisement.interstitial.disable !== true;
    },
    showInterstitial(placement) {
      events.push(['show', placement]);
      return showResult;
    },
    showRewarded() {
      events.push(['rewarded']);
    },
    showBanner() {
      events.push(['banner']);
    },
  };
  class PlaygamaBridge {
    get version() {
      return version === null ? undefined : version;
    }
    get isInitialized() {
      return isInitialized;
    }
    get advertisement() {
      if (!isInitialized) {
        advertisementReadsBeforeInit++;
      }
      return modules[this.MODULE_NAME.ADVERTISEMENT];
    }
    get options() {
      return resolvedOptions;
    }
    initialize(...args) {
      assert.equal(this, bridge);
      initCalls++;
      lastArgs = args;
      lastPromise = Promise.resolve().then(() => {
        // Like a successful configuration fetch, this replaces any fallback
        // supplied to initialize, rather than merging the fallback into it.
        resolvedOptions = structuredClone(fetchedOptions);
        modules[this.MODULE_NAME.ADVERTISEMENT] = advertisement;
        isInitialized = true;
        return args[1];
      });
      return lastPromise;
    }
  }
  // Values from src/constants/moduleName.ts and src/constants/eventName.ts.
  // The real SDK publishes these on PlaygamaBridge.prototype before init.
  Object.assign(PlaygamaBridge.prototype, {
    MODULE_NAME: { CORE: 'core', ADVERTISEMENT: 'advertisement' },
    EVENT_NAME: {
      INTERSTITIAL_STATE_CHANGED: 'interstitial_state_changed',
      REWARDED_STATE_CHANGED: 'rewarded_state_changed',
      PLATFORM_MESSAGE_SENT: 'platform_message_sent',
    },
  });
  const bridge = new PlaygamaBridge();
  if (initialized) {
    resolvedOptions = structuredClone(fetchedOptions);
    modules[bridge.MODULE_NAME.ADVERTISEMENT] = advertisement;
  }
  return {
    bridge,
    advertisement,
    events,
    showResult,
    fetchedOptions,
    get lastPromise() {
      return lastPromise;
    },
    get initCalls() {
      return initCalls;
    },
    get lastArgs() {
      return lastArgs;
    },
    get advertisementReadsBeforeInit() {
      return advertisementReadsBeforeInit;
    },
  };
}

test('disables resolved Playgama interstitials before game init callbacks run', async () => {
  const fixture = playgamaFixture();
  const env = environment({ bridge: fixture.bridge });
  const advertisement = fixture.advertisement;
  const originalShow = advertisement.showInterstitial;
  const originalRewarded = advertisement.showRewarded;
  const originalBanner = advertisement.showBanner;
  env.inject();
  assert.equal(fixture.advertisementReadsBeforeInit, 0, 'do not probe an uninitialized SDK module');
  const token = { initialized: 'provider-return-value' };
  const fallback = { advertisement: { interstitial: { disable: false } } };
  const result = fixture.bridge.initialize(fallback, token);
  assert.equal(result, fixture.lastPromise, 'the original Promise identity is preserved');
  const value = await result.then((resolvedValue) => {
    assert.equal(advertisement.isInterstitialSupported, false);
    assert.equal(fixture.bridge.options.advertisement.interstitial.disable, true);
    assert.equal(fixture.bridge.options.advertisement.interstitial.autoShow.length, 0);
    return resolvedValue;
  });
  assert.equal(value, token);
  assert.equal(fixture.initCalls, 1);
  assert.deepEqual(fixture.lastArgs, [fallback, token]);
  assert.deepEqual(fallback, { advertisement: { interstitial: { disable: false } } });
  assert.equal(advertisement.showInterstitial, originalShow);
  assert.equal(advertisement.showRewarded, originalRewarded);
  assert.equal(advertisement.showBanner, originalBanner);
  assert.deepEqual(fixture.events, [], 'changing availability must not emit SDK events');
  assert.equal(advertisement.showInterstitial('level_complete'), fixture.showResult);
  assert.deepEqual(fixture.events, [['show', 'level_complete']]);
  const expected = structuredClone(fixture.fetchedOptions);
  expected.advertisement.interstitial.disable = true;
  expected.advertisement.interstitial.autoShow = [];
  assert.deepEqual(JSON.parse(JSON.stringify(fixture.bridge.options)), expected);
});

test('observes a late Playgama bridge before its immediate initialization', async () => {
  const env = environment();
  const fixture = playgamaFixture();
  env.inject();
  env.context.bridge = fixture.bridge;
  await env.context.bridge.initialize().then(() => {
    assert.equal(fixture.bridge.advertisement.isInterstitialSupported, false);
  });
});

test('recognizes the real v2 prototype before its advertisement module exists', async () => {
  const fixture = playgamaFixture();
  const env = environment();
  assert.equal(fixture.bridge.advertisement, undefined);
  const previousReads = fixture.advertisementReadsBeforeInit;
  env.inject();
  env.context.bridge = fixture.bridge;
  assert.equal(fixture.advertisementReadsBeforeInit, previousReads);
  await env.context.bridge.initialize().then(() => {
    assert.equal(fixture.bridge.advertisement, fixture.advertisement);
    assert.equal(fixture.bridge.advertisement.isInterstitialSupported, false);
    assert.equal(fixture.bridge.options.advertisement.interstitial.autoShow.length, 0);
  });
  assert.equal(fixture.advertisementReadsBeforeInit, previousReads);
});

test('protects an already initialized bridge without issuing provider requests', () => {
  const fixture = playgamaFixture({ initialized: true });
  const env = environment({ bridge: fixture.bridge });
  env.inject();
  assert.equal(fixture.bridge.advertisement.isInterstitialSupported, false);
  assert.equal(fixture.bridge.options.advertisement.interstitial.autoShow.length, 0);
  assert.equal(fixture.initCalls, 0);
  assert.deepEqual(fixture.events, []);
});

test('reinjection and repeated initialization preserve one wrapper and the original results', async () => {
  const fixture = playgamaFixture();
  const env = environment({ bridge: fixture.bridge });
  env.inject();
  const initialize = fixture.bridge.initialize;
  env.inject();
  assert.equal(fixture.bridge.initialize, initialize);
  const first = { call: 1 };
  const second = { call: 2 };
  assert.equal(await fixture.bridge.initialize({}, first), first);
  const previousAutoShow = fixture.bridge.options.advertisement.interstitial.autoShow;
  env.inject();
  assert.equal(fixture.bridge.options.advertisement.interstitial.autoShow, previousAutoShow);
  assert.equal(await fixture.bridge.initialize({}, second), second);
  assert.equal(fixture.bridge.advertisement.isInterstitialSupported, false);
  assert.equal(fixture.initCalls, 2);
});

test('replacement initialize methods retain configuration protection', async () => {
  const fixture = playgamaFixture();
  const initialize = fixture.bridge.initialize;
  const env = environment({ bridge: fixture.bridge });
  env.inject();
  fixture.bridge.initialize = initialize;
  await fixture.bridge.initialize();
  assert.equal(fixture.bridge.advertisement.isInterstitialSupported, false);
  assert.equal(fixture.initCalls, 1);
});

test('initialization rejection retains the exact Promise and original error', async () => {
  const fixture = playgamaFixture();
  const error = new Error('provider configuration unavailable');
  const originalPromise = Promise.reject(error);
  fixture.bridge.initialize = function (...args) {
    assert.equal(this, fixture.bridge);
    assert.deepEqual(args, ['a', 'b']);
    return originalPromise;
  };
  const env = environment({ bridge: fixture.bridge });
  env.inject();
  const result = fixture.bridge.initialize('a', 'b');
  assert.equal(result, originalPromise);
  await assert.rejects(result, (value) => value === error);
  assert.equal(fixture.bridge.options, undefined);
  assert.deepEqual(fixture.events, []);
});

test('synchronous provider returns and throws preserve their contracts', () => {
  const fixture = playgamaFixture({ initialized: true });
  const token = { initialized: true };
  fixture.bridge.initialize = function () {
    assert.equal(this, fixture.bridge);
    return token;
  };
  const env = environment({ bridge: fixture.bridge });
  env.inject();
  assert.equal(fixture.bridge.initialize(), token);
  const error = new Error('synchronous initialization failed');
  fixture.bridge.initialize = () => {
    throw error;
  };
  assert.throws(
    () => fixture.bridge.initialize(),
    (value) => value === error,
  );
});

test('uses an unversioned bridge only when it exposes the resolved interstitial configuration', () => {
  const fixture = playgamaFixture({ initialized: true, version: null });
  const env = environment({ bridge: fixture.bridge });
  env.inject();
  assert.equal(fixture.bridge.advertisement.isInterstitialSupported, false);
});

test('other bridge shapes and explicit unsupported SDK versions remain unchanged', () => {
  const candidates = [
    { initialize() {}, options: { advertisement: { interstitial: { disable: false } } } },
    { advertisement: { showInterstitial() {} }, initialize() {} },
    { version: '2.3.0', advertisement: {}, initialize() {} },
    { version: '2.3.0', advertisement: { showInterstitial() {} } },
    { version: '2.3.0', isInitialized: false, initialize() {} },
    {
      version: '2.3.0',
      isInitialized: true,
      advertisement: { showInterstitial() {} },
      initialize() {},
      options: { advertisement: { interstitial: { disable: false } } },
    },
    playgamaFixture({ initialized: true, version: '1.30.0' }).bridge,
    playgamaFixture({ initialized: true, version: '3.0.0' }).bridge,
  ];
  for (const bridge of candidates) {
    const descriptors = Object.getOwnPropertyDescriptors(bridge);
    const options = bridge.options && structuredClone(bridge.options);
    const env = environment({ bridge });
    env.inject();
    assert.deepEqual(Object.getOwnPropertyDescriptors(bridge), descriptors);
    assert.deepEqual(bridge.options, options);
  }
});

test('read-only provider methods and configuration fail open without breaking initialization', async () => {
  const frozenBridge = playgamaFixture();
  const initialize = frozenBridge.bridge.initialize;
  Object.freeze(frozenBridge.bridge);
  const env = environment({ bridge: frozenBridge.bridge });
  env.inject();
  assert.equal(frozenBridge.bridge.initialize, initialize);
  const token = { initialized: 'original-result' };
  assert.equal(await frozenBridge.bridge.initialize({}, token), token);
  assert.equal(frozenBridge.bridge.advertisement.isInterstitialSupported, true);

  const frozenConfig = playgamaFixture({ initialized: true });
  const interstitial = frozenConfig.bridge.options.advertisement.interstitial;
  Object.freeze(interstitial);
  const frozenEnv = environment({ bridge: frozenConfig.bridge });
  frozenEnv.inject();
  assert.equal(interstitial.disable, false);
  assert.deepEqual(interstitial.autoShow, ['game_ready', 'storage_set']);
  assert.equal(frozenConfig.bridge.advertisement.isInterstitialSupported, true);
  assert.deepEqual(frozenConfig.events, []);
});

test('read-only bridge accessors are not replaced', () => {
  const fixture = playgamaFixture({ initialized: true });
  const env = environment();
  const get = () => fixture.bridge;
  Object.defineProperty(env.context, 'bridge', { configurable: true, get });
  const descriptor = Object.getOwnPropertyDescriptor(env.context, 'bridge');
  env.inject();
  assert.deepEqual(Object.getOwnPropertyDescriptor(env.context, 'bridge'), descriptor);
  assert.equal(fixture.bridge.advertisement.isInterstitialSupported, false);
});

test('coexists with the native ad adapter without adding global API overrides', async () => {
  const fixture = playgamaFixture();
  const env = environment();
  const adapter = fs.readFileSync(path.join(__dirname, '../ad-adapter.js'), 'utf8');
  vm.runInContext(adapter, env.context);
  const before = vm.runInContext(
    '({ defineProperty: Object.defineProperty, defineProperties: Object.defineProperties, reflectDefine: Reflect.defineProperty, dateNow: Date.now })',
    env.context,
  );
  env.inject();
  const after = vm.runInContext(
    '({ defineProperty: Object.defineProperty, defineProperties: Object.defineProperties, reflectDefine: Reflect.defineProperty, dateNow: Date.now })',
    env.context,
  );
  for (const key of Object.keys(before)) {
    assert.equal(after[key], before[key]);
  }
  env.context.bridge = fixture.bridge;
  await env.context.bridge.initialize();
  assert.equal(fixture.bridge.advertisement.isInterstitialSupported, false);
  assert.deepEqual(fixture.events, []);
});
