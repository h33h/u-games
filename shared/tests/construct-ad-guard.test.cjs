'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');

const file = path.join(__dirname, '../construct-ad-guard.js');
const source = () => (fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '');
const method = () => function () {};
const constant = (value) => ({ IsConstant: () => true, Get: () => value });

// Initialized Construct event objects, reduced from the published ADS sheets of
// SprunkiPG/PG/FNAFPG/CalmarPG/NNNIghts and New project. Method identity, function
// links, variable links and expression nodes mirror c3runtime.js, not game names.
function fixture(win) {
  const acts = (names) => Object.fromEntries(names.map((name) => [name, method()]));
  const sys = {
    Cnds: acts(['CompareVar', 'Compare', 'CompareBoolVar', 'TriggerOnce', 'Every', 'LayerVisible']),
    Acts: acts([
      'SetTimescale',
      'SetLayerVisible',
      'SetObjectTimescale',
      'AddVar',
      'SubVar',
      'SetVar',
    ]),
  };
  const timer = { Cnds: acts(['OnTimer', 'IsTimerRunning']), Acts: acts(['StartTimer']) };
  const sprite = { Acts: acts(['SetPos', 'SetSize', 'SetWidth', 'SetVisible']) };
  const text = { Acts: acts(['SetText', 'SetVisible']) };
  const bridge = {
    Acts: acts(['ShowInterstitial', 'ShowRewarded', 'SendMessage']),
    Cnds: acts(['OnInterstitialClosed', 'OnInterstitialFailed']),
  };
  win.C3 = {
    Plugins: {
      System: sys,
      Sprite: sprite,
      Text: text,
      Audio: { Acts: acts(['SetMasterVolume']) },
      PlaygamaBridge: bridge,
    },
    Behaviors: {
      Timer: timer,
      Tween: { Acts: acts(['TweenOneProperty', 'TweenTwoProperties']) },
      Pin: { Acts: acts(['PinByProperties']) },
    },
  };
  let sid = 0;
  const variable = {
    value: 60,
    GetSID: () => 913,
    IsGlobal: () => true,
    IsNumber: () => true,
    GetInitialValue: () => 60,
  };
  const varParam = { ...constant(variable), _eventVar: variable, _eventVarSid: 913 };
  const timerOwner = {
    IsFamily: () => false,
    GetPlugin: () => ({ GetConstructor: () => text }),
    GetBehaviorTypesIncludingInherited: () => [],
  };
  const overlay = {
    IsFamily: () => false,
    GetPlugin: () => ({ GetConstructor: () => sprite }),
    GetBehaviorTypesIncludingInherited: () => [],
  };
  const behavior = {};
  const all = [];
  const eventSheet = {};
  function ace(fn, values = [], owner = null, behaviorType = null) {
    return {
      _func: fn,
      _parameters: values.map(constant),
      _objectClass: owner,
      _behaviorType: behaviorType,
      Run: () => true,
      DebugRun: function* () {
        yield* [];
        return true;
      },
      IsInverted: () => false,
    };
  }
  function block(conditions = [], actions = [], parent = null) {
    const b = {
      conditions,
      actions,
      children: [],
      parent,
      sid: ++sid,
      GetSID() {
        return this.sid;
      },
      GetEventSheet: () => eventSheet,
      GetConditions() {
        return this.conditions;
      },
      GetActions() {
        return this.actions;
      },
      GetSubEvents() {
        return this.children;
      },
      GetParent() {
        return this.parent;
      },
      IsOrBlock: () => false,
      IsElseBlock: () => false,
      HasElseBlock: () => false,
    };
    if (parent) {
      parent.children.push(b);
    }
    all.push(b);
    return b;
  }
  const update = ace(sys.Acts.SubVar, [variable, 1]);
  update._parameters[0] = varParam;
  block([ace(sys.Cnds.Every, [1])], [update]);
  const compare = ace(sys.Cnds.CompareVar, [variable, 3, 0]);
  compare._parameters[0] = varParam;
  const gate = block([compare]);
  const once = ace(sys.Cnds.TriggerOnce);
  const pause = block(
    [],
    [
      ace(sys.Acts.SetTimescale, [0]),
      ace(timer.Acts.StartTimer, [2, 0, 'renamed'], timerOwner, behavior),
      ace(sprite.Acts.SetPos, [100, 0], overlay),
    ],
  );
  const call = ace(null);
  call._callEventBlock = pause;
  const trigger = block([once], [call], gate);
  const sink = block(
    [ace(timer.Cnds.OnTimer, ['renamed'], timerOwner, behavior)],
    [ace(bridge.Acts.ShowInterstitial, [false])],
  );
  const label = block([ace(timer.Cnds.IsTimerRunning, ['renamed'], timerOwner, behavior)]);
  const labelAction = ace(text.Acts.SetText, [], timerOwner);
  labelAction._parameters.push({
    IsConstant: () => false,
    _expressionFunc: method(),
    _numberedNodes: [{ _objectClass: timerOwner }],
  });
  block([], [labelAction], label);
  const manager = { _blocksBySid: new Map(all.map((b) => [b.sid, b])) };
  const runtime = {
    GetEventSheetManager: () => manager,
    GetIRuntime: () => ({
      projectName: 'Different project',
      globalVars: { DifferentVariable: 60 },
    }),
    _LoadDataJson: async function (value) {
      this.loaded = true;
      return value;
    },
  };
  function second() {
    if (variable.value > 0) {
      variable.value--;
    }
    if (variable.value <= 0 && once.Run()) {
      runtime.paused = true;
    }
  }
  return {
    runtime,
    manager,
    all,
    variable,
    once,
    pause,
    trigger,
    sink,
    label,
    labelAction,
    overlay,
    timerOwner,
    behavior,
    sys,
    timer,
    bridge,
    sprite,
    ace,
    block,
    second,
  };
}

