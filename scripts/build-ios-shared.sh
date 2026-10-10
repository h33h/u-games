#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if command -v node >/dev/null 2>&1; then
  exec node scripts/build-shared.cjs
fi
for candidate in "$HOME"/.nvm/versions/node/v20*/bin/node "$HOME"/.nvm/versions/node/v22*/bin/node /opt/homebrew/bin/node /usr/local/bin/node; do
  if [ -x "$candidate" ]; then exec "$candidate" scripts/build-shared.cjs; fi
done
echo "Node.js 20 or newer is required to package shared protection." >&2
exit 1
