import type { BinaryFiles } from "@excalidraw/excalidraw/types";

// Excalidraw uses a file's dataURL as an <img> source as-is, so a drawing could point it at
// any address. Keep only inline image data; anything else would be fetched over the network.
const INLINE_IMAGE = /^data:image\//i;

export function inlineImageFiles(files: BinaryFiles | null | undefined): BinaryFiles {
  if (!files || typeof files !== "object") return {};
  return Object.fromEntries(
    Object.entries(files).filter(
      ([, file]) => !!file && typeof file === "object" && typeof file.dataURL === "string" && INLINE_IMAGE.test(file.dataURL),
    ),
  );
}
