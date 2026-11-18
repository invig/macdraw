# MacDraw

A native Mac app for [Excalidraw](https://excalidraw.com) drawings.

Excalidraw's hand-drawn whiteboard, but your `.excalidraw` files live on your disk like any other
document: double-click to open, ⌘S to save, autosave, version history, tabs, and Quick Look in Finder.
No account, no browser, works offline.

## Features

- Opens and saves standard `.excalidraw` files, compatible with excalidraw.com, Obsidian and other tools
- Autosave, Versions (File → Revert To), Open Recent, Duplicate, Rename, Move To, window tabs
- Export to PNG or SVG (⌥⌘E) with scale, background, dark mode and "embed scene" options
- Quick Look: press Space on a drawing in Finder to preview it; Finder thumbnails
- Shape libraries, including one-click "Add to Excalidraw" from [libraries.excalidraw.com](https://libraries.excalidraw.com)
- Apple silicon and Intel, macOS 14 or later

## Install

Download the latest `MacDraw-<version>.zip` from [Releases](https://github.com/invig/macdraw/releases),
unzip it and drag **MacDraw** to Applications. It's signed and notarised by Apple, and keeps itself up
to date: it checks GitHub once a day and asks before installing (MacDraw › Check for Updates…).

If Quick Look doesn't show your drawings, turn on **MacDraw Thumbnails** and **MacDraw Preview** in
System Settings → General → Login Items & Extensions → Quick Look.

## Build from source

Needs Xcode, Node.js and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
xcodegen generate
open MacDraw.xcodeproj
```

Then press ⌘R. Debug builds are signed ad hoc and never update themselves.

`scripts/release.sh` builds a universal release signed with a Developer ID, notarises it and
publishes it as a GitHub release, which is also what the built-in updater reads. See the top of
the script for the one-time setup; `DRY_RUN=1` builds and signs without notarising or publishing.

## How it works

The editor is the official [`@excalidraw/excalidraw`](https://www.npmjs.com/package/@excalidraw/excalidraw)
component running in a WebKit view (`web/`). Everything around it is native AppKit (`App/`): the app is an
`NSDocument` app, so files, saving and versions are handled by macOS itself. The Quick Look extensions
(`QuickLook/`) render drawings with Excalidraw's own exporter, so previews look exactly like the app.

## Credits

MacDraw is an independent project and isn't affiliated with Excalidraw. Excalidraw is © Excalidraw
and released under the MIT License; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
