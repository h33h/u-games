(function installPortalTheme(win) {
  'use strict';
  const doc = win.document;
  const branding = win.__UGamesBranding;
  if (
    !doc ||
    !branding ||
    !/^(?:www\.)?yandex\.(?:ru|com)$/.test(win.location.hostname) ||
    !/^\/games(?:\/|$)/.test(win.location.pathname) ||
    win.__UGamesPortalTheme
  ) {
    return;
  }
  win.__UGamesPortalTheme = true;
  const roots = new WeakSet();
  const styleId = 'ugames-portal-theme';
  const themedImages = new WeakMap();
  function ensureStyle(root) {
    if (!win.document) {
      return;
    }
    const shadow = root !== doc;
    const parent = shadow ? root : doc.head || doc.documentElement;
    if (!parent) {
      return;
    }
    let style = root.querySelector('#' + styleId);
    if (!style) {
      style = doc.createElement('style');
      style.id = styleId;
      parent.appendChild(style);
    }
    const css = shadow ? branding.css.replaceAll('[data-ugames-theme]', ':host') : branding.css;
    if (style.textContent !== css) {
      style.textContent = css;
    }
    if (doc.documentElement) {
      if (doc.documentElement.dataset.ugamesTheme !== 'violet-mint') {
        doc.documentElement.dataset.ugamesTheme = 'violet-mint';
      }
      const page = /^\/games\/app(?:\/|$)/.test(win.location.pathname) ? 'game' : 'catalog';
      if (doc.documentElement.dataset.ugamesPage !== page) {
        doc.documentElement.dataset.ugamesPage = page;
      }
    }
  }
  function inspect(element) {
    if (!element || element.nodeType !== 1) {
      return;
    }
    if (element.tagName === 'IMG') {
      const match =
        /^https:\/\/yastatic\.net\/s3\/games-static\/static-data\/images\/shop\/shortcuts\/([a-z-]+)\.png(?:[?].*)?$/.exec(
          element.src,
        );
      if (match) {
        themedImages.set(element, branding.assets['shop-' + match[1]] || branding.assets.icon);
      }
      const replacement = themedImages.get(element);
      if (replacement) {
        if (element.getAttribute('src') !== replacement) {
          element.setAttribute('src', replacement);
        }
        element.removeAttribute('srcset');
        for (const source of element.closest('picture')?.querySelectorAll('source') || []) {
          source.removeAttribute('srcset');
        }
      }
    }
    if (element.tagName === 'SOURCE') {
      const image = element.closest('picture')?.querySelector('img');
      if (image && themedImages.has(image)) {
        inspect(image);
      }
    }
    // Portal font preloads are unnecessary once the local system typeface is active.
    if (
      element.matches('link[rel="preload"][as="font"]') &&
      /\/home\/fonts\/ys\//.test(element.href)
    ) {
      element.remove();
    }
    if (element.shadowRoot) {
      observe(element.shadowRoot);
    }
  }
  function scan(node) {
    inspect(node);
    if (node.querySelectorAll) {
      for (const element of node.querySelectorAll('*')) {
        inspect(element);
      }
    }
  }
  function observe(root) {
    if (roots.has(root)) {
      return;
    }
    roots.add(root);
    const observer = new win.MutationObserver((changes) => {
      ensureStyle(root);
      for (const change of changes) {
        if (change.type === 'childList') {
          for (const node of change.addedNodes) {
            scan(node);
          }
        } else {
          inspect(change.target);
        }
      }
    });
    observer.observe(root, {
      subtree: true,
      childList: true,
      characterData: true,
      attributes: true,
      attributeFilter: [
        'data-ugames-theme',
        'data-ugames-page',
        'src',
        'srcset',
        'href',
        'rel',
        'as',
        'id',
      ],
    });
    ensureStyle(root);
    scan(root);
  }
  observe(doc);
  const attachShadow = win.Element.prototype.attachShadow;
  win.Element.prototype.attachShadow = function (options) {
    const root = attachShadow.call(this, options);
    observe(root);
    return root;
  };
})(window);

(function followPageBackground(win) {
  'use strict';
  const doc = win.document;
  if (!doc || win !== win.top || win.__UGamesPageBackground) {
    return;
  }
  win.__UGamesPageBackground = true;
  let pending = false;
  let previous;
  function report() {
    pending = false;
    if (!doc.documentElement || !doc.body) {
      return;
    }
    const root = win.getComputedStyle(doc.documentElement);
    const dark =
      root.colorScheme === 'dark' ||
      (root.colorScheme.includes('dark') &&
        win.matchMedia?.('(prefers-color-scheme: dark)').matches);
    let rgb = dark ? [18, 18, 18] : [255, 255, 255];
    for (const element of [doc.documentElement, doc.body]) {
      const color = win.getComputedStyle(element).backgroundColor;
      const channels = /^rgba?\(([^)]+)\)$/
        .exec(color)?.[1]
        .split(/[, /]+/)
        .map(Number);
      if (!channels || channels.length < 3 || channels.some((value) => !Number.isFinite(value))) {
        continue;
      }
      const alpha = channels[3] ?? 1;
      rgb = rgb.map((base, index) => Math.round(channels[index] * alpha + base * (1 - alpha)));
    }
    const color = '#' + rgb.map((channel) => channel.toString(16).padStart(2, '0')).join('');
    if (color !== previous) {
      previous = color;
      win.__UGamesAppearance?.postMessage(color);
      win.webkit?.messageHandlers?.ugamesAppearance?.postMessage(color);
    }
  }
  function schedule() {
    if (!pending) {
      pending = true;
      win.setTimeout(report, 0);
    }
  }
  new win.MutationObserver(schedule).observe(doc, {
    subtree: true,
    childList: true,
    characterData: true,
    attributes: true,
    attributeFilter: ['class', 'style', 'data-theme', 'data-ugames-page', 'media', 'href'],
  });
  doc.addEventListener('DOMContentLoaded', schedule);
  doc.addEventListener('load', schedule, true);
  doc.addEventListener('transitionend', schedule, true);
  doc.addEventListener('animationend', schedule, true);
  win.addEventListener('pageshow', schedule);
  win.addEventListener('resize', schedule);
  win.matchMedia?.('(prefers-color-scheme: dark)').addEventListener('change', schedule);
  schedule();
})(window);
