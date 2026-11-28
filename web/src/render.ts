// Headless renderer for the Quick Look thumbnail and preview extensions.
// Native calls window.macdrawRender(sceneJSON, maxSize) and gets back a base64 PNG.
import { exportToBlob, getNonDeletedElements, restore } from "@excalidraw/excalidraw";
import { inlineImageFiles } from "./files";

(window as unknown as { EXCALIDRAW_ASSET_PATH: string }).EXCALIDRAW_ASSET_PATH = window.location.origin + "/";

async function render(sceneJSON: string, maxSize: number): Promise<string | null> {
  const scene = restore(JSON.parse(sceneJSON), null, null);
  const elements = getNonDeletedElements(scene.elements);
  if (elements.length === 0) return null;
  const blob = await exportToBlob({
    elements,
    files: inlineImageFiles(scene.files),
    appState: {
      ...scene.appState,
      exportBackground: true,
      exportWithDarkMode: false,
      exportEmbedScene: false,
    },
    mimeType: "image/png",
    // Scale up or down so the longest side is maxSize (maxWidthOrHeight only shrinks).
    getDimensions: (w: number, h: number) => {
      const scale = Math.min(maxSize / Math.max(w, h), 8);
      return { width: Math.round(w * scale), height: Math.round(h * scale), scale };
    },
    exportPadding: 16,
  });
  const bytes = new Uint8Array(await blob.arrayBuffer());
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(binary);
}

declare global {
  interface Window {
    macdrawRender: typeof render;
  }
}
window.macdrawRender = render;
