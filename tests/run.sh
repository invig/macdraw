#!/bin/bash
# Runs the navigation-policy tests against App/Sources/EditorViewController.swift.
# They fail while subframe and script navigations are sent to NSWorkspace.shared.open.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFTC="${SWIFTC:-$(command -v swiftc || true)}"
if [[ -z "$SWIFTC" ]]; then
  echo "swiftc not found. Set SWIFTC to the Swift 5+ compiler." >&2
  exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

python3 - "$ROOT" "$WORK" << 'PY'
import pathlib, sys
root, work = map(pathlib.Path, sys.argv[1:])
source = (root / "App/Sources/EditorViewController.swift").read_text()
prepared = source.replace("import AppKit\nimport WebKit\n", "import Foundation\n")
prepared = prepared.replace("@objc ", "")
prepared = prepared.replace("URLResponse", "StubURLResponse")
replacements = {
    "#selector(showInFinder(_:))": 'Selector("showInFinder:")',
    "#selector(exportImage(_:))": 'Selector("exportImage:")',
    "#selector(libraryChangedElsewhere(_:))": 'Selector("libraryChangedElsewhere:")',
}
for old, new in replacements.items():
    if old not in prepared:
        raise SystemExit(f"missing {old}")
    prepared = prepared.replace(old, new)

def extract(text, signature):
    start = text.find(signature)
    if start < 0:
        raise SystemExit(f"missing signature {signature}")
    brace = text.find("{", start)
    depth = 0
    for i in range(brace, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[start:i + 1]
    raise SystemExit(f"unbalanced {signature}")

# The two delegates must be the original method bodies. Only the import lines,
# @objc, and #selector (unavailable without the Objective-C runtime) are adapted.
for signature in (
    "func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,",
    "func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,",
):
    if extract(source, signature) != extract(prepared, signature):
        raise SystemExit(f"delegate body changed while preparing {signature}")

(work / "EditorViewController.swift").write_text(prepared)
PY

BIN="$WORK/navigation-policy-tests"
"$SWIFTC" -swift-version 5 -D DEBUG -o "$BIN" \
  "$ROOT/tests/support/AppKitWebKitStubs.swift" \
  "$WORK/EditorViewController.swift" \
  "$ROOT/tests/NavigationPolicyTests.swift" \
  "$ROOT/tests/main.swift"

# swiftc on Linux needs its own lib directory at run time.
SWIFT_LIB="$(cd "$(dirname "$SWIFTC")/../lib/swift/linux" 2>/dev/null && pwd || true)"
if [[ -n "$SWIFT_LIB" ]]; then
  export LD_LIBRARY_PATH="$SWIFT_LIB${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
"$BIN"
