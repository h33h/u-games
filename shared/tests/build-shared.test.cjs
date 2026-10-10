'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const { spawnSync } = require('node:child_process');
const script = path.join(__dirname, '../../scripts/build-shared.cjs');

test('build produces identical executable scripts and valid native content rules', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ugames-build-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  fs.mkdirSync(path.join(root, 'shared'));
  fs.writeFileSync(path.join(root, 'shared/ad-adapter.js'), 'window.executedRules = window.__UGamesRules.version;');
  fs.writeFileSync(path.join(root, 'shared/ad-rules.json'), JSON.stringify({ version: 1, blockedHosts: ['an.yandex.ru'], blockedUrlPatterns: [], hiddenSelectors: [] }));
  const run = spawnSync(process.execPath, [script, root], { encoding: 'utf8' });
  assert.equal(run.status, 0, run.stderr);
  const android = fs.readFileSync(path.join(root, 'android/app/src/main/assets/ugames/ad-adapter.js'), 'utf8');
  const ios = fs.readFileSync(path.join(root, 'ios/UGames/Resources/ad-adapter.js'), 'utf8');
  assert.equal(android, ios);
  const ctx = vm.createContext({ window: {} });
  vm.runInContext(ios, ctx);
  assert.equal(ctx.window.executedRules, 1);
  const content = JSON.parse(fs.readFileSync(path.join(root, 'ios/UGames/Resources/content-rules.json'), 'utf8'));
  assert.equal(content[0].action.type, 'block');
  assert.equal(new RegExp(content[0].trigger['url-filter']).test('https://an.yandex.ru/ad'), true);
  const first = android;
  assert.equal(spawnSync(process.execPath, [script, root]).status, 0);
  assert.equal(fs.readFileSync(path.join(root, 'ios/UGames/Resources/ad-adapter.js'), 'utf8'), first);
});

test('missing shared source fails packaging instead of silently generating empty protection', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ugames-missing-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const run = spawnSync(process.execPath, [script, root], { encoding: 'utf8' });
  assert.notEqual(run.status, 0);
});