function page(t, prepare = () => {}) {
  const dom = new JSDOM('', {
    runScripts: 'outside-only',
    url: 'https://app-999991.games.s3.yandex.net/new/index.html',
  });
  t.after(() => dom.window.close());
  const f = fixture(dom.window);
  prepare(dom.window, f);
  dom.window.eval(source());
  return { win: dom.window, f };
}

async function load(win, f) {
  win.C3_CreateRuntime = function () {
    assert.equal(this, win);
    return f.runtime;
  };
  const raw = win.C3_CreateRuntime();
  assert.equal(raw, f.runtime);
  assert.equal(await raw._LoadDataJson('original result'), 'original result');
}

function withPauseLayer(f) {
  const parent = f.block([f.ace(f.sys.Cnds.LayerVisible, ['Overlay'])]);
  f.sink.parent = parent;
  parent.children.push(f.sink);
  f.pause.actions.push(f.ace(f.sys.Acts.SetLayerVisible, ['Overlay', 1]));
  f.manager._blocksBySid = new Map(f.all.map((b) => [b.sid, b]));
  return parent;
}

// TocaBoca's ad function resets touch state and disables dragging before its
// one-shot ad timer. Those actions must still run when the delay is shortened.
function withInputCleanup(win, f) {
  const controls = { touch: 9, dragging: true };
  const owner = { GetPlugin: () => ({ GetConstructor: () => f.sprite }) };
  f.sprite.Acts.SetInstanceVar = function (_index, value) {
    this.touch = value;
  };
  win.C3.Behaviors.DragnDrop = {
    Acts: {
      SetEnabled(value) {
        this.dragging = !!value;
      },
    },
  };
  const reset = f.ace(f.sprite.Acts.SetInstanceVar, [0, 0], owner);
  Object.assign(reset._parameters[0], { _type: 10, _instVarIndex: 0 });
  const disable = f.ace(win.C3.Behaviors.DragnDrop.Acts.SetEnabled, [0], owner, {});
  f.pause.actions.unshift(reset, disable);
  const timerAction = f.pause.actions.find((a) => a._func === f.timer.Acts.StartTimer);
  f.timer.Acts.StartTimer = function (duration, type, name) {
    if (this.failure) {
      throw this.failure;
    }
    this.scheduled = { duration, type, name };
    return 'scheduled';
  };
  timerAction._func = f.timer.Acts.StartTimer;
  const ownClock = f.ace(f.sys.Acts.SetObjectTimescale, [f.timerOwner, 1]);
  ownClock._parameters[0]._objectClass = f.timerOwner;
  f.pause.actions.push(ownClock);
  return { controls, reset, disable, timerAction };
}

test('mixed input cleanup runs while only its proven advertising timer loses the wait', async (t) => {
  const { win, f } = page(t);
  const { controls, reset, disable, timerAction } = withInputCleanup(win, f);
  const original = { once: f.once.Run, reset: reset._func, disable: disable._func };
  await load(win, f);
  const receiver = {};
  assert.equal(timerAction._func.call(receiver, 2, 0, 'renamed'), 'scheduled');
  assert.ok(receiver.scheduled.duration > 0 && receiver.scheduled.duration < 1 / 60);
  assert.equal(receiver.scheduled.type, 0);
  assert.equal(receiver.scheduled.name, 'renamed');
  assert.equal(f.once.Run, original.once);
  assert.equal(f.once.Run(), true);
  reset._func.call(controls, 0, 0);
  disable._func.call(controls, 0);
  assert.deepEqual(controls, { touch: 0, dragging: false });
  assert.equal(reset._func, original.reset);
  assert.equal(disable._func, original.disable);
  assert.equal(f.variable.value, 60);
  assert.equal(win.__UGamesConstructAds.shortenedTimers, 1);
  assert.equal(win.__UGamesConstructAds.blockedGates, 0);
  assert.equal(win.__UGamesConstructAds.status, 'active');
});

