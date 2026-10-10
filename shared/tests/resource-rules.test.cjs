'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const modulePath = path.join(__dirname, '../../scripts/build-shared.cjs');
const compiler = () => fs.existsSync(modulePath) ? require(modulePath) : { compileContentRules: () => [], validateRules() {} };
const rules = {
  version: 1,
  blockedHosts: ['an.yandex.ru'],
  blockedUrlPatterns: ['^https?://yandex\\.ru/ads/', '^https?://yastatic\\.net/safeframe-bundles/'],
  hiddenSelectors: ['.sticky-banner-container'],
};
for (const [url, wanted] of [
  ['https://an.yandex.ru/mapuid/test', true],
  ['https://child.an.yandex.ru/resource', true],
  ['https://yandex.ru/ads/system/context.js', true],
  ['https://yastatic.net/safeframe-bundles/0.89/render.html', true],
  ['https://an.yandex.ru.evil.test/mapuid/test', false],
  ['https://not-an.yandex.ru/resource', false],
  ['https://app-263344.cdn.games.yandex.net/game.js', false],
  ['https://yandex.ru/games/', false],
  ['https://passport.yandex.ru/auth?retpath=https://an.yandex.ru/', false],
  ['https://yastatic.net/s3/games-static/sdk.js', false],
]) {
  test('compiled WebKit filter decision: ' + url, () => {
    const compiled = compiler().compileContentRules(rules);
    const blocked = compiled.some(rule => rule.action.type === 'block' && new RegExp(rule.trigger['url-filter'], 'i').test(url));
    assert.equal(blocked, wanted);
  });
}
test('invalid host and regex are rejected before packaging', () => {
  assert.throws(() => compiler().validateRules({ ...rules, blockedHosts: ['yandex.ru/ads'] }));
  assert.throws(() => compiler().validateRules({ ...rules, blockedUrlPatterns: ['['] }));
});
test('WebKit-incompatible regex disjunction is rejected before app startup', () => {
  assert.throws(() => compiler().validateRules({ ...rules, blockedUrlPatterns: ['^https?://example\\.test/ad(a|b)'] }));
});
