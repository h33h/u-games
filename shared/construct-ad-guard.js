(function installConstructAdGuard(win) {
  'use strict';
  if (win.__UGamesConstructAds?.version === 1) {
    return;
  }
  const state = {
    version: 1,
    status: 'waiting',
    blockedGates: 0,
    shortenedTimers: 0,
    inspectedRuntimes: 0,
  };
  Object.defineProperty(win, '__UGamesConstructAds', { value: state });
  if (!win.document) {
    state.status = 'unsupported';
    return;
  }
  const inspected = new WeakSet();
  const captured = new WeakSet();
  const patched = new WeakSet();
  const patches = [];
  const timerPatches = [];
  const unknown = Symbol('unknown parameter');
  let active = true;
  const refresh = () => {
    state.blockedGates = patches.filter(
      (p) => p.condition.Run === p.blocked && p.condition.DebugRun === p.blockedDebug,
    ).length;
    state.shortenedTimers = timerPatches.filter((p) => p.action._func === p.immediate).length;
    state.status =
      state.blockedGates || state.shortenedTimers
        ? 'active'
        : state.inspectedRuntimes || state.workerRuntime
          ? 'unsupported'
          : 'waiting';
  };
  const params = (ace) => (Array.isArray(ace?._parameters) ? ace._parameters : []);
  const isExpression = (p) =>
    p &&
    typeof p === 'object' &&
    ('_expressionFunc' in p || '_numberedNodes' in p || [0, 1, 5, 7, 14].includes(p._type));
  function literalExpression(expression) {
    const source = Function.prototype.toString.call(expression).trim();
    const arrow = source.match(/^\(\s*\)\s*=>\s*([\s\S]+)$/);
    const normal = source.match(/^function(?:\s+[\w$]+)?\s*\(\s*\)\s*(\{[\s\S]*\})$/);
    let body = arrow?.[1] ?? normal?.[1];
    if (!body) {
      return unknown;
    }
    if (body.startsWith('{')) {
      body = body.match(/^\{\s*return[ \t]+([^\r\n]*?)\s*;?\s*\}$/)?.[1];
    }
    if (
      !body ||
      !/^(?:"(?:[^"\\\r\n]|\\(?:["'\\/bfnrt]|u[\da-fA-F]{4}))*"|'(?:[^'\\\r\n]|\\(?:["'\\/bfnrt]|u[\da-fA-F]{4}))*'|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?|true|false|null)$/.test(
        body,
      )
    ) {
      return unknown;
    }
    // Decode a string literal without evaluating the expression's code.
    const json = body.startsWith("'")
      ? '"' +
        body
          .slice(1, -1)
          .replace(/\\'|\\[\s\S]|"/g, (token) =>
            token === "\\'" ? "'" : token === '"' ? '\\"' : token,
          ) +
        '"'
      : body;
    try {
      return JSON.parse(json);
    } catch (_) {
      return unknown;
    }
  }
  function value(ace, index) {
    const p = params(ace)[index];
    // Even "constant" expression Get methods can execute project code. Resolve
    // node-free literals from their source; never invoke an expression getter.
    if (isExpression(p)) {
      return Array.isArray(p._numberedNodes) &&
        !p._numberedNodes.length &&
        typeof p._expressionFunc === 'function'
        ? literalExpression(p._expressionFunc)
        : unknown;
    }
    if (typeof p?.IsConstant !== 'function' || !p.IsConstant() || typeof p.Get !== 'function') {
      return unknown;
    }
    try {
      return p.Get(0);
    } catch (_) {
      return unknown;
    }
  }
  const isBlock = (block) =>
    [
      'GetConditions',
      'GetActions',
      'GetSubEvents',
      'GetParent',
      'IsOrBlock',
      'IsElseBlock',
      'HasElseBlock',
    ].every((name) => typeof block?.[name] === 'function');
  const ordinary = (block) =>
    isBlock(block) && !block.IsOrBlock() && !block.IsElseBlock() && !block.HasElseBlock();
  function ancestors(block) {
    const result = [];
    while (block && result.length < 64 && !result.includes(block)) {
      result.push(block);
      block = block.GetParent?.();
    }
    return result;
  }
  function nodes(ace, visit) {
    const seen = new Set();
    function walk(p) {
      if (!p || typeof p !== 'object' || seen.has(p)) {
        return;
      }
      seen.add(p);
      visit(p);
      for (const key of ['_numberedNodes', '_subParams']) {
        if (Array.isArray(p[key])) {
          for (const child of p[key]) {
            walk(child);
          }
        }
      }
    }
    if (ace?._objectClass) {
      visit(ace);
    }
    for (const p of params(ace)) {
      walk(p);
    }
  }

  function analyze(engine) {
    const manager = engine?.GetEventSheetManager?.();
    const map = manager?._blocksBySid;
    if (!map || typeof map.values !== 'function') {
      return [];
    }
    const blocks = Array.from(map.values());
    if (!blocks.length || blocks.length > 20000 || !blocks.every(isBlock)) {
      return [];
    }
    const knownBlocks = new Set(blocks);
    const C3 = win.C3;
    const system = C3?.Plugins?.System;
    const timer = C3?.Behaviors?.Timer;
    if (!system?.Cnds?.TriggerOnce || !timer?.Acts?.StartTimer || !timer.Cnds?.OnTimer) {
      return [];
    }
    const select = (object, names) =>
      names.map((name) => object?.[name]).filter((fn) => typeof fn === 'function');
    const interstitial = new Set(
      [
        C3.Plugins.PlaygamaBridge?.Acts?.ShowInterstitial,
        C3.Plugins.InstantGamesBridge?.Acts?.ShowInterstitial,
      ].filter((fn) => typeof fn === 'function'),
    );
    if (!interstitial.size) {
      return [];
    }
    const uiPlugins = new Set([C3.Plugins.Sprite, C3.Plugins.Text].filter(Boolean));
    const pluginType = (object) => {
      const plugin = object?.GetPlugin?.();
      return typeof plugin?.GetConstructor === 'function'
        ? plugin.GetConstructor()
        : plugin?.constructor;
    };
    const uiBehaviorConstructors = new Set(
      ['Timer', 'Tween', 'Pin', 'Fade'].map((name) => C3.Behaviors[name]).filter(Boolean),
    );
    const uiBehaviors = new Set(
      ['Timer', 'Tween', 'Pin', 'Fade']
        .map((name) => C3.AddonManager?.GetBehaviorByConstructorFunction?.(C3.Behaviors[name]))
        .filter(Boolean),
    );
    function uiObject(object) {
      const behaviors = object?.GetBehaviorTypesIncludingInherited?.();
      return (
        !object?.IsFamily?.() &&
        uiPlugins.has(pluginType(object)) &&
        Array.isArray(behaviors) &&
        behaviors.every((type) => {
          const behavior = type.GetBehavior?.();
          return uiBehaviors.has(behavior) || uiBehaviorConstructors.has(behavior?.constructor);
        })
      );
    }
    const presentation = new Set([
      ...select(C3.Plugins.Sprite?.Acts, ['SetPos', 'SetSize', 'SetWidth', 'SetVisible']),
      ...select(C3.Plugins.Text?.Acts, ['SetVisible']),
      ...select(C3.Behaviors.Tween?.Acts, ['TweenOneProperty', 'TweenTwoProperties']),
      ...select(C3.Behaviors.Pin?.Acts, ['PinByProperties']),
    ]);
    const conditions = new Set(
      [
        ...select(system.Cnds, [
          'CompareVar',
          'CompareBoolVar',
          'Compare',
          'TriggerOnce',
          'LayerVisible',
        ]),
        ...select(C3.Plugins.Touch?.Cnds, ['IsInTouch']),
        timer.Cnds.OnTimer,
        timer.Cnds.IsTimerRunning,
      ].filter((fn) => typeof fn === 'function'),
    );
    const expressions = new Set([
      ...select(system.Exps, [
        'viewportleft',
        'viewporttop',
        'viewportright',
        'viewportbottom',
        'viewportmidx',
        'viewportmidy',
        'viewportwidth',
        'viewportheight',
        'int',
        'floor',
        'ceil',
        'round',
        'min',
        'max',
        'abs',
      ]),
      ...select(C3.Plugins.Sprite?.Exps, ['X', 'Y', 'LayerName']),
      ...select(timer.Exps, ['CurrentTime']),
      ...select(C3.Plugins.PlaygamaBridge?.Exps, ['PlatformId']),
      ...select(C3.Plugins.InstantGamesBridge?.Exps, ['PlatformId']),
    ]);
    function safeExpressions(ace) {
      let safe = true;
      nodes(ace, (node) => {
        if (
          isExpression(node) &&
          (!Array.isArray(node._numberedNodes) ||
            typeof node._expressionFunc !== 'function' ||
            (!node._numberedNodes.length && literalExpression(node._expressionFunc) === unknown))
        ) {
          safe = false;
        }
        if (
          node !== ace &&
          (node._functionBlock ||
            node._functionName ||
            (node._func && !expressions.has(node._func)))
        ) {
          safe = false;
        }
      });
      return safe;
    }
    const safeConditions = (block) =>
      block
        .GetConditions()
        .every((condition) => conditions.has(condition._func) && safeExpressions(condition));
    const sameTimer = (ace, started, tagIndex) =>
      ace._objectClass === started._objectClass &&
      ace._behaviorType === started._behaviorType &&
      typeof value(ace, tagIndex) === 'string' &&
      value(ace, tagIndex).toLowerCase() === value(started, 2).toLowerCase();

    // Input cleanup is recognized only in the mode that keeps every action and
    // shortens a proven ad timer. It must never permit skipping gameplay writes.
    function region(root, ownershipOnly = false, preserveControls = false) {
      const result = {
        blocks: new Set(),
        ui: new Set(),
        timers: [],
        pauses: 0,
        ads: 0,
        controls: 0,
      };
      const visiting = new Set();
      function walk(block) {
        // An unchanged alternative ad branch can have a following Else. It is
        // inspected only to establish UI ownership; we never suppress it.
        const allowedFollowingElse = ownershipOnly && block === root;
        if (
          visiting.has(block) ||
          !knownBlocks.has(block) ||
          !isBlock(block) ||
          block.IsOrBlock() ||
          block.IsElseBlock() ||
          (!allowedFollowingElse && block.HasElseBlock()) ||
          !safeConditions(block)
        ) {
          return false;
        }
        if (result.blocks.has(block)) {
          return true;
        }
        if (result.blocks.size >= 256) {
          return false;
        }
        visiting.add(block);
        result.blocks.add(block);
        for (const action of block.GetActions()) {
          if (!safeExpressions(action)) {
            return false;
          }
          if (!action._callEventBlock && typeof action._func !== 'function') {
            return false;
          }
          if (action._callEventBlock) {
            if (params(action).length || !walk(action._callEventBlock)) {
              return false;
            }
          } else if (action._func === system.Acts.SetTimescale) {
            if (value(action, 0) !== 0) {
              return false;
            }
            result.pauses++;
          } else if (action._func === timer.Acts.StartTimer) {
            const duration = value(action, 0);
            if (
              !(
                typeof duration === 'number' &&
                Number.isFinite(duration) &&
                duration > 0 &&
                duration <= 30
              ) ||
              value(action, 1) !== 0 ||
              typeof value(action, 2) !== 'string' ||
              !action._objectClass ||
              !action._behaviorType ||
              action._objectClass.IsFamily?.()
            ) {
              return false;
            }
            result.timers.push(action);
            result.ui.add(action._objectClass);
          } else if (presentation.has(action._func)) {
            if (!action._objectClass || action._objectClass.IsFamily?.()) {
              return false;
            }
            result.ui.add(action._objectClass);
          } else if (action._func === system.Acts.SetLayerVisible) {
            if (typeof value(action, 0) !== 'string' || ![0, 1].includes(value(action, 1))) {
              return false;
            }
          } else if (action._func === system.Acts.SetObjectTimescale) {
            if (value(action, 1) !== 1 || !params(action)[0]?._objectClass) {
              return false;
            }
          } else if (action._func === C3.Plugins.Audio?.Acts?.SetMasterVolume) {
            if (typeof value(action, 0) !== 'number' || !Number.isFinite(value(action, 0))) {
              return false;
            }
          } else if (action._func === C3.Plugins.PlaygamaBridge?.Acts?.SendMessage) {
            // Playgama's exported actions.js maps 4 to GAMEPLAY_STOPPED.
            if (value(action, 0) !== 4) {
              return false;
            }
          } else if (interstitial.has(action._func)) {
            result.ads++;
          } else if (
            preserveControls &&
            pluginType(action._objectClass) === C3.Plugins.Sprite &&
            ((action._func === C3.Plugins.Sprite?.Acts?.SetInstanceVar &&
              params(action)[0]?._type === 10 &&
              Number.isInteger(params(action)[0]._instVarIndex) &&
              params(action)[0]._instVarIndex >= 0 &&
              value(action, 1) === 0) ||
              (action._func === C3.Behaviors.DragnDrop?.Acts?.SetEnabled &&
                action._behaviorType &&
                value(action, 0) === 0))
          ) {
            result.controls++;
          } else {
            return false;
          }
        }
        for (const child of block.GetSubEvents()) {
          if (!walk(child)) {
            return false;
          }
        }
        visiting.delete(block);
        return true;
      }
      return walk(root) ? result : null;
    }
    function periodicCounter(trigger) {
      for (const parent of ancestors(trigger)) {
        if (!ordinary(parent)) {
          return false;
        }
        for (const condition of parent.GetConditions()) {
          if (condition._func !== system.Cnds.CompareVar || condition.IsInverted?.()) {
            continue;
          }
          const variable = params(condition)[0]?._eventVar;
          const comparison = value(condition, 1),
            threshold = value(condition, 2);
          const initial = variable?.GetInitialValue?.();
          if (
            !variable?.IsGlobal?.() ||
            !variable.IsNumber?.() ||
            !Number.isFinite(initial) ||
            !Number.isFinite(threshold) ||
            ![2, 3, 4, 5].includes(comparison)
          ) {
            continue;
          }
          const decreasing = comparison < 4;
          if (decreasing ? initial <= threshold : initial >= threshold) {
            continue;
          }
          for (const block of blocks) {
            const every = ancestors(block).some(
              (b) =>
                isBlock(b) &&
                b
                  .GetConditions()
                  .some(
                    (c) =>
                      c._func === system.Cnds.Every &&
                      Number.isFinite(value(c, 0)) &&
                      value(c, 0) > 0,
                  ),
            );
            if (!every) {
              continue;
            }
            for (const action of block.GetActions()) {
              if (params(action)[0]?._eventVar !== variable) {
                continue;
              }
              const amount = value(action, 1);
              const delta =
                action._func === system.Acts.SubVar
                  ? -amount
                  : action._func === system.Acts.AddVar
                    ? amount
                    : NaN;
              if (Number.isFinite(delta) && (decreasing ? delta < 0 : delta > 0)) {
                return variable;
              }
            }
          }
        }
      }
      return false;
    }
    function labelRegion(root, started) {
      if (
        !root
          .GetConditions()
          .some((c) => c._func === timer.Cnds.IsTimerRunning && sameTimer(c, started, 0))
      ) {
        return null;
      }
      const result = new Set();
      function walk(block) {
        if (
          !ordinary(block) ||
          !knownBlocks.has(block) ||
          !safeConditions(block) ||
          result.has(block)
        ) {
          return false;
        }
        result.add(block);
        if (
          !block
            .GetActions()
            .every(
              (a) =>
                a._func === C3.Plugins.Text?.Acts?.SetText &&
                a._objectClass === started._objectClass &&
                safeExpressions(a),
            )
        ) {
          return false;
        }
        return block.GetSubEvents().every(walk);
      }
      return walk(root) ? result : null;
    }
    function canShortenTimer(trigger, started, sink, counter) {
      const sheet = trigger.GetEventSheet?.();
      const path = ancestors(trigger);
      if (
        !sheet ||
        sink.GetEventSheet?.() !== sheet ||
        trigger.GetSubEvents().length ||
        path[path.length - 1].GetParent() ||
        path.some(
          (block) =>
            !ordinary(block) ||
            block.GetEventSheet?.() !== sheet ||
            !block.GetConditions().length ||
            !safeConditions(block) ||
            (block !== trigger && block.GetActions().length),
        )
      ) {
        return false;
      }
      // The mixed function must finish synchronously before the next tick.
      // Flatten only unconditional calls, retaining their actual action order.
      const actions = [];
      const visiting = new Set();
      const completionBlock = (block) =>
        isBlock(block) &&
        block.GetConditions().length === 1 &&
        !block.IsElseBlock() &&
        !block.HasElseBlock();
      function flatten(block, output = actions, handler = false) {
        if (
          !knownBlocks.has(block) ||
          !(handler ? completionBlock(block) : ordinary(block)) ||
          visiting.has(block) ||
          (!handler && block.GetConditions().length) ||
          block.GetSubEvents().length ||
          output.length > 256
        ) {
          return false;
        }
        visiting.add(block);
        for (const action of block.GetActions()) {
          if (action._callEventBlock) {
            if (!flatten(action._callEventBlock, output)) {
              return false;
            }
          } else {
            output.push(action);
          }
        }
        visiting.delete(block);
        return output.length <= 256;
      }
      if (
        !flatten(trigger.GetActions()[0]._callEventBlock) ||
        actions.filter((action) => action === started).length !== 1 ||
        !actions.some(
          (action) =>
            action._func === system.Acts.SetObjectTimescale &&
            params(action)[0]?._objectClass === started._objectClass &&
            value(action, 1) === 1,
        )
      ) {
        return false;
      }
      const visible = new Map();
      const layerName = (ace) => {
        const name = value(ace, 0);
        return typeof name === 'string' ? name.toLowerCase() : unknown;
      };
      for (const action of actions) {
        if (action._func === system.Acts.SetLayerVisible) {
          visible.set(layerName(action), value(action, 1) === 1);
        }
      }
      const sinkPath = ancestors(sink);
      const reachable = (block) =>
        ordinary(block) &&
        block.GetEventSheet?.() === sheet &&
        !block.GetActions().length &&
        block.GetConditions().length &&
        block
          .GetConditions()
          .every(
            (condition) =>
              condition._func === system.Cnds.LayerVisible &&
              !condition.IsInverted?.() &&
              visible.get(layerName(condition)) === true,
          );
      if (!(
        !sink.GetConditions()[0].IsInverted?.() &&
        !sinkPath[sinkPath.length - 1].GetParent() &&
        sinkPath.slice(1).every(reachable)
      )) {
        return false;
      }
      const gatingLayers = new Set(
        sinkPath.slice(1).flatMap((block) => block.GetConditions().map(layerName)),
      );
      if (!gatingLayers.size) {
        return true;
      }
      const completion = new Set([
        ...select(C3.Plugins.InstantGamesBridge?.Cnds, [
          'OnInterstitialClosed',
          'OnInterstitialFailed',
        ]),
        ...select(C3.Plugins.PlaygamaBridge?.Cnds, [
          'OnInterstitialClosed',
          'OnInterstitialFailed',
        ]),
      ]);
      const body = new Set(actions);
      for (const block of blocks) {
        for (const action of block.GetActions()) {
          if (action._func !== system.Acts.SetLayerVisible) {
            continue;
          }
          const layer = layerName(action);
          // A dynamic name or index might target the required pause layer.
          if (typeof layer !== 'string') {
            return false;
          }
          if (!gatingLayers.has(layer)) {
            continue;
          }
          if (body.has(action) && value(action, 1) === 1) {
            continue;
          }
          const conditions = block.GetConditions();
          const path = ancestors(block);
          const cleanup = [];
          if (
            conditions.length !== 1 ||
            !completionBlock(block) ||
            block.GetEventSheet?.() !== sheet ||
            !completion.has(conditions[0]._func) ||
            conditions[0].IsInverted?.() ||
            conditions[0]._objectClass !== sink.GetActions()[0]._objectClass ||
            path[path.length - 1].GetParent() ||
            !path.slice(1).every(reachable) ||
            !flatten(block, cleanup, true) ||
            !cleanup.some((a) => a._func === system.Acts.SetTimescale && value(a, 0) === 1) ||
            !cleanup.every(
              (a) =>
                safeExpressions(a) &&
                ((a._func === system.Acts.SetTimescale && value(a, 0) === 1) ||
                  (a._func === system.Acts.SetLayerVisible &&
                    typeof value(a, 0) === 'string' &&
                    value(a, 1) === 0) ||
                  (a._func === system.Acts.SetVar &&
                    params(a)[0]?._eventVar === counter &&
                    value(a, 1) === counter.GetInitialValue()) ||
                  (a._func === C3.Plugins.Audio?.Acts?.SetMasterVolume &&
                    Number.isFinite(value(a, 0)))),
            )
          ) {
            return false;
          }
        }
      }
      return true;
    }
    const found = [];
    for (const trigger of blocks) {
      if (
        !ordinary(trigger) ||
        trigger.GetConditions().length !== 1 ||
        trigger.GetConditions()[0]._func !== system.Cnds.TriggerOnce ||
        trigger.GetActions().length !== 1 ||
        !trigger.GetActions()[0]._callEventBlock
      ) {
        continue;
      }
      const counter = periodicCounter(trigger);
      if (!counter) {
        continue;
      }
      let proof = region(trigger);
      let preserveControls = false;
      if (!proof) {
        proof = region(trigger, false, true);
        preserveControls = !!proof?.controls;
      }
      if (!proof || !proof.pauses || proof.timers.length !== 1) {
        continue;
      }
      if (![...proof.ui].every(uiObject)) {
        continue;
      }
      const started = proof.timers[0];
      const consumers = blocks.filter((b) =>
        b.GetConditions().some((c) => c._func === timer.Cnds.OnTimer && sameTimer(c, started, 0)),
      );
      if (consumers.length !== 1) {
        continue;
      }
      const sink = consumers[0];
      if (
        !ordinary(sink) ||
        sink.GetConditions().length !== 1 ||
        sink.GetSubEvents().length ||
        !sink.GetActions().every(safeExpressions) ||
        !interstitial.has(sink.GetActions()[0]?._func)
      ) {
        continue;
      }
      // Some export versions reset this same ad counter in the timer event.
      // Writes to any other variable, or to an arbitrary value, are gameplay.
      if (
        !sink
          .GetActions()
          .slice(1)
          .every(
            (a) =>
              a._func === system.Acts.SetVar &&
              params(a)[0]?._eventVar === counter &&
              value(a, 1) === counter.GetInitialValue(),
          )
      ) {
        continue;
      }
      if (preserveControls && !canShortenTimer(trigger, started, sink, counter)) {
        continue;
      }
      const allowed = new Set([...proof.blocks, sink]);
      for (const block of blocks) {
        const labels = labelRegion(block, started);
        if (labels) {
          for (const b of labels) {
            allowed.add(b);
          }
        }
        if (block.GetActions().some((a) => interstitial.has(a._func))) {
          const alternative = region(block, true);
          if (alternative?.ads && !alternative.timers.length) {
            for (const b of alternative.blocks) {
              allowed.add(b);
            }
          }
        }
      }
      let exclusive = true;
      for (const block of blocks) {
        if (allowed.has(block)) {
          continue;
        }
        for (const ace of [...block.GetConditions(), ...block.GetActions()]) {
          nodes(ace, (node) => {
            if (proof.ui.has(node._objectClass)) {
              exclusive = false;
            }
          });
        }
      }
      if (exclusive) {
        found.push(
          preserveControls
            ? { action: started, duration: value(started, 0), tag: value(started, 2).toLowerCase() }
            : { condition: trigger.GetConditions()[0] },
        );
      }
    }
    return found;
  }

  function replaceTimerPatch(patch, enabled) {
    try {
      const descriptor = Object.getOwnPropertyDescriptor(patch.action, '_func');
      if (
        !descriptor?.writable ||
        !('value' in descriptor) ||
        (descriptor.value !== patch.original && descriptor.value !== patch.immediate)
      ) {
        return false;
      }
      const next = enabled ? patch.immediate : patch.original;
      patch.action._func = next;
      return patch.action._func === next;
    } catch (_) {
      return false;
    }
  }

  function replacePatch(patch, block) {
    const condition = patch.condition;
    // Cleanup owns each replacement separately. An external change to one
    // method must not leave our other method installed or get overwritten.
    if (!block) {
      for (const [key, owned, original] of [
        ['Run', patch.blocked, patch.run],
        ['DebugRun', patch.blockedDebug, patch.debug],
      ]) {
        try {
          const descriptor = Object.getOwnPropertyDescriptor(condition, key);
          if (descriptor?.writable && descriptor.value === owned) {
            condition[key] = original;
          }
        } catch (_) {
          /* Preserve independently replaced engine methods. */
        }
      }
    }
    const before = { Run: condition.Run, DebugRun: condition.DebugRun };
    const after = {
      Run: block ? patch.blocked : patch.run,
      DebugRun: block ? patch.blockedDebug : patch.debug,
    };
    try {
      for (const key of ['Run', 'DebugRun']) {
        const descriptor = Object.getOwnPropertyDescriptor(condition, key);
        // These are own, writable data properties on the supported C3 schema.
        if (!descriptor || descriptor.writable !== true || !('value' in descriptor)) {
          return false;
        }
        if (
          condition[key] !== patch[key === 'Run' ? 'run' : 'debug'] &&
          condition[key] !== patch[key === 'Run' ? 'blocked' : 'blockedDebug']
        ) {
          return false;
        }
      }
      condition.Run = after.Run;
      condition.DebugRun = after.DebugRun;
      if (condition.Run === after.Run && condition.DebugRun === after.DebugRun) {
        return true;
      }
    } catch (_) {
      /* A changed engine property must not break loading or navigation. */
    }
    for (const key of ['Run', 'DebugRun']) {
      try {
        condition[key] = before[key];
      } catch (_) {
        /* Best-effort rollback. */
      }
    }
    return false;
  }
  function inspect(engine, finalBoundary = false) {
    if (
      !engine ||
      (typeof engine !== 'object' && typeof engine !== 'function') ||
      (inspected.has(engine) && !finalBoundary)
    ) {
      return;
    }
    try {
      // pageshow can arrive while data.json is still loading. An empty manager
      // is not a completed inspection and must not consume the one-time cache.
      if (engine.GetEventSheetManager?.()?._blocksBySid?.size === 0) {
        return;
      }
      if (!inspected.has(engine)) {
        inspected.add(engine);
        state.inspectedRuntimes++;
      }
      for (const candidate of analyze(engine)) {
        if (candidate.action) {
          const action = candidate.action;
          if (patched.has(action)) {
            continue;
          }
          const original = action._func;
          const patch = {
            action,
            original,
            immediate: function (duration, type, tag, ...args) {
              const matched =
                duration === candidate.duration &&
                type === 0 &&
                typeof tag === 'string' &&
                tag.toLowerCase() === candidate.tag;
              // Zero would be deleted by legacy Tick2 before an earlier sink
              // sees it. A positive epsilon survives until the next tick.
              return original.call(this, matched ? Number.EPSILON : duration, type, tag, ...args);
            },
          };
          if (replaceTimerPatch(patch, active)) {
            timerPatches.push(patch);
            patched.add(action);
          }
          continue;
        }
        const condition = candidate.condition;
        if (
          patched.has(condition) ||
          typeof condition.Run !== 'function' ||
          typeof condition.DebugRun !== 'function'
        ) {
          continue;
        }
        const patch = {
          condition,
          run: condition.Run,
          debug: condition.DebugRun,
          blocked: () => false,
          blockedDebug: function* () {
            yield* [];
            return false;
          },
        };
        if (replacePatch(patch, active)) {
          patches.push(patch);
          patched.add(condition);
        }
      }
    } catch (_) {
      /* Unknown engine revisions keep their original event behavior. */
    }
    refresh();
  }
  state.inspect = inspect;
  function capture(engine) {
    if (!engine || captured.has(engine)) {
      return;
    }
    captured.add(engine);
    if (typeof engine._LoadDataJson === 'function') {
      const original = engine._LoadDataJson;
      engine._LoadDataJson = function (...args) {
        const result = original.apply(this, args);
        if (result && typeof result.then === 'function') {
          return result.then((value) => {
            inspect(this);
            return value;
          });
        }
        inspect(this);
        return result;
      };
    }
    if (typeof engine.Start === 'function') {
      const original = engine.Start;
      engine.Start = function (...args) {
        inspect(this, true);
        return original.apply(this, args);
      };
    }
  }
  const factories = new WeakMap();
  function wrapFactory(factory) {
    if (typeof factory !== 'function') {
      return factory;
    }
    if (factories.has(factory)) {
      return factories.get(factory);
    }
    const wrapped = function (...args) {
      const engine = factory.apply(this, args);
      try {
        capture(engine);
      } catch (_) {
        /* Preserve the game's factory return value. */
      }
      return engine;
    };
    factories.set(factory, wrapped);
    factories.set(wrapped, wrapped);
    return wrapped;
  }
  function watch(name, transform) {
    const descriptor = Object.getOwnPropertyDescriptor(win, name);
    if (
      descriptor &&
      (!descriptor.configurable || descriptor.writable === false || !('value' in descriptor))
    ) {
      return;
    }
    let current = transform(descriptor?.value);
    Object.defineProperty(win, name, {
      configurable: true,
      enumerable: descriptor?.enumerable ?? true,
      get: () => current,
      set(value) {
        current = transform(value);
      },
    });
  }
  watch('C3_CreateRuntime', wrapFactory);
  const registrars = new WeakMap();
  watch('C3_SetInitFunctions', (registrar) => {
    if (typeof registrar !== 'function') {
      return registrar;
    }
    if (registrars.has(registrar)) {
      return registrars.get(registrar);
    }
    const wrapped = function (factory, initializer, ...args) {
      return registrar.call(this, wrapFactory(factory), initializer, ...args);
    };
    registrars.set(registrar, wrapped);
    registrars.set(wrapped, wrapped);
    return wrapped;
  });
  function existingRuntime() {
    try {
      if (win.c3_runtimeInterface?.UsesWorker?.()) {
        state.workerRuntime = true;
        refresh();
        return;
      }
      inspect(win.c3_runtimeInterface?._GetLocalRuntime?.());
    } catch (_) {
      /* Worker/private DOM interfaces have no raw getter. */
    }
  }
  existingRuntime();
  win.addEventListener('pagehide', () => {
    active = false;
    for (const patch of patches) {
      replacePatch(patch, false);
    }
    for (const patch of timerPatches) {
      replaceTimerPatch(patch, false);
    }
    refresh();
  });
  win.addEventListener('pageshow', () => {
    active = true;
    for (const patch of patches) {
      replacePatch(patch, true);
    }
    for (const patch of timerPatches) {
      replaceTimerPatch(patch, true);
    }
    refresh();
    existingRuntime();
  });
})(typeof window === 'undefined' ? globalThis : window);
