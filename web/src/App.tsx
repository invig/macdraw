import { useEffect, useMemo, useRef, useState } from "react";
import {
  Excalidraw,
  exportToBlob,
  exportToSvg,
  getNonDeletedElements,
  getSceneVersion,
  MainMenu,
  restore,
  restoreLibraryItems,
  serializeAsJSON,
  serializeLibraryAsJSON,
} from "@excalidraw/excalidraw";
import type {
  AppState,
  BinaryFiles,
  ExcalidrawImperativeAPI,
  ExcalidrawInitialDataState,
  LibraryItems,
} from "@excalidraw/excalidraw/types";
import { isNative, post } from "./bridge";
import { inlineImageFiles } from "./files";

type Elements = Parameters<typeof serializeAsJSON>[0];

declare global {
  interface Window {
    macdraw: {
      /** Native calls this once with the document contents (null for a new document). */
      load: (sceneJSON: string | null, libraryJSON: string | null) => void;
      /** Native calls this before saving: returns the full .excalidraw JSON. */
      serialize: () => string;
      /** What File > Export can offer: is there anything to export, is anything selected. */
      exportInfo: () => { isEmpty: boolean; hasSelection: boolean };
      /** File > Export: PNG comes back base64-encoded, SVG as text. */
      exportImage: (opts: ExportOptions) => Promise<string>;
      /** "Add to Excalidraw" from libraries.excalidraw.com: merge a fetched .excalidrawlib (native asked first). */
      importLibrary: (libraryJSON: string) => Promise<void>;
      /** Another window changed the shared library: replace ours without echoing it back. */
      setLibrary: (libraryJSON: string) => Promise<void>;
      /** Native menu Undo/Redo. */
      undo: () => void;
      redo: () => void;
    };
  }
}

type ExportOptions = {
  format: "png" | "svg";
  scale: number;
  background: boolean;
  embedScene: boolean;
  selectionOnly: boolean;
  darkMode: boolean;
};

const SERIALIZE_DEBOUNCE_MS = 400;
const systemTheme = () =>
  window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";

// While typing in a text element, Undo/Redo belong to the text field, not the scene.
const editingText = () => {
  const el = document.activeElement;
  return el instanceof HTMLTextAreaElement || el instanceof HTMLInputElement;
};

function sendKey(key: string, shift: boolean) {
  const ev = new KeyboardEvent("keydown", {
    key,
    code: "KeyZ",
    metaKey: true,
    shiftKey: shift,
    bubbles: true,
    cancelable: true,
  });
  document.dispatchEvent(ev);
}

