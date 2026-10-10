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
