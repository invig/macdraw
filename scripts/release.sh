#!/bin/zsh
# Builds a Release MacDraw.app (ad-hoc signed, not notarized) and zips it for distribution.
# Output: build/release/MacDraw-<version>.zip
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
cd "$(dirname "$0")/.."

VERSION=$(awk '/MARKETING_VERSION:/{gsub(/"/,"",$2); print $2; exit}' project.yml)
DERIVED=build/DerivedData-release
OUT=build/release
APP="$DERIVED/Build/Products/Release/MacDraw.app"

xcodegen generate --quiet
rm -rf "$DERIVED" "$OUT"
xcodebuild -project MacDraw.xcodeproj -scheme MacDraw -configuration Release \
  -derivedDataPath "$DERIVED" -destination "generic/platform=macOS" \
  ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY=- build -quiet

codesign --verify --deep --strict "$APP"
mkdir -p "$OUT/MacDraw-$VERSION"
ditto "$APP" "$OUT/MacDraw-$VERSION/MacDraw.app"
cp THIRD_PARTY_NOTICES.md "$OUT/MacDraw-$VERSION/"
(cd "$OUT" && ditto -c -k --sequesterRsrc --keepParent "MacDraw-$VERSION" "MacDraw-$VERSION.zip")
rm -rf "$OUT/MacDraw-$VERSION"

echo "Built $OUT/MacDraw-$VERSION.zip ($(du -h "$OUT/MacDraw-$VERSION.zip" | cut -f1))"
shasum -a 256 "$OUT/MacDraw-$VERSION.zip"