export default function App() {
  // `gen` remounts the editor when native reloads the document (Revert, Versions).
  const [scene, setScene] = useState<{ data: ExcalidrawInitialDataState; gen: number } | null>(null);
  const apiRef = useRef<ExcalidrawImperativeAPI | null>(null);
  const lastVersion = useRef<number>(-1);
  const lastFileCount = useRef<number>(0);
  const lastBg = useRef<string | null>(null);
  const loaded = useRef(false);
  const serializeTimer = useRef<number | undefined>(undefined);
  const applyingRemoteLibrary = useRef(false);

  const serialize = () => {
    const api = apiRef.current;
    if (!api) return "";
    return serializeAsJSON(api.getSceneElementsIncludingDeleted(), api.getAppState(), inlineImageFiles(api.getFiles()), "local");
  };

  useEffect(() => {
    window.macdraw = {
      load: (sceneJSON, libraryJSON) => {
        let data: ExcalidrawInitialDataState = {};
        if (sceneJSON) {
          try {
            const parsed = JSON.parse(sceneJSON);
            const restored = restore(parsed, null, null, { repairBindings: true });
            data = {
              elements: restored.elements,
              appState: { ...restored.appState },
              files: inlineImageFiles(restored.files),
            };
          } catch (e) {
            post({ type: "log", message: `Failed to parse scene: ${String(e)}` });
          }
        } else {
          data = { appState: { theme: systemTheme() } };
        }
        if (libraryJSON) {
          try {
            const lib = JSON.parse(libraryJSON);
            data.libraryItems = restoreLibraryItems(lib.libraryItems ?? lib.library ?? [], "unpublished");
          } catch (e) {
            post({ type: "log", message: `Failed to parse library: ${String(e)}` });
          }
        }
        loaded.current = false;
        setScene((prev) => ({ data, gen: (prev?.gen ?? 0) + 1 }));
      },
      serialize,
      exportInfo: () => {
        const api = apiRef.current;
        if (!api) return { isEmpty: true, hasSelection: false };
        const selected = Object.keys(api.getAppState().selectedElementIds ?? {}).length;
        return { isEmpty: getNonDeletedElements(api.getSceneElements()).length === 0, hasSelection: selected > 0 };
      },
      exportImage: async (opts) => {
        const api = apiRef.current;
        if (!api) throw new Error("Editor not ready");
        const appState = api.getAppState();
        let elements = getNonDeletedElements(api.getSceneElements());
        if (opts.selectionOnly) {
          const ids = appState.selectedElementIds ?? {};
          const groups = new Set(elements.filter((e) => ids[e.id]).flatMap((e) => e.groupIds));
          // Include bound text and other members of selected groups, like Excalidraw's own export.
          elements = elements.filter(
            (e) => ids[e.id] || ("containerId" in e && e.containerId && ids[e.containerId]) || e.groupIds.some((g) => groups.has(g)),
          );
        }
        const exportState = {
          ...appState,
          exportBackground: opts.background,
          exportEmbedScene: opts.embedScene,
          exportWithDarkMode: opts.darkMode,
          exportScale: opts.scale,
        };
        const files = inlineImageFiles(api.getFiles());
        if (opts.format === "svg") {
          const svg = await exportToSvg({ elements, appState: exportState, files });
          return svg.outerHTML;
        }
        const blob = await exportToBlob({
          elements,
          appState: exportState,
          files,
          mimeType: "image/png",
          getDimensions: (w: number, h: number) => ({ width: w * opts.scale, height: h * opts.scale, scale: opts.scale }),
        });
        const bytes = new Uint8Array(await blob.arrayBuffer());
        let binary = "";
        for (let i = 0; i < bytes.length; i += 0x8000) {
          binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
        }
        return btoa(binary);
      },
      importLibrary: async (libraryJSON) => {
        const api = apiRef.current;
        if (!api) throw new Error("Editor not ready");
        // No `prompt: true`: that uses window.confirm, which blocks the page (and any save
        // waiting on it) until answered. Native shows its own sheet before calling this.
        await api.updateLibrary({
          libraryItems: new Blob([libraryJSON], { type: "application/vnd.excalidrawlib+json" }),
          merge: true,
          openLibraryMenu: true,
          defaultStatus: "published",
        });
      },
      setLibrary: async (libraryJSON) => {
        const api = apiRef.current;
        if (!api) return;
        const lib = JSON.parse(libraryJSON);
        applyingRemoteLibrary.current = true;
        try {
          await api.updateLibrary({
            libraryItems: restoreLibraryItems(lib.libraryItems ?? lib.library ?? [], "unpublished"),
            merge: false,
          });
        } finally {
          window.setTimeout(() => (applyingRemoteLibrary.current = false), 0);
        }
      },
      undo: () => editingText() ? document.execCommand("undo") : sendKey("z", false),
      redo: () => editingText() ? document.execCommand("redo") : sendKey("z", true),
    };
    post({ type: "ready" });
    // Running in a plain browser (npm run dev): start with an empty scene.
    if (!isNative()) window.macdraw.load(null, null);
  }, []);

  const onChange = (elements: Elements, appState: AppState, files: BinaryFiles) => {
    if (!loaded.current) return;
    const version = getSceneVersion(elements);
    const fileCount = Object.keys(files).length;
    const bg = appState.viewBackgroundColor;
    // onChange fires on every pointer move / selection change; only persist real edits.
    if (version === lastVersion.current && fileCount === lastFileCount.current && bg === lastBg.current) return;
    lastVersion.current = version;
    lastFileCount.current = fileCount;
    lastBg.current = bg;

    post({ type: "dirty" });
    window.clearTimeout(serializeTimer.current);
    serializeTimer.current = window.setTimeout(() => {
      post({ type: "scene", json: serialize() });
    }, SERIALIZE_DEBOUNCE_MS);
  };

  const onLibraryChange = (items: LibraryItems) => {
    if (!loaded.current || applyingRemoteLibrary.current) return;
    post({ type: "library", json: serializeLibraryAsJSON(items) });
  };

  const uiOptions = useMemo(
    () => ({
      canvasActions: {
        // File handling is native (File menu, Cmd-S, Cmd-O); hide the web equivalents.
        loadScene: false,
        saveToActiveFile: false,
        export: false as const,
        saveAsImage: true,
      },
    }),
    [],
  );

  if (!scene) return null;

  return (
    <div style={{ height: "100%", width: "100%" }}>
      <Excalidraw
        key={scene.gen}
        initialData={scene.data}
        excalidrawAPI={(api) => {
          apiRef.current = api;
          // Record the loaded state as the baseline so opening a file doesn't mark it edited.
          window.setTimeout(() => {
            const els = api.getSceneElementsIncludingDeleted();
            lastVersion.current = getSceneVersion(els);
            lastFileCount.current = Object.keys(api.getFiles()).length;
            lastBg.current = api.getAppState().viewBackgroundColor;
            loaded.current = true;
          }, 0);
        }}
        onChange={onChange}
        onLibraryChange={onLibraryChange}
        UIOptions={uiOptions}
        autoFocus
        handleKeyboardGlobally
      >
        {/* Excalidraw's default menu minus "Excalidraw links" (and the web-only file items). */}
        <MainMenu>
          <MainMenu.DefaultItems.SaveAsImage />
          <MainMenu.DefaultItems.SearchMenu />
          <MainMenu.DefaultItems.Help />
          <MainMenu.DefaultItems.ClearCanvas />
          <MainMenu.Separator />
          <MainMenu.DefaultItems.ToggleTheme />
          <MainMenu.DefaultItems.ChangeCanvasBackground />
        </MainMenu>
      </Excalidraw>
    </div>
  );
}