test('a shortened timer survives same-frame cleanup until its next event-sheet pass', async (t) => {
  const { win, f } = page(t);
  const { timerAction } = withInputCleanup(win, f);
  await load(win, f);
  const receiver = {};
  timerAction._func.call(receiver, 2, 0, 'renamed');
  let pending = receiver.scheduled;
  // Construct polls OnTimer during events and deletes finished one-shots in
  // Tick2 afterwards. A sink before the start action cannot see a new timer.
  let currentTime = 0;
  if (currentTime >= pending.duration) {
    pending = undefined;
  }
  assert.ok(pending, 'the ad must remain scheduled after its startup frame');
  currentTime += 1 / 60;
  assert.equal(currentTime >= pending.duration, true, 'the next frame can resume the game');
});

test('a family input-variable index is read from metadata before any instances exist', async (t) => {
  const { win, f } = page(t);
  const { reset, timerAction } = withInputCleanup(win, f);
  reset._objectClass.IsFamily = () => true;
  reset._parameters[0].IsConstant = () => false;
  reset._parameters[0].Get = () => {
    throw new Error('a family index needs a selected gameplay instance');
  };
  await load(win, f);
  const receiver = {};
  timerAction._func.call(receiver, 2, 0, 'renamed');
  assert.ok(receiver.scheduled.duration > 0 && receiver.scheduled.duration < 1 / 60);
});

test('legacy Construct plugin and behavior instances identify the same ad-only timer owner', async (t) => {
  const { win, f } = page(t);
  const { reset, disable, timerAction } = withInputCleanup(win, f);
  class SpritePlugin {}
  SpritePlugin.Acts = f.sprite.Acts;
  class TextPlugin {}
  TextPlugin.Acts = win.C3.Plugins.Text.Acts;
  class TimerBehavior {}
  TimerBehavior.Acts = f.timer.Acts;
  TimerBehavior.Cnds = f.timer.Cnds;
  win.C3.Plugins.Sprite = SpritePlugin;
  win.C3.Plugins.Text = TextPlugin;
  win.C3.Behaviors.Timer = TimerBehavior;
  for (const owner of [reset._objectClass, disable._objectClass, f.overlay]) {
    owner.GetPlugin = () => new SpritePlugin();
  }
  f.timerOwner.GetPlugin = () => new TextPlugin();
  f.timerOwner.GetBehaviorTypesIncludingInherited = () => [
    { GetBehavior: () => new TimerBehavior() },
  ];
  await load(win, f);
  const receiver = {};
  timerAction._func.call(receiver, 2, 0, 'renamed');
  assert.ok(receiver.scheduled.duration > 0 && receiver.scheduled.duration < 1 / 60);
});

test('a countdown sink under its enabled pause layer remains reachable on the next frame', async (t) => {
  const { win, f } = page(t);
  const { timerAction } = withInputCleanup(win, f);
  const parent = f.block([f.ace(f.sys.Cnds.LayerVisible, ['Overlay'])]);
  f.sink.parent = parent;
  parent.children.push(f.sink);
  f.pause.actions.push(f.ace(f.sys.Acts.SetLayerVisible, ['Overlay', 1]));
  f.manager._blocksBySid = new Map(f.all.map((b) => [b.sid, b]));
  await load(win, f);
  const receiver = {};
  timerAction._func.call(receiver, 2, 0, 'renamed');
  assert.ok(receiver.scheduled.duration > 0 && receiver.scheduled.duration < 1 / 60);
  assert.equal(win.__UGamesConstructAds.shortenedTimers, 1);
});

