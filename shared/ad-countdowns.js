(function installAdCountdowns(win) {
  'use strict';
  if (win.__UGamesCountdowns?.version === 1) {
    return;
  }
  const state = { version: 1, hidden: 0 };
  Object.defineProperty(win, '__UGamesCountdowns', { value: state });
  let active = true;
  const cleanups = [];
  const resumes = [];
  const doc = win.document;
  if (doc && typeof win.MutationObserver === 'function') {
    const markers = [
      '[data-ad-countdown]',
      '[data-ad-timer]',
      '[data-testid="ad-countdown"]',
      '[data-testid="advertisement-countdown"]',
      '#ad-countdown',
      '#ads-countdown',
      '.ad-countdown',
      '.ads-countdown',
      '.advertisement-countdown',
      '.ad-timer',
      '.ads-timer',
    ].join(',');
    const controls =
      'canvas,iframe,video,a,button,input,select,textarea,[role="button"],[contenteditable]';
    const labels = 'div,span,p,aside,output,label';
    // Whole-label matches only: a bare "3 сек" or a gameplay timer is insufficient.
    const adText =
      /^(?:реклама\s+(?:(?:начн[её]тся|начинается)\s+)?через|рекламная\s+пауза\s+через|(?:ad(?:vertisement)?|ad\s+break)\s+(?:(?:starts?|begins?)\s+)?in)[\s.:…-]*\d{1,2}(?:\s*(?:сек(?:\.|унд[уы]?)?|с\.|s(?:ec(?:ond)?s?)?\.?))?[\s.!…]*$/iu;
    const saved = new WeakMap();
    const roots = new WeakSet();

    function update(element) {
      if (!active || !element?.matches || !element.matches(labels)) {
        return;
      }
      const text = (element.textContent || '').replace(/\s+/g, ' ').trim();
      const isCountdown =
        !element.closest(controls) &&
        !element.querySelector(controls) &&
        (element.matches(markers) ||
          (text.length <= 100 && element.querySelectorAll('*').length <= 6 && adText.test(text)));
      if (isCountdown) {
        if (!saved.has(element)) {
          saved.set(element, [
            element.style.getPropertyValue('display'),
            element.style.getPropertyPriority('display'),
          ]);
          state.hidden++;
        }
        if (
          element.style.getPropertyValue('display') !== 'none' ||
          element.style.getPropertyPriority('display') !== 'important'
        ) {
          element.style.setProperty('display', 'none', 'important');
        }
      } else if (saved.has(element)) {
        const [display, priority] = saved.get(element);
        saved.delete(element);
        if (display) {
          element.style.setProperty('display', display, priority);
        } else {
          element.style.removeProperty('display');
        }
      }
    }

    function scan(root) {
      update(root);
      if (!root.querySelectorAll) {
        return;
      }
      for (const element of root.querySelectorAll('*')) {
        update(element);
        if (element.shadowRoot) {
          observe(element.shadowRoot);
        }
      }
      if (root.shadowRoot) {
        observe(root.shadowRoot);
      }
    }

    function observe(root) {
      if (!active || roots.has(root)) {
        return;
      }
      roots.add(root);
      scan(root);
      const observer = new win.MutationObserver((changes) => {
        for (const change of changes) {
          const element =
            change.target.nodeType === 1 ? change.target : change.target.parentElement;
          update(element);
          update(element?.parentElement);
          if (change.type === 'childList') {
            for (const node of change.addedNodes) {
              scan(node);
            }
          }
        }
      });
      const options = {
        childList: true,
        characterData: true,
        subtree: true,
        attributes: true,
        attributeFilter: [
          'class',
          'id',
          'style',
          'data-ad-countdown',
          'data-ad-timer',
          'data-testid',
        ],
      };
      observer.observe(root, options);
      cleanups.push(() => observer.disconnect());
      resumes.push(() => {
        scan(root);
        observer.observe(root, options);
      });
    }

    observe(doc);
    if (typeof win.Element?.prototype.attachShadow === 'function') {
      const original = win.Element.prototype.attachShadow;
      win.Element.prototype.attachShadow = function (options) {
        const root = original.call(this, options);
        observe(root);
        return root;
      };
    }
  }

  win.addEventListener?.('pagehide', () => {
    active = false;
    for (const cleanup of cleanups) {
      cleanup();
    }
  });
  win.addEventListener?.('pageshow', () => {
    if (!active) {
      active = true;
      for (const resume of resumes) {
        resume();
      }
    }
  });
})(window);
