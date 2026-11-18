import { createRoot } from "react-dom/client";
import App from "./App";
import "@excalidraw/excalidraw/index.css";

// Serve Excalidraw's drawing fonts from our own bundle (copied to /fonts at build time).
(window as unknown as { EXCALIDRAW_ASSET_PATH: string }).EXCALIDRAW_ASSET_PATH =
  window.location.origin + "/";

createRoot(document.getElementById("root")!).render(<App />);