test('SDK close and failure cleanup can hide the pause layer while restoring game time', async (t) => {
  const { win, f } = page(t);
  const { timerAction } = withInputCleanup(win, f);
  const parent = withPauseLayer(f);
  for (const [fn, owner] of [
    [f.bridge.Cnds.OnInterstitialClosed, null],
    [f.bridge.Cnds.OnInterstitialFailed, parent],
  ]) {
    const reset = f.ace(f.sys.Acts.SetVar, [f.variable, 60]);
    reset._parameters[0]._eventVar = f.variable;
    const handler = f.block(
      [f.ace(fn)],
      [
        reset,
        f.ace(f.sys.Acts.SetLayerVisible, ['Overlay', 0]),
        f.ace(f.sys.Acts.SetTimescale, [1]),
      ],
      owner,
    );
    if (fn === f.bridge.Cnds.OnInterstitialClosed) {
      handler.IsOrBlock = () => true;
    }
  }
  f.manager._blocksBySid = new Map(f.all.map((b) => [b.sid, b]));
  await load(win, f);
  const receiver = {};
  timerAction._func.call(receiver, 2, 0, 'renamed');
  assert.ok(receiver.scheduled.duration > 0 && receiver.scheduled.duration < 1 / 60);
});

test('only the matched timer action and its original one-shot arguments are shortened', async (t) => {
  const { win, f } = page(t);
  const { timerAction } = withInputCleanup(win, f);
  await load(win, f);
  const receiver = {};
  for (const [duration, type, name] of [
    [3, 0, 'renamed'],
    [2, 1, 'renamed'],
    [2, 0, 'gameplay'],
  ]) {
    timerAction._func.call(receiver, duration, type, name);
    assert.deepEqual(receiver.scheduled, { duration, type, name });
  }
  f.timer.Acts.StartTimer.call(receiver, 2, 0, 'renamed');
  assert.equal(receiver.scheduled.duration, 2);
  timerAction._func.call(receiver, 2, 0, 'RENAMED');
  assert.ok(receiver.scheduled.duration > 0 && receiver.scheduled.duration < 1 / 60);
  const failure = new Error('timer failed');
  assert.throws(
    () => timerAction._func.call({ failure }, 2, 0, 'renamed'),
    (e) => e === failure,
  );
});

test('an input-cleanup timer is restored on pagehide and resumed without double wrapping', async (t) => {
  const { win, f } = page(t);
  const { timerAction } = withInputCleanup(win, f);
  const original = timerAction._func;
  await load(win, f);
  const immediate = timerAction._func;
  win.__UGamesConstructAds.inspect(f.runtime, true);
  assert.equal(timerAction._func, immediate);
  win.dispatchEvent(new win.Event('pagehide'));
  assert.equal(timerAction._func, original);
  assert.equal(win.__UGamesConstructAds.shortenedTimers, 0);
  win.dispatchEvent(new win.Event('pageshow'));
  assert.equal(timerAction._func, immediate);
  assert.equal(win.__UGamesConstructAds.shortenedTimers, 1);
});

test('externally replaced and readonly timer methods keep their own behavior', async (t) => {
  const { win, f } = page(t);
  const { timerAction } = withInputCleanup(win, f);
  await load(win, f);
  const external = () => 'external timer';
  timerAction._func = external;
  win.dispatchEvent(new win.Event('pagehide'));
  win.dispatchEvent(new win.Event('pageshow'));
  assert.equal(timerAction._func, external);
  assert.equal(win.__UGamesConstructAds.shortenedTimers, 0);

  const readonly = page(t);
  const second = withInputCleanup(readonly.win, readonly.f).timerAction;
  const original = second._func;
  Object.defineProperty(second, '_func', { writable: false });
  await load(readonly.win, readonly.f);
  assert.equal(second._func, original);
  assert.equal(readonly.win.__UGamesConstructAds.shortenedTimers, 0);
  assert.equal(readonly.win.__UGamesConstructAds.status, 'unsupported');
});

