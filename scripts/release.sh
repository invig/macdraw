#!/bin/zsh
# Builds a signed, notarised, universal MacDraw.app and publishes it as a GitHub release.
# The release carries the zip twice: as MacDraw-<version>.zip (what the app's updater fetches)
# and as MacDraw.zip, so https://github.com/invig/macdraw/releases/latest/download/MacDraw.zip
# always gets the newest. (Same flow as Expanse's release script.)
#
# One-time setup:
#   1. A "Developer ID Application" certificate in your keychain
#      (Xcode › Settings › Accounts › Manage Certificates › + › Developer ID Application).
#   2. Notarisation credentials in the keychain. The profile belongs to your Apple developer
#      account, not the app, so Expanse's "expanse-notary" works here too. To make one:
#        xcrun notarytool store-credentials <profile> --apple-id <you@example.com> --team-id <TEAMID>
#      (it asks for an app-specific password from account.apple.com).
#
# Usage: scripts/release.sh               # bump MARKETING_VERSION in project.yml first
#        DRY_RUN=1 scripts/release.sh     # build and sign only: no notarising, no publishing
#        NO_PUBLISH=1 scripts/release.sh  # build, sign, notarise and zip, but don't publish
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
cd "$(dirname "$0")/.."

VERSION=$(awk '/MARKETING_VERSION:/{gsub(/"/,"",$2); print $2; exit}' project.yml)
IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application}"
PROFILE="${NOTARY_PROFILE:-expanse-notary}"
# The team is read from the certificate, so it doesn't have to live in the repo.
TEAM="${DEVELOPMENT_TEAM:-$(security find-identity -v -p codesigning |
  sed -n 's/.*"Developer ID Application: .*(\([A-Z0-9]\{10\}\))".*/\1/p' | head -1)}"
[[ -n "$TEAM" ]] || { echo "No Developer ID Application certificate in the keychain (see the top of this script)." >&2; exit 1; }
DERIVED=build/DerivedData-release
OUT=build/release
APP="$DERIVED/Build/Products/Release/MacDraw.app"
ZIP="$OUT/MacDraw-$VERSION.zip"

echo "==> MacDraw $VERSION"
if [[ -z "${DRY_RUN:-}${NO_PUBLISH:-}" ]] && git ls-remote --exit-code --tags origin "v$VERSION" >/dev/null 2>&1; then
  echo "Release v$VERSION already exists; bump MARKETING_VERSION in project.yml." >&2
  exit 1
fi

echo "==> Building universal app (Apple silicon + Intel), signed with $IDENTITY"
xcodegen generate --quiet
rm -rf "$DERIVED" "$OUT"
mkdir -p "$OUT"
# Xcode signs inside-out: each Quick Look extension with its own (sandbox) entitlements, then
# the app. Hardened runtime and a secure timestamp are what notarisation requires.
xcodebuild -project MacDraw.xcodeproj -scheme MacDraw -configuration Release \
  -derivedDataPath "$DERIVED" -destination "generic/platform=macOS" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM" ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS="--timestamp" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  build -quiet

echo "==> Checking the signature"
codesign --verify --deep --strict --verbose=2 "$APP"
for code in "$APP" "$APP"/Contents/PlugIns/*.appex; do
  info=$(codesign -dvv "$code" 2>&1)
  flags=$(awk -F'[()]' '/^CodeDirectory/{print $2}' <<< "$info")
  authority=$(awk -F= '/^Authority/ && !seen++ {print $2}' <<< "$info")
  echo "    ${code:t}: $authority, flags $flags"
  [[ "$flags" == *runtime* ]] || { echo "${code:t} isn't signed with the hardened runtime" >&2; exit 1; }
done
lipo -archs "$APP/Contents/MacOS/MacDraw"

if [[ -n "${DRY_RUN:-}" ]]; then
  echo "==> Dry run: skipping notarisation and publishing. App at $APP"
  exit 0
fi

echo "==> Notarising (this takes a few minutes)"
ditto -c -k --keepParent "$APP" "$OUT/notarise.zip"
xcrun notarytool submit "$OUT/notarise.zip" --keychain-profile "$PROFILE" --wait
rm "$OUT/notarise.zip"
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose=2 "$APP"

echo "==> Packaging"
# Zipped again after stapling, so the ticket is inside. The updater expects MacDraw.app at the
# top of the zip.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
cp "$ZIP" "$OUT/MacDraw.zip"
echo "Built $ZIP ($(du -h "$ZIP" | cut -f1))"
shasum -a 256 "$ZIP"

if [[ -n "${NO_PUBLISH:-}" ]]; then
  echo "==> Not publishing (NO_PUBLISH). Zips in $OUT"
  exit 0
fi

echo "==> Publishing GitHub release v$VERSION"
gh release create "v$VERSION" "$ZIP" "$OUT/MacDraw.zip" --title "MacDraw $VERSION" --notes-file - <<NOTES
A native Mac app for Excalidraw drawings.

Download \`MacDraw-$VERSION.zip\`, unzip it and drag **MacDraw** to Applications. It's signed and
notarised by Apple and runs on macOS 14 or later (Apple silicon and Intel). \`MacDraw.zip\` is the
same file. MacDraw checks for updates once a day (MacDraw menu › Check for Updates…).

If Quick Look doesn't show your drawings, turn on **MacDraw Thumbnails** and **MacDraw Preview** in
System Settings › General › Login Items & Extensions › Quick Look.
NOTES
echo "==> Done"
