#!/bin/zsh
# Builds the web bundle (web/dist) if any web source is newer than the last build.
# Runs once per Xcode build via the WebBundle aggregate target; fine to run by hand.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

ROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT/web"

[[ -d node_modules ]] || npm ci

STAMP=dist/.build-stamp
if [[ -f $STAMP ]] && [[ -z "$(find src index.html render.html vite.config.ts package.json package-lock.json -newer $STAMP -print -quit)" ]]; then
  echo "web/dist is up to date"
  exit 0
fi
npm run build --silent
touch $STAMP