for (const [name, change] of [
  ['score writes', (f) => f.pause.actions.push(f.ace(f.sys.Acts.AddVar, [f.variable, 1]))],
  ['unknown actions', (f) => f.pause.actions.push(f.ace(method()))],
  [
    'rewarded ads',
    (f) => {
      f.sink.actions[0]._func = f.bridge.Acts.ShowRewarded;
    },
  ],
  [
    'repeating timers',
    (f, a) => {
      a._parameters[1] = constant(1);
    },
  ],
  [
    'nonzero input writes',
    (_f, _a, reset) => {
      reset._parameters[1] = constant(5);
    },
  ],
  [
    'gameplay references to the timer owner',
    (f) => {
      f.block([], [f.ace(f.sys.Acts.SetVar, [1], f.timerOwner)]);
      f.manager._blocksBySid = new Map(f.all.map((b) => [b.sid, b]));
    },
  ],
  [
    'an unreachable parent condition',
    (f) => {
      const parent = f.block([f.ace(f.sys.Cnds.CompareBoolVar, [f.variable])]);
      f.sink.parent = parent;
      parent.children.push(f.sink);
      f.manager._blocksBySid = new Map(f.all.map((b) => [b.sid, b]));
    },
  ],
  [
    'an unrelated event sheet',
    (f) => {
      f.sink.GetEventSheet = () => ({});
    },
  ],
  [
    'no independent timer-owner clock',
    (f) => {
      f.pause.actions = f.pause.actions.filter((a) => a._func !== f.sys.Acts.SetObjectTimescale);
    },
  ],
  [
    'a different object clock',
    (f) => {
      const clock = f.pause.actions.find((a) => a._func === f.sys.Acts.SetObjectTimescale);
      clock._parameters[0]._objectClass = f.overlay;
    },
  ],
  [
    'a conditional countdown function',
    (f) => {
      f.block([f.ace(f.sys.Cnds.CompareBoolVar, [f.variable])], [], f.pause);
      f.manager._blocksBySid = new Map(f.all.map((b) => [b.sid, b]));
    },
  ],
  [
    'a pause layer that is not enabled',
    (f) => {
      const parent = f.block([f.ace(f.sys.Cnds.LayerVisible, ['Other'])]);
      f.sink.parent = parent;
      parent.children.push(f.sink);
      f.manager._blocksBySid = new Map(f.all.map((b) => [b.sid, b]));
    },
  ],
  [
    'an inverted OnTimer condition',
    (f) => {
      f.sink.conditions[0].IsInverted = () => true;
    },
  ],
  [
    'an unrelated writer to its required pause layer',
    (f) => {
      withPauseLayer(f);
      f.block([], [f.ace(f.sys.Acts.SetLayerVisible, ['Overlay', 0])]);
      f.manager._blocksBySid = new Map(f.all.map((b) => [b.sid, b]));
    },
  ],
  [
    'a dynamic layer writer that could hide its pause layer',
    (f) => {
      withPauseLayer(f);
      const action = f.ace(f.sys.Acts.SetLayerVisible, ['Other', 0]);
      action._parameters[0] = {
        _type: 5,
        _numberedNodes: [{ _eventVar: f.variable }],
        _expressionFunc: method(),
        IsConstant: () => false,
      };
      f.block([], [action]);
      f.manager._blocksBySid = new Map(f.all.map((b) => [b.sid, b]));
    },
  ],
  [
    'a differently cased writer to its pause layer',
    (f) => {
      withPauseLayer(f);
      f.block([], [f.ace(f.sys.Acts.SetLayerVisible, ['overlay', 0])]);
      f.manager._blocksBySid = new Map(f.all.map((b) => [b.sid, b]));
    },
  ],
]) {
  test(`input cleanup does not allow shortening a timer with ${name}`, async (t) => {
    const { win, f } = page(t);
    const { timerAction, reset } = withInputCleanup(win, f);
    change(f, timerAction, reset);
    const original = timerAction._func;
    await load(win, f);
    assert.equal(timerAction._func, original);
    assert.equal(f.once.Run(), true);
    assert.equal(win.__UGamesConstructAds.shortenedTimers, 0);
    assert.equal(win.__UGamesConstructAds.status, 'unsupported');
  });
}

test('unrelated existing and late startup functions are never invoked by the detector', (t) => {
  let calls = 0;
  const existing = () => {
    calls++;
  };
  const { win } = page(t, (w) => {
    w.runOnStartup = existing;
  });
  assert.equal(calls, 0);
  assert.equal(win.runOnStartup, existing);
  const replacement = () => {
    calls++;
  };
  win.runOnStartup = replacement;
  assert.equal(calls, 0);
  assert.equal(win.runOnStartup, replacement);
});

test('an interstitial argument with a gameplay function keeps the whole countdown unchanged', async (t) => {
  const { win, f } = page(t, (_w, game) => {
    game.sink.actions[0]._parameters.push({
      _numberedNodes: [{ _functionBlock: {}, _functionName: 'SetScore' }],
    });
  });
  await load(win, f);
  assert.equal(f.once.Run(), true);
  assert.equal(win.__UGamesConstructAds.blockedGates, 0);
});

test('published factory automatically blocks the proven countdown before gameplay', async (t) => {
  const { win, f } = page(t);
  await load(win, f);
  for (let i = 0; i < 90; i++) {
    f.second();
  }
  assert.equal(f.runtime.paused, undefined);
  assert.equal(f.variable.value, 0);
  assert.equal(win.__UGamesConstructAds?.blockedGates, 1);
  assert.equal(win.__UGamesConstructAds.status, 'active');
  assert.equal((await f.once.DebugRun().next()).value, false);
});

