(function installOfflineCatalog(win) {
  'use strict';
  if (win.__UGamesCachedCatalog?.version !== 1 || win.__UGamesOfflineCatalog) {
    return;
  }
  const doc = win.document;
  const branding = win.__UGamesBranding;
  const placeholder = branding?.assets?.['cover-placeholder'];

  function gameURL(raw) {
    try {
      const url = new win.URL(raw);
      return url.protocol === 'https:' &&
        !url.username &&
        !url.password &&
        !url.port &&
        /\.(?:games\.yandex\.net|games\.s3\.yandex\.net)$/.test(url.hostname)
        ? url
        : null;
    } catch (_) {
      return null;
    }
  }
  function localCover(raw) {
    try {
      const url = new win.URL(raw);
      if (
        url.username ||
        url.password ||
        url.port ||
        url.search ||
        url.hash ||
        url.hostname !== 'yandex.ru'
      ) {
        return null;
      }
      return (url.protocol === 'https:' &&
        /^\/games\/\.ugames-cache-cover\/[a-f0-9]{64}$/.test(url.pathname)) ||
        (url.protocol === 'ugames-offline:' &&
          /^\/games\/_covers\/[a-f0-9]{64}$/.test(url.pathname))
        ? url.href
        : null;
    } catch (_) {
      return null;
    }
  }
  function element(tag, className, text) {
    const node = doc.createElement(tag);
    if (className) {
      node.className = className;
    }
    if (text !== undefined) {
      node.textContent = text;
    }
    return node;
  }
  function render() {
    if (!doc.body) {
      return;
    }
    doc.documentElement.lang = 'ru';
    doc.documentElement.setAttribute('data-ugames-theme', 'dark');
    doc.documentElement.setAttribute('data-ugames-page', 'catalog');
    doc.documentElement.setAttribute('data-ugames-cached-catalog', '');
    doc.title = 'UGames';
    if (!doc.querySelector('style[data-ugames-cached-catalog-style]')) {
      const style = element('style');
      style.setAttribute('data-ugames-cached-catalog-style', '');
      style.textContent = branding?.css || '';
      (doc.head || doc.documentElement).appendChild(style);
    }
    const header = element('header', 'ugames-cached-header');
    const home = element('a', 'ugames-cached-home');
    home.href = 'https://yandex.ru/games/';
    if (branding?.assets?.logo) {
      const logo = element('img');
      logo.src = branding.assets.logo;
      logo.alt = 'UGames';
      logo.width = 140;
      logo.height = 32;
      home.appendChild(logo);
    } else {
      home.textContent = 'UGames';
    }
    header.appendChild(home);
    const main = element('main', 'ugames-cached-main');
    main.appendChild(element('h1', '', 'Игры'));
    const grid = element('ul', 'ugames-cached-grid');
    grid.setAttribute('aria-label', 'Игры');
    const seen = new Set();
    const games = win.__UGamesCachedCatalog?.games;
    for (const game of Array.isArray(games) ? games : []) {
      const url = gameURL(game?.url);
      if (!url) {
        continue;
      }
      const identity = url.hostname.match(/^app-(\d+)\./)?.[1] || url.href;
      if (seen.has(identity)) {
        continue;
      }
      seen.add(identity);
      const rawTitle = typeof game.title === 'string' ? game.title : '';
      const title =
        (win.__UGamesOfflineRuntime?.cleanTitle?.(rawTitle) ?? rawTitle.trim()).slice(0, 200) ||
        'Игра';
      const card = element('li', 'game-card');
      const link = element('a', 'game-card__link');
      link.href = url.href;
      link.title = title;
      const graphic = element('div', 'game-card__graphic');
      const image = element('img', 'game-card__image');
      image.alt = '';
      image.loading = 'lazy';
      image.decoding = 'async';
      const cover = localCover(game.cover);
      if (cover || placeholder) {
        image.src = cover || placeholder;
      }
      if (!cover) {
        image.setAttribute('data-ugames-image-fallback', '');
      }
      image.onerror = () => {
        image.onerror = null;
        image.setAttribute('data-ugames-image-fallback', '');
        if (placeholder) {
          image.src = placeholder;
        }
      };
      graphic.appendChild(image);
      link.appendChild(graphic);
      const info = element('div', 'ugames-cached-caption');
      info.appendChild(element('h2', 'game-card__title', title));
      link.appendChild(info);
      card.appendChild(link);
      grid.appendChild(card);
    }
    if (grid.childElementCount) {
      main.appendChild(grid);
    } else {
      const empty = element(
        'p',
        'ugames-cached-empty',
        'В кэше пока нет игр. Открой игры с интернетом, чтобы они появились здесь.',
      );
      empty.setAttribute('role', 'status');
      main.appendChild(empty);
    }
    doc.body.replaceChildren(header, main);
  }
  Object.defineProperty(win, '__UGamesOfflineCatalog', { value: { version: 1, render } });
  if (doc.readyState === 'loading' || !doc.body) {
    doc.addEventListener('DOMContentLoaded', render, { once: true });
  } else {
    render();
  }
})(window);
