#!/usr/bin/env bash
# Runs the editor-bridge authorization tests.
# They fail until a script message is ignored unless its frame is the main
# frame and that frame's URL is the bundled macdraw page.
set -euo pipefail
cd "$(dirname "$0")"

python3 prepare-sources.py

if ! command -v swift >/dev/null 2>&1; then
  toolchain="/tmp/swift/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin"
  if [[ -x "$toolchain/swift" ]]; then
    export PATH="$toolchain:$PATH"
    export LD_LIBRARY_PATH="/tmp/swiftlibs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  fi
fi

exec swift test "$@"