test('modern init registrar captures runtimes with private DOM interfaces', async (t) => {
  const { win, f } = page(t);
  let create, init;
  win.C3_SetInitFunctions = function (factory, initializer) {
    assert.equal(this, win);
    create = factory;
    init = initializer;
    win.C3_SetInitFunctions = null;
    return 27;
  };
  const originalInit = (raw) => raw._LoadDataJson(42);
  assert.equal(
    win.C3_SetInitFunctions(() => f.runtime, originalInit),
    27,
  );
  assert.equal(init, originalInit);
  assert.equal(await init(create()), 42);
  assert.equal(f.once.Run(), false);
});

test('existing runtime fallback and reload do not double-patch', (t) => {
  const { win, f } = page(t, (w, graph) => {
    w.c3_runtimeInterface = { _GetLocalRuntime: () => graph.runtime };
  });
  const run = f.once.Run;
  win.eval(source());
  win.__UGamesConstructAds.inspect(f.runtime);
  assert.equal(f.once.Run, run);
  assert.equal(win.__UGamesConstructAds.inspectedRuntimes, 1);
});

test('page lifecycle restores and resumes the same condition without changing globals', async (t) => {
  let original;
  const { win, f } = page(t, (_w, graph) => {
    original = graph.once.Run;
  });
  await load(win, f);
  win.dispatchEvent(new win.Event('pagehide'));
  assert.equal(f.once.Run, original);
  f.variable.value = 7;
  win.dispatchEvent(new win.Event('pageshow'));
  assert.equal(f.once.Run(), false);
  assert.equal(f.variable.value, 7);
  assert.equal(win.__UGamesConstructAds.blockedGates, 1);
});

test('a shared counter and independent gameplay event keep their values and behavior', async (t) => {
  const { win, f } = page(t);
  let score = 0;
  const scoreAction = f.ace(f.sys.Acts.AddVar, [f.variable, 10]);
  scoreAction.Run = () => {
    score += 10;
  };
  f.block([], [scoreAction]);
  f.manager._blocksBySid = new Map(f.all.map((b) => [b.sid, b]));
  await load(win, f);
  scoreAction.Run();
  assert.equal(score, 10);
  assert.equal(f.variable.value, 60);
  assert.equal(f.once.Run(), false);
});

for (const [name, change] of [
  [
    'mixed score in pause function',
    (f) => f.pause.actions.push(f.ace(f.sys.Acts.AddVar, [f.variable, 1])),
  ],
  [
    'mixed score in triggering event',
    (f) => f.trigger.actions.push(f.ace(f.sys.Acts.SetVar, [f.variable, 1])),
  ],
  [
    'OR event',
    (f) => {
      f.trigger.IsOrBlock = () => true;
    },
  ],
  [
    'following Else event',
    (f) => {
      f.trigger.HasElseBlock = () => true;
    },
  ],
  [
    'rewarded ad',
    (f) => {
      f.sink.actions[0]._func = f.bridge.Acts.ShowRewarded;
    },
  ],
  ['unknown function', (f) => f.pause.actions.push(f.ace(method()))],
  ['unknown script child', (f) => f.pause.children.push({ Run() {} })],
  [
    'wrong timer behavior',
    (f) => {
      f.sink.conditions[0]._behaviorType = {};
    },
  ],
  [
    'wrong timer tag',
    (f) => {
      f.sink.conditions[0]._parameters[0] = constant('gameplay');
    },
  ],
  [
    'UI object read by gameplay expression',
    (f) => {
      const action = f.ace(f.sys.Acts.SetVar, [1]);
      action._parameters.push({ _numberedNodes: [{ _objectClass: f.overlay }] });
      f.block([], [action]);
    },
  ],
  [
    'ordinary score threshold without periodic timer',
    (f) => {
      f.all[0].conditions = [];
    },
  ],
]) {
  test(`leaves ${name} unchanged`, async (t) => {
    const { win, f } = page(t);
    change(f);
    f.manager._blocksBySid = new Map(f.all.map((b) => [b.sid, b]));
    const original = f.once.Run;
    await load(win, f);
    assert.equal(f.once.Run, original);
    assert.equal(win.__UGamesConstructAds?.blockedGates, 0);
    assert.equal(win.__UGamesConstructAds?.status, 'unsupported');
  });
}

test('known Playgama gameplay-stop notification stays inside the suppressed ad event', async (t) => {
  const { win, f } = page(t);
  f.block([], [f.ace(f.bridge.Acts.SendMessage, [4])], f.trigger);
  f.manager._blocksBySid = new Map(f.all.map((b) => [b.sid, b]));
  await load(win, f);
  assert.equal(f.once.Run(), false);
});

