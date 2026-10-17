(function installPortalTheme(win) {
  'use strict';
  const doc = win.document;
  const branding = win.__UGamesBranding;
  if (
    !doc ||
    !branding ||
    win.__UGamesCachedCatalog?.version === 1 ||
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
  const illustrationSelector =
    '.footer__image,[class*="authorization"][class*="image"], [class*="auth-banner"][class*="image"], [class*="sticky-promo-banner"][class*="image"], [class*="stripe-"][class*="image--"], [class*="stripe-"][class*="Image--"]';
  function artworkForURL(source) {
    let url;
    try {
      url = new win.URL(source, doc.baseURI);
    } catch (_) {
      return null;
    }
    if (url.hostname === 'avatars.mds.yandex.net' && /^\/get-yapic\/0\/0-0\//.test(url.pathname)) {
      return 'avatar';
    }
    const staticAsset =
      (url.hostname === 'yastatic.net' && url.pathname.startsWith('/s3/games-static/')) ||
      (/^(?:www\.)?yandex\.(?:ru|com)$/.test(url.hostname) &&
        /^\/games\/(?:[^/]+\/)*cdn\/games-static\//.test(url.pathname));
    if (!staticAsset) {
      return null;
    }
    if (/\/favicons\/yandex\//.test(url.pathname)) {
      return 'icon';
    }
    if (/\/images\/(?:single-logo\/(?:games|yandex)\/|logo\/v\d+\/yandex\/)/.test(url.pathname)) {
      return 'logo';
    }
    if (/\/images\/background\/background-dark-purple\.(?:jpg|webp|avif)$/.test(url.pathname)) {
      return 'background';
    }
    const shortcut = /\/images\/shop\/shortcuts\/([a-z-]+)(?:@2x)?\.(?:png|webp|avif|svg)$/.exec(
      url.pathname,
    );
    if (shortcut) {
      return 'shop-' + shortcut[1];
    }
    if (/\/images\/art\/purple_close(?:@2x)?\.(?:png|webp|avif)$/.test(url.pathname)) {
      return 'controller';
    }
    return null;
  }
  function replacementFor(artwork) {
    return branding.assets[artwork] || branding.assets.icon;
  }
  function artworkFor(element, source) {
    const candidates = [source, element.getAttribute('srcset') || ''];
    for (const node of element.closest('picture')?.querySelectorAll('source') || []) {
      candidates.push(node.getAttribute('srcset') || '');
    }
    for (const candidate of candidates) {
      // Provider responsive sources are ordinary CDN URLs; do not split bundled data URLs.
      const values =
        candidate.match(/(?:https?:)?\/\/[^\s,]+/g) ||
        candidate.split(',').map((value) => value.trim().split(/\s+/)[0]);
      for (const value of values) {
        const artwork = artworkForURL(value);
        if (artwork) {
          return artwork;
        }
      }
    }
    if (element.matches(illustrationSelector)) {
      return element.matches('.footer__image') ? 'developer' : 'controller';
    }
    return null;
  }
  function replaceInlineArtwork(element) {
    for (const property of ['background-image', 'mask-image']) {
      const original = element.style.getPropertyValue(property);
      if (!original.includes('url(')) {
        continue;
      }
      const replacement = original.replace(
        /url\(\s*(?:"([^"]*)"|'([^']*)'|([^)]*))\s*\)/g,
        (match, double, single, unquoted) => {
          const artwork = artworkForURL((double ?? single ?? unquoted).trim());
          return artwork ? 'url("' + replacementFor(artwork) + '")' : match;
        },
      );
      if (replacement !== original) {
        // Replacing just the URL preserves the portal's gradients and layer ordering.
        element.style.setProperty(property, replacement, 'important');
      }
    }
  }
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
    if (element.tagName === 'IMG' || element.localName === 'image') {
      const attribute = element.tagName === 'IMG' ? 'src' : 'href';
      const source = element.getAttribute(attribute) || element.getAttribute('xlink:href') || '';
      const previous = themedImages.get(element);
      const responsive =
        element.getAttribute('srcset') ||
        element.closest('picture')?.querySelector('source[srcset]:not([srcset=""])');
      if (!previous || source !== previous.replacement || responsive) {
        delete element.dataset.ugamesImageFallback;
        const artwork = artworkFor(element, source);
        if (artwork) {
          themedImages.set(element, {
            replacement: replacementFor(artwork),
          });
        } else {
          // Virtualized profile slots can be reused for a real player avatar.
          themedImages.delete(element);
        }
      }
      const replacement = themedImages.get(element)?.replacement;
      if (replacement) {
        if (element.getAttribute(attribute) !== replacement) {
          element.setAttribute(attribute, replacement);
        }
        if (element.localName === 'image' && element.hasAttribute('xlink:href')) {
          element.removeAttribute('xlink:href');
        }
        element.removeAttribute('srcset');
        for (const source of element.closest('picture')?.querySelectorAll('source') || []) {
          source.removeAttribute('srcset');
        }
      }
    }
    replaceInlineArtwork(element);
    if (element.tagName === 'SOURCE') {
      const image = element.closest('picture')?.querySelector('img');
      if (image) {
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
    root.addEventListener(
      'error',
      (event) => {
        const image = event.target;
        if (image?.tagName !== 'IMG' || themedImages.get(image)?.fallback) {
          return;
        }
        const avatar = image.matches('[class*="avatar" i],[class*="user-account-pic"]');
        themedImages.set(image, {
          replacement: replacementFor(avatar ? 'avatar' : 'cover-placeholder'),
          fallback: true,
        });
        // Clear failed responsive sources before the browser retries the local fallback.
        image.removeAttribute('srcset');
        for (const node of image.closest('picture')?.querySelectorAll('source') || []) {
          node.removeAttribute('srcset');
        }
        image.dataset.ugamesImageFallback = '';
        image.setAttribute('src', themedImages.get(image).replacement);
        inspect(image);
      },
      true,
    );
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
        'xlink:href',
        'rel',
        'as',
        'id',
        'class',
        'style',
        'data-ugames-artwork',
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
  for (const method of ['pushState', 'replaceState']) {
    const original = win.history[method];
    win.history[method] = function () {
      const result = original.apply(this, arguments);
      ensureStyle(doc);
      return result;
    };
  }
  win.addEventListener('popstate', () => ensureStyle(doc));
  win.addEventListener('pageshow', () => ensureStyle(doc));
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
