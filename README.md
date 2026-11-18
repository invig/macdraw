# MacDraw

A native macOS document app for `.excalidraw` files. The editor is
[Excalidraw](https://github.com/excalidraw/excalidraw) (the `@excalidraw/excalidraw` package, MIT)
running in a WKWebView; everything to do with files is AppKit's `NSDocument`.

- Open, Save, Duplicate, Rename, Move To, Revert / Browse All Versions, autosave, Open Recent, tabs
- Double-click `.excalidraw` files in Finder
- File → Export as PNG… (⌥⌘E) / SVG… with scale, background, dark mode, embed-scene and selection-only options
- Quick Look: Space-bar previews and Finder thumbnails rendered by Excalidraw itself
- Works offline (fonts and editor are bundled)

## Install a release

Download `MacDraw-<version>.zip` from [Releases](https://github.com/invig/macdraw/releases), unzip, and move
`MacDraw.app` to Applications.

Releases are **not notarized**, so macOS blocks the first launch. Either open it once, then go to
System Settings → Privacy & Security and click **Open Anyway**, or run:

```bash
xattr -dr com.apple.quarantine /Applications/MacDraw.app
```

Quick Look extensions may start switched off: System Settings → General → Login Items & Extensions →
Quick Look → enable **MacDraw Thumbnails** and **MacDraw Preview**. Thumbnails can take a log out/in
to appear.

## Build

Needs Xcode, Node and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
xcodegen generate
open MacDraw.xcodeproj      # ⌘R
```

The build runs `scripts/build-web.sh` (Vite build of `web/`, skipped when nothing changed) and copies
the bundle into the app and both Quick Look extensions.

Release zip (universal, ad-hoc signed): `scripts/release.sh` → `build/release/MacDraw-<version>.zip`.
The version comes from `MARKETING_VERSION` in `project.yml`.

## Layout

| Path | What |
|---|---|
| `web/src/App.tsx` | Excalidraw + the JS side of the bridge (`window.macdraw`) |
| `web/src/render.ts` | Headless renderer (scene JSON → PNG) used by Quick Look |
| `App/Sources/ExcalidrawDocument.swift` | NSDocument: read/write, autosave, flush-before-save |
| `App/Sources/EditorViewController.swift` | WKWebView host, bridge messages, export, downloads, file pickers |
| `App/Sources/ExportPanel.swift` | Export save panel and its options |
| `App/Sources/BundleSchemeHandler.swift` | Serves the bundled web code at `macdraw://app/` |
| `App/Sources/MainMenu.swift` | Menus (File menu = standard NSDocument actions) |
| `QuickLook/` | Thumbnail and Preview extensions + shared offscreen renderer |
| `scripts/make-icon.swift` | Regenerates the app icon from `App/Icon/icon-source.webp` |
| `project.yml` | XcodeGen spec, incl. the `.excalidraw` document type |

## Bridge

- Page → native (`webkit.messageHandlers.macdraw`): `ready`, `dirty`, `scene` (debounced JSON), `library`.
- Native → page: `macdraw.load(scene, library)`, `macdraw.serialize()` (called before every save),
  `exportInfo()`, `exportImage(opts)`, `undo()`, `redo()`.

## Notes

- The main app is not sandboxed; the Quick Look extensions are (required).
- The shape library is stored in `~/Library/Application Support/MacDraw/library.excalidrawlib`.
- Third-party licenses: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