test('factory exceptions and unsupported engines keep original contracts', async (t) => {
  const { win } = page(t);
  const failure = new Error('game creation failed');
  win.C3_CreateRuntime = () => {
    throw failure;
  };
  assert.throws(
    () => win.C3_CreateRuntime(),
    (error) => error === failure,
  );
  const unknown = { _LoadDataJson: () => 17 };
  win.C3_CreateRuntime = () => unknown;
  assert.equal(win.C3_CreateRuntime()._LoadDataJson(), 17);
});

test('literal layer parameters are read without resolving an unstarted layout', async (t) => {
  const { win, f } = page(t);
  const layer = {
    _type: 5,
    _numberedNodes: [],
    _expressionFunc: () => 'Overlay',
    IsConstant: () => false,
    Get: () => {
      throw new Error('layout not running yet');
    },
  };
  const visible = f.ace(f.sys.Acts.SetLayerVisible, ['Overlay', 1]);
  visible._parameters[0] = layer;
  f.pause.actions.push(visible);
  await load(win, f);
  assert.equal(f.once.Run(), false);
});

test('an ad timer may reset its own periodic counter to the declared initial value', async (t) => {
  const { win, f } = page(t);
  const reset = f.ace(f.sys.Acts.SetVar, [f.variable, 60]);
  reset._parameters[0] = { ...constant(f.variable), _eventVar: f.variable };
  f.sink.actions.push(reset);
  await load(win, f);
  assert.equal(f.once.Run(), false);
  assert.equal(f.variable.value, 60);
});

test('a timer sink with an unrelated score write remains unchanged', async (t) => {
  const { win, f } = page(t);
  const other = { GetInitialValue: () => 60 };
  const score = f.ace(f.sys.Acts.SetVar, [other, 60]);
  score._parameters[0] = { ...constant(other), _eventVar: other };
  f.sink.actions.push(score);
  await load(win, f);
  assert.equal(f.once.Run(), true);
});

test('unchanged alternative ad branches may have an Else while sharing ad UI', async (t) => {
  const { win, f } = page(t);
  const alternative = f.block(
    [],
    [
      f.ace(f.bridge.Acts.ShowInterstitial, [true]),
      f.ace(f.sprite.Acts.SetVisible, [0], f.overlay),
    ],
  );
  alternative.HasElseBlock = () => true;
  f.manager._blocksBySid = new Map(f.all.map((b) => [b.sid, b]));
  await load(win, f);
  assert.equal(f.once.Run(), false);
  assert.equal(alternative.actions[0].Run(), true);
});

test('node-free layer expressions with statements are never executed during inspection', async (t) => {
  const { win, f } = page(t);
  let calls = 0;
  const visible = f.ace(f.sys.Acts.SetLayerVisible, ['Overlay', 1]);
  visible._parameters[0] = {
    _type: 5,
    _numberedNodes: [],
    _expressionFunc: () => {
      calls++;
      return 'Overlay';
    },
    IsConstant: () => false,
  };
  f.pause.actions.push(visible);
  await load(win, f);
  assert.equal(calls, 0);
  assert.equal(f.once.Run(), true);
});

for (const name of ['Run', 'DebugRun']) {
  test(`readonly ${name} rejects suppression transactionally`, async (t) => {
    const { win, f } = page(t);
    const run = f.once.Run,
      debug = f.once.DebugRun;
    Object.defineProperty(f.once, name, { value: f.once[name], writable: false });
    await load(win, f);
    assert.equal(f.once.Run, run);
    assert.equal(f.once.DebugRun, debug);
    assert.equal(win.__UGamesConstructAds.blockedGates, 0);
    assert.equal(win.__UGamesConstructAds.status, 'unsupported');
    win.dispatchEvent(new win.Event('pagehide'));
    win.dispatchEvent(new win.Event('pageshow'));
    assert.equal(f.once.Run, run);
    assert.equal(f.once.DebugRun, debug);
  });
}

test('existing readonly factory publication keeps its property contract', (t) => {
  let original;
  const { win, f } = page(t, (w, graph) => {
    original = () => graph.runtime;
    Object.defineProperty(w, 'C3_CreateRuntime', {
      value: original,
      writable: false,
      configurable: true,
    });
  });
  const descriptor = Object.getOwnPropertyDescriptor(win, 'C3_CreateRuntime');
  assert.equal(descriptor.writable, false);
  assert.equal(descriptor.value, original);
  assert.equal(win.C3_CreateRuntime(), f.runtime);
});

