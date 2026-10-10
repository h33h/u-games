'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const root = path.resolve(__dirname, '..');
const [mode, ...selected] = process.argv.slice(2);
if (!['format', 'format:check', 'lint'].includes(mode)) {
  console.error('Usage: node scripts/code-quality.cjs <format|format:check|lint> [files...]');
  process.exit(1);
}

function run(command, args) {
  const result = spawnSync(command, args, {
    cwd: root,
    stdio: 'inherit',
    env: {
      ...process.env,
      PATH: [path.join(root, '.tools/bin'), process.env.PATH].join(path.delimiter),
    },
  });
  if (result.error) {
    console.error(
      `Cannot run ${command}: ${result.error.message}. Install tools with brew bundle.`,
    );
  }
  if (result.error || result.status !== 0) {
    process.exit(result.status || 1);
  }
}

const listing = selected.length
  ? null
  : spawnSync('git', ['ls-files', '-z', '--cached', '--others', '--exclude-standard'], {
      cwd: root,
      encoding: 'utf8',
    });
if (listing && listing.status !== 0) {
  console.error(listing.stderr || 'Cannot list repository files.');
  process.exit(1);
}
const files = [...new Set(selected.length ? selected : listing.stdout.split('\0'))]
  .filter(Boolean)
  .map((file) => path.relative(root, path.resolve(root, file)))
  .filter((file) => fs.existsSync(path.join(root, file)))
  .filter((file) => !/^(node_modules|\.tools|\.git)\//.test(file))
  .filter((file) => !/(?:^|\/)(?:build[^/]*|DerivedData|[^/]+\.xcodeproj)\//.test(file))
  .filter((file) => !file.startsWith('android/app/src/main/assets/ugames/'))
  .filter((file) => !file.startsWith('ios/UGames/Resources/'));

const javascript = files.filter((file) => /\.(?:js|cjs|mjs|html)$/.test(file));
const prettier = files.filter((file) =>
  /\.(?:js|cjs|mjs|json|html|css|xml|plist|ya?ml|md)$/.test(file),
);
const kotlin = files.filter((file) => /\.(?:kt|kts)$/.test(file));
const swift = files.filter((file) => file.endsWith('.swift'));
const shell = files.filter(
  (file) => file.endsWith('.sh') || (file.startsWith('.husky/') && !file.startsWith('.husky/_/')),
);

function nodeTool(packageName, entry, args) {
  run(process.execPath, [path.join(root, 'node_modules', packageName, entry), ...args]);
}

if (mode === 'format') {
  if (javascript.length) {
    nodeTool('eslint', 'bin/eslint.js', ['--fix', ...javascript]);
  }
  if (prettier.length) {
    nodeTool('prettier', 'bin/prettier.cjs', ['--write', ...prettier]);
  }
  if (kotlin.length) {
    run('ktlint', ['--format', ...kotlin]);
  }
  if (swift.length) {
    run('swiftformat', [...swift, '--config', '.swiftformat']);
  }
  if (shell.length) {
    run('shfmt', ['-ln', 'posix', '-i', '2', '-w', ...shell]);
  }
} else {
  if (prettier.length) {
    nodeTool('prettier', 'bin/prettier.cjs', ['--check', ...prettier]);
  }
  if (kotlin.length) {
    run('ktlint', kotlin);
  }
  if (swift.length) {
    run('swiftformat', [...swift, '--config', '.swiftformat', '--lint']);
  }
  if (shell.length) {
    run('shfmt', ['-ln', 'posix', '-i', '2', '-d', ...shell]);
  }
  if (mode === 'lint') {
    if (javascript.length) {
      nodeTool('eslint', 'bin/eslint.js', javascript);
    }
    if (swift.length) {
      run('swiftlint', ['lint', '--strict', '--no-cache', '--config', '.swiftlint.yml', ...swift]);
    }
    if (shell.length) {
      run('shellcheck', ['--shell=sh', ...shell]);
    }
  }
}
