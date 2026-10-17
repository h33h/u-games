'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const { spawnSync } = require('node:child_process');
const script = path.join(__dirname, '../../scripts/build-shared.cjs');
function addGameScripts(root) {
  fs.writeFileSync(path.join(root, 'shared/offline-games.js'), 'window.offlineReady = true;');
  fs.writeFileSync(
    path.join(root, 'shared/ad-provider-availability.js'),
    'window.providersReady = window.executedRules;',
  );
  fs.writeFileSync(
    path.join(root, 'shared/construct-ad-guard.js'),
    'window.constructReady = window.providersReady;',
  );
  fs.writeFileSync(
    path.join(root, 'shared/ad-countdowns.js'),
    'window.countdownsReady = window.constructReady;',
  );
}

test('build produces identical executable scripts and valid native content rules', (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ugames-build-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  fs.mkdirSync(path.join(root, 'shared'));
  addGameScripts(root);
  fs.writeFileSync(
    path.join(root, 'shared/ad-adapter.js'),
    'window.executedRules = window.__UGamesRules.version;',
  );
  fs.writeFileSync(
    path.join(root, 'shared/ad-rules.json'),
    JSON.stringify({
      version: 1,
      blockedHosts: ['an.yandex.ru'],
      blockedUrlPatterns: [],
      hiddenSelectors: [],
    }),
  );
  const run = spawnSync(process.execPath, [script, root], { encoding: 'utf8' });
  assert.equal(run.status, 0, run.stderr);
  const android = fs.readFileSync(
    path.join(root, 'android/app/src/main/assets/ugames/ad-adapter.js'),
    'utf8',
  );
  const ios = fs.readFileSync(path.join(root, 'ios/UGames/Resources/ad-adapter.js'), 'utf8');
  assert.equal(android, ios);
  const ctx = vm.createContext({ window: {} });
  vm.runInContext(ios, ctx);
  assert.equal(ctx.window.executedRules, 1);
  assert.equal(ctx.window.offlineReady, true);
  assert.equal(ctx.window.providersReady, 1);
  assert.equal(ctx.window.constructReady, 1);
  assert.equal(ctx.window.countdownsReady, 1);
  const content = JSON.parse(
    fs.readFileSync(path.join(root, 'ios/UGames/Resources/content-rules.json'), 'utf8'),
  );
  assert.equal(content[0].action.type, 'block');
  assert.equal(new RegExp(content[0].trigger['url-filter']).test('https://an.yandex.ru/ad'), true);
  const first = android;
  assert.equal(spawnSync(process.execPath, [script, root]).status, 0);
  assert.equal(
    fs.readFileSync(path.join(root, 'ios/UGames/Resources/ad-adapter.js'), 'utf8'),
    first,
  );
});

test('missing shared source fails packaging instead of silently generating empty protection', (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ugames-missing-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const run = spawnSync(process.execPath, [script, root], { encoding: 'utf8' });
  assert.notEqual(run.status, 0);
});

test('packaging embeds artwork and CSS as local data URLs and rejects missing artwork', (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ugames-brand-build-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  fs.mkdirSync(path.join(root, 'shared'));
  addGameScripts(root);
  fs.writeFileSync(
    path.join(root, 'shared/ad-adapter.js'),
    'window.logo = window.__UGamesBranding?.assets.logo;',
  );
  fs.writeFileSync(path.join(root, 'shared/portal-theme.js'), 'window.themeExecuted = true;');
  fs.writeFileSync(
    path.join(root, 'shared/portal-theme.css'),
    'body {background-image:url("{{logo}}")}',
  );
  fs.writeFileSync(path.join(root, 'shared/branding.json'), JSON.stringify({ logo: 'logo.svg' }));
  fs.writeFileSync(
    path.join(root, 'shared/logo.svg'),
    '<svg xmlns="http://www.w3.org/2000/svg"><text>UGames</text></svg>',
  );
  fs.writeFileSync(
    path.join(root, 'shared/ad-rules.json'),
    JSON.stringify({ version: 1, blockedHosts: [], blockedUrlPatterns: [], hiddenSelectors: [] }),
  );
  let run = spawnSync(process.execPath, [script, root], { encoding: 'utf8' });
  assert.equal(run.status, 0, run.stderr);
  const ctx = vm.createContext({ window: {} });
  vm.runInContext(
    fs.readFileSync(path.join(root, 'ios/UGames/Resources/ad-adapter.js'), 'utf8'),
    ctx,
  );
  assert.match(ctx.window.logo, /^data:image\/svg\+xml;base64,/);
  assert.match(Buffer.from(ctx.window.logo.split(',')[1], 'base64').toString(), /UGames/);
  assert.equal(ctx.window.themeExecuted, true);
  assert.ok(ctx.window.__UGamesBranding.css.includes(ctx.window.logo));
  fs.unlinkSync(path.join(root, 'shared/logo.svg'));
  run = spawnSync(process.execPath, [script, root], { encoding: 'utf8' });
  assert.notEqual(run.status, 0);
});
