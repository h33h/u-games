'use strict';
const fs = require('node:fs');
const path = require('node:path');

function validateRules(rules) {
  if (rules.version !== 1) {
    throw new Error('Unsupported rules version');
  }
  for (const key of ['blockedHosts', 'blockedUrlPatterns', 'hiddenSelectors']) {
    if (
      !Array.isArray(rules[key]) ||
      rules[key].some((value) => typeof value !== 'string' || !value)
    ) {
      throw new Error('Invalid rule collection: ' + key);
    }
  }
  for (const host of rules.blockedHosts) {
    if (!/^[a-z0-9-]+(?:\.[a-z0-9-]+)+$/.test(host)) {
      throw new Error('Invalid blocked hostname');
    }
  }
  for (const pattern of rules.blockedUrlPatterns) {
    if (!pattern.startsWith('^https?://')) {
      throw new Error('Resource patterns must anchor scheme and hostname');
    }
    if (pattern.includes('|')) {
      throw new Error('WebKit does not support regex disjunction; use separate rules');
    }
    new RegExp(pattern);
  }
}

function compileContentRules(rules) {
  validateRules(rules);
  const patterns = rules.blockedHosts
    .map((host) => '^https?://([a-z0-9-]+\\.)*' + host.replaceAll('.', '\\.') + '(:[0-9]+)?/')
    .concat(rules.blockedUrlPatterns);
  const result = patterns.map((pattern) => ({
    trigger: { 'url-filter': pattern, 'url-filter-is-case-sensitive': false },
    action: { type: 'block' },
  }));
  if (rules.hiddenSelectors.length) {
    result.push({
      trigger: { 'url-filter': '.*' },
      action: { type: 'css-display-none', selector: rules.hiddenSelectors.join(',') },
    });
  }
  return result;
}

function buildShared(rootDir) {
  const adapter = fs.readFileSync(path.join(rootDir, 'shared/ad-adapter.js'), 'utf8');
  if (!adapter.trim()) {
    throw new Error('Missing adapter code');
  }
  const rules = JSON.parse(fs.readFileSync(path.join(rootDir, 'shared/ad-rules.json'), 'utf8'));
  const contentRules = compileContentRules(rules);
  const script = 'window.__UGamesRules = Object.freeze(' + JSON.stringify(rules) + ');\n' + adapter;
  const android = path.join(rootDir, 'android/app/src/main/assets/ugames');
  const ios = path.join(rootDir, 'ios/UGames/Resources');
  fs.mkdirSync(android, { recursive: true });
  fs.mkdirSync(ios, { recursive: true });
  fs.writeFileSync(path.join(android, 'ad-adapter.js'), script);
  fs.writeFileSync(path.join(android, 'ad-rules.json'), JSON.stringify(rules, null, 2) + '\n');
  fs.writeFileSync(path.join(ios, 'ad-adapter.js'), script);
  fs.writeFileSync(
    path.join(ios, 'content-rules.json'),
    JSON.stringify(contentRules, null, 2) + '\n',
  );
}

module.exports = { buildShared, compileContentRules, validateRules };
if (require.main === module) {
  try {
    buildShared(path.resolve(process.argv[2] || path.join(__dirname, '..')));
  } catch (error) {
    console.error('Shared asset build failed:', error.message);
    process.exitCode = 1;
  }
}
