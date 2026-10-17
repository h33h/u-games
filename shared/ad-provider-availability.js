(function installAdProviderAvailability(win) {
  'use strict';
  if (win.__UGamesAdProviders?.version === 1) {
    return;
  }
  const state = { version: 1, status: 'waiting', protected: 0 };
  try {
    Object.defineProperty(win, '__UGamesAdProviders', { value: state });
  } catch (_) {
    return;
  }
  const providers = new WeakMap();
  const watched = new WeakMap();
  const protectedConfigurations = new WeakSet();

  function isRecord(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value);
  }

  function playgamaShape(bridge) {
    if (
      !isRecord(bridge) ||
      typeof bridge.initialize !== 'function' ||
      typeof bridge.isInitialized !== 'boolean' ||
      bridge.MODULE_NAME?.ADVERTISEMENT !== 'advertisement' ||
      bridge.EVENT_NAME?.INTERSTITIAL_STATE_CHANGED !== 'interstitial_state_changed' ||
      bridge.EVENT_NAME?.REWARDED_STATE_CHANGED !== 'rewarded_state_changed'
    ) {
      return false;
    }
    // PlaygamaBridge publishes these constants on its prototype before init.
    // Its advertisement getter logs SDK_NOT_INITIALIZED and returns undefined
    // until initialize populates the module registry, so do not probe it here.
    // Constant values: Playgama/bridge src/constants/{moduleName,eventName}.ts.
    if (bridge.version !== undefined) {
      return typeof bridge.version === 'string' && /^2(?:\.|$)/.test(bridge.version);
    }
    return bridge.isInitialized;
  }

  function writable(object, key) {
    const descriptor = Object.getOwnPropertyDescriptor(object, key);
    return descriptor ? 'value' in descriptor && descriptor.writable : Object.isExtensible(object);
  }

  function protectConfiguration(bridge) {
    try {
      if (
        !playgamaShape(bridge) ||
        !bridge.isInitialized ||
        typeof bridge.advertisement?.showInterstitial !== 'function'
      ) {
        return;
      }
      const interstitial = bridge.options?.advertisement?.interstitial;
      if (!isRecord(interstitial)) {
        return;
      }
      const disabled = interstitial.disable === true;
      const noAutoShow = Array.isArray(interstitial.autoShow) && interstitial.autoShow.length === 0;
      if (
        (!disabled && !writable(interstitial, 'disable')) ||
        (!noAutoShow && !writable(interstitial, 'autoShow'))
      ) {
        state.status = 'unsupported';
        return;
      }
      // Playgama reads these documented settings from the resolved options.
      // Keep every provider method and its native lifecycle unchanged.
      if (!disabled) {
        interstitial.disable = true;
      }
      if (!noAutoShow) {
        interstitial.autoShow = [];
      }
      if (!protectedConfigurations.has(interstitial)) {
        protectedConfigurations.add(interstitial);
        state.protected++;
      }
      state.status = 'protected';
    } catch (_) {
      // Unsupported SDK revisions and immutable configuration fail open.
    }
  }

  function observeProperty(object, key, transform) {
    try {
      let properties = watched.get(object);
      if (!properties) {
        properties = new Map();
        watched.set(object, properties);
      }
      const descriptor = Object.getOwnPropertyDescriptor(object, key);
      const previous = properties.get(key);
      if (previous && descriptor?.get === previous.get) {
        previous.refresh();
        return;
      }
      if (
        descriptor &&
        (!descriptor.configurable || !('value' in descriptor) || !descriptor.writable)
      ) {
        const current = object[key];
        const replacement = transform(current);
        if ('value' in descriptor && descriptor.writable && replacement !== current) {
          object[key] = replacement;
        }
        return;
      }
      let current = object[key];
      const get = () => current;
      const refresh = () => {
        current = transform(current);
      };
      Object.defineProperty(object, key, {
        configurable: true,
        enumerable: descriptor?.enumerable ?? true,
        get,
        set(value) {
          current = transform(value);
        },
      });
      properties.set(key, { get, refresh });
      refresh();
    } catch (_) {
      // A readonly publication must keep the provider's own behavior.
    }
  }

  function protectBridge(bridge) {
    try {
      if (!playgamaShape(bridge)) {
        return bridge;
      }
      let wrappers = providers.get(bridge);
      if (!wrappers) {
        wrappers = new WeakMap();
        providers.set(bridge, wrappers);
      }
      observeProperty(bridge, 'initialize', (initialize) => {
        if (typeof initialize !== 'function') {
          return initialize;
        }
        if (wrappers.has(initialize)) {
          return wrappers.get(initialize);
        }
        const wrapper = function () {
          const result = initialize.apply(this, arguments);
          try {
            if (result && typeof result.then === 'function') {
              // Register before the game can attach .then, while returning the
              // original Promise and preserving its value and rejection.
              result.then(
                () => protectConfiguration(bridge),
                () => {},
              );
            } else {
              protectConfiguration(bridge);
            }
          } catch (_) {}
          return result;
        };
        wrappers.set(initialize, wrapper);
        wrappers.set(wrapper, wrapper);
        return wrapper;
      });
      protectConfiguration(bridge);
    } catch (_) {}
    return bridge;
  }

  observeProperty(win, 'bridge', protectBridge);
})(window);