test('pageshow during data loading does not seal an empty runtime before project initialization', async (t) => {
  let complete;
  const { win, f } = page(t, (w, graph) => {
    complete = graph.manager._blocksBySid;
    graph.manager._blocksBySid = new Map();
    w.c3_runtimeInterface = { _GetLocalRuntime: () => graph.runtime };
    graph.runtime._LoadDataJson = async function () {
      graph.manager._blocksBySid = complete;
    };
  });
  win.dispatchEvent(new win.Event('pageshow'));
  win.C3_CreateRuntime = () => f.runtime;
  await win.C3_CreateRuntime()._LoadDataJson();
  assert.equal(f.once.Run(), false);
  assert.equal(win.__UGamesConstructAds.inspectedRuntimes, 1);
});

test('the final Start boundary inspects resolved event data before game code executes', async (t) => {
  const { win, f } = page(t);
  f.runtime._LoadDataJson = async function () {
    this.savedActions = f.pause.actions;
    f.pause.actions = [];
  };
  f.runtime.Start = function (value) {
    assert.equal(this, f.runtime);
    assert.equal(f.once.Run(), false);
    return value;
  };
  win.C3_CreateRuntime = () => f.runtime;
  const raw = win.C3_CreateRuntime();
  await raw._LoadDataJson();
  f.pause.actions = raw.savedActions;
  assert.equal(raw.Start(99), 99);
  assert.equal(win.__UGamesConstructAds.inspectedRuntimes, 1);
});

test('an automatically moving gameplay object cannot be claimed as exclusive ad UI', async (t) => {
  const { win, f } = page(t);
  f.overlay.GetBehaviorTypesIncludingInherited = () => [{ GetBehavior: () => ({ physics: true }) }];
  await load(win, f);
  assert.equal(f.once.Run(), true);
  assert.equal(win.__UGamesConstructAds.blockedGates, 0);
});

test('a known worker runtime reports unsupported without changing its execution mode', (t) => {
  const { win } = page(t, (w) => {
    w.c3_runtimeInterface = { UsesWorker: () => true };
  });
  assert.equal(win.__UGamesConstructAds.status, 'unsupported');
  assert.equal(win.__UGamesConstructAds.blockedGates, 0);
  win.dispatchEvent(new win.Event('pageshow'));
  assert.equal(win.__UGamesConstructAds.status, 'unsupported');
});

test('node-free SDK argument expressions with side effects reject the countdown without execution', async (t) => {
  const { win, f } = page(t);
  let calls = 0;
  const expression = () => {
    calls++;
    return false;
  };
  f.sink.actions[0]._parameters[0] = {
    _type: 1,
    _numberedNodes: [],
    _expressionFunc: expression,
    IsConstant: () => true,
    Get: expression,
  };
  await load(win, f);
  assert.equal(calls, 0);
  assert.equal(f.once.Run(), true);
  assert.equal(win.__UGamesConstructAds.status, 'unsupported');
});

test('an expression parameter claiming to be constant cannot execute an unknown getter', async (t) => {
  const { win, f } = page(t);
  let calls = 0;
  f.trigger.GetParent().conditions[0]._parameters[2] = {
    _type: 7,
    IsConstant: () => true,
    Get: () => {
      calls++;
      return 0;
    },
  };
  await load(win, f);
  assert.equal(calls, 0);
  assert.equal(f.once.Run(), true);
  assert.equal(win.__UGamesConstructAds.status, 'unsupported');
});

test('literal expression values bypass their getters for every expression parameter type', async (t) => {
  const { win, f } = page(t);
  const literal = () => 2;
  f.pause.actions[1]._parameters[0] = {
    _type: 0,
    _numberedNodes: [],
    _expressionFunc: literal,
    IsConstant: () => true,
    Get: () => {
      throw new Error('must parse the literal');
    },
  };
  await load(win, f);
  assert.equal(f.once.Run(), false);
});

for (const externalKey of ['Run', 'DebugRun']) {
  test(`pagehide restores the still-owned method when ${externalKey} is replaced externally`, async (t) => {
    const { win, f } = page(t);
    const original = { Run: f.once.Run, DebugRun: f.once.DebugRun };
    await load(win, f);
    const replacement = () => 'external behavior';
    f.once[externalKey] = replacement;
    win.dispatchEvent(new win.Event('pagehide'));
    assert.equal(f.once[externalKey], replacement);
    const ownedKey = externalKey === 'Run' ? 'DebugRun' : 'Run';
    assert.equal(f.once[ownedKey], original[ownedKey]);
    assert.equal(win.__UGamesConstructAds.blockedGates, 0);
    win.dispatchEvent(new win.Event('pageshow'));
    assert.equal(f.once[externalKey], replacement);
    assert.equal(f.once[ownedKey], original[ownedKey]);
  });
}
