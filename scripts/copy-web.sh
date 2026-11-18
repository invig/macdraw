#!/bin/zsh
# Copies web/dist into the current target's Resources/web.
# --no-cjk leaves out the 12 MB Chinese/Japanese/Korean font (used for Quick Look extensions).
set -euo pipefail
ROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
DEST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/web"
EXCLUDES=(--exclude .build-stamp)
[[ "${1:-}" == "--no-cjk" ]] && EXCLUDES+=(--exclude fonts/Xiaolai)
mkdir -p "$DEST"
rsync -a --delete "${EXCLUDES[@]}" "$ROOT/web/dist/" "$DEST/"
echo "Copied web bundle to $DEST"
