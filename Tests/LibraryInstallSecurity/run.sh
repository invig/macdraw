#!/bin/bash
# Runs the library-install tests. Exits 0 only when every assertion holds.
# Until the install path is fixed, the Swift assertions fail on purpose.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"

if [[ -d /tmp/swift-install/swift-6.2.1-RELEASE-ubuntu24.04/usr/bin ]]; then
  export PATH="/tmp/swift-install/swift-6.2.1-RELEASE-ubuntu24.04/usr/bin:${PATH}"
fi
if ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc is required" >&2
  exit 127
fi

BUILD="${TMPDIR:-/tmp}/library-install-security"
rm -rf "$BUILD"
mkdir -p "$BUILD/src" "$BUILD/home"
export HOME="$BUILD/home"

cp "$ROOT/App/Sources/LibraryImporter.swift" "$BUILD/src/"
cp "$ROOT/App/Sources/EditorViewController.swift" "$BUILD/src/"
cp "$ROOT/App/Sources/LibraryStore.swift" "$BUILD/src/"
cp "$ROOT/App/Sources/BundleSchemeHandler.swift" "$BUILD/src/"
# The app sources are compiled in this test module, whose shims are the AppKit,
# WebKit, and UniformTypeIdentifiers types. On Linux, URLSession lives in
# FoundationNetworking; the function bodies are otherwise the files in App/Sources.
for f in LibraryImporter.swift EditorViewController.swift BundleSchemeHandler.swift LibraryStore.swift; do
  sed -i '/^import AppKit$/d; /^import WebKit$/d; /^import UniformTypeIdentifiers$/d' "$BUILD/src/$f"
  if ! grep -q '^import Foundation$' "$BUILD/src/$f"; then
    sed -i '1i import Foundation' "$BUILD/src/$f"
  fi
done
if [[ "$(uname -s)" == "Linux" ]]; then
  for f in LibraryImporter.swift EditorViewController.swift BundleSchemeHandler.swift; do
    sed -i '1i import FoundationNetworking' "$BUILD/src/$f"
  done
fi
# Linux Swift has no Objective-C runtime. Drop @objc / #selector in the build
# copy only; the library-install functions themselves are not rewritten.
python3 - "$BUILD/src/EditorViewController.swift" << 'PY'
import sys
path = sys.argv[1]
text = open(path).read()
text = text.replace("@objc ", "")
out = []
i = 0
while True:
    j = text.find("#selector(", i)
    if j < 0:
        out.append(text[i:])
        break
    out.append(text[i:j])
    k = j + len("#selector(")
    depth = 1
    while k < len(text) and depth:
        if text[k] == "(": depth += 1
        elif text[k] == ")": depth -= 1
        k += 1
    out.append('Selector("")')
    i = k
open(path, "w").write("".join(out))
PY

SWIFT_SOURCES=(
  "$HERE/Shims/UniformTypeIdentifiers.swift"
  "$HERE/Shims/AppKit.swift"
  "$HERE/Shims/WebKit.swift"
  "$HERE/Support/DocumentStubs.swift"
  "$BUILD/src/LibraryStore.swift"
  "$BUILD/src/BundleSchemeHandler.swift"
  "$BUILD/src/LibraryImporter.swift"
  "$BUILD/src/EditorViewController.swift"
  "$HERE/SecurityTests.swift"
)
if ! grep -q 'issueAddLibraryToken' "$ROOT/App/Sources/LibraryImporter.swift"; then
  SWIFT_SOURCES+=("$HERE/Support/TokenShim.swift")
fi

swiftc -g -D DEBUG -parse-as-library -o "$BUILD/security-tests" \
  -module-name LibraryInstallSecurity \
  "${SWIFT_SOURCES[@]}"

"$BUILD/security-tests"
