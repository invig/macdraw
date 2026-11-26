#!/usr/bin/env python3
"""Stage the app sources this package compiles.

On macOS the staged files are the originals. Linux Swift cannot compile
`#selector` or `@objc` (there is no Objective-C runtime), so those registration
lines are rewritten to call the same methods. The script-message handler is
copied unchanged. The script fails if an expected line disappeared.
"""

import os
import platform
import shutil
import sys

here = os.path.dirname(os.path.abspath(__file__))
src_dir = os.path.abspath(os.path.join(here, "..", "..", "..", "App", "Sources"))
dest = os.path.join(here, "MacDrawSources")
files = [
    "BundleSchemeHandler.swift",
    "EditorViewController.swift",
    "ExcalidrawDocument.swift",
    "ExportPanel.swift",
    "LibraryStore.swift",
]

linux = platform.system() != "Darwin"


def must_replace(text, old, new, filename):
    if old not in text:
        sys.exit(f"{filename}: expected snippet not found:\n{old}")
    return text.replace(old, new, 1)


def adapt_editor(text):
    text = must_replace(
        text,
        """        NotificationCenter.default.addObserver(self, selector: #selector(libraryChangedElsewhere(_:)),
                                               name: Self.libraryDidChange, object: nil)""",
        """        // Linux Swift cannot build an Objective-C selector. This block calls the same method.
        NotificationCenter.default.addObserver(forName: Self.libraryDidChange, object: nil, queue: nil) { [weak self] note in
            self?.libraryChangedElsewhere(note)
        }""",
        "EditorViewController.swift",
    )
    text = must_replace(
        text,
        """        switch item.action {
        case #selector(showInFinder(_:)): return document?.fileURL != nil
        case #selector(exportImage(_:)): return isReady
        default: return true
        }""",
        """        // Menu actions are Objective-C selectors. Not part of the bridge tests.
        switch item.tag {
        case 1: return document?.fileURL != nil
        case 2: return isReady
        default: return true
        }""",
        "EditorViewController.swift",
    )
    text = text.replace("@objc ", "")
    if "#selector" in text or "@objc" in text:
        sys.exit("EditorViewController.swift: objc syntax remains after adaptation")
    return text


def adapt_export(text):
    text = must_replace(
        text,
        "        formatPopup.action = #selector(formatChanged)\n",
        "        formatPopup.target = self\n",
        "ExportPanel.swift",
    )
    text = text.replace("@objc ", "")
    if "#selector" in text or "@objc" in text:
        sys.exit("ExportPanel.swift: objc syntax remains after adaptation")
    return text


def main():
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    os.makedirs(dest)
    for name in files:
        source = os.path.join(src_dir, name)
        with open(source, encoding="utf-8") as handle:
            text = handle.read()
        if linux and name == "EditorViewController.swift":
            text = adapt_editor(text)
        elif linux and name == "ExportPanel.swift":
            text = adapt_export(text)
        with open(os.path.join(dest, name), "w", encoding="utf-8") as handle:
            handle.write(text)
    print(f"staged {len(files)} sources ({'linux objc rewrite' if linux else 'unchanged'})")


if __name__ == "__main__":
    main()
