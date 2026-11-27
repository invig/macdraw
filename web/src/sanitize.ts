// Excalidraw renders an iframe element's customData.generationData (the HTML of its AI
// "magic frame", or an error message) in a script-enabled srcdoc frame. MacDraw never
// generates that data, so whatever is there came from a file, the clipboard or a library:
// strip it before Excalidraw gets the elements.
import { loadSceneOrLibraryFromBlob, MIME_TYPES, serializeAsJSON } from "@excalidraw/excalidraw";

type Data = Record<string, unknown>;

const isRecord = (value: unknown): value is Data =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const hasOwn = (obj: object, key: string) => Object.prototype.hasOwnProperty.call(obj, key);

// Excalidraw's deep copy assigns every own key, so a "__proto__" key turns into the copy's
// prototype and anything under it (customData, generationData) would be inherited again.
const needsRebuild = (obj: Data) => Object.getPrototypeOf(obj) !== Object.prototype || hasOwn(obj, "__proto__");

function ownProps(obj: Data, omit: readonly string[]): Data {
  const out: Data = {};
  for (const [key, value] of Object.entries(obj)) {
    if (key !== "__proto__" && !omit.includes(key)) out[key] = value;
  }
  return out;
}

export function withoutGeneratedHtml<T>(element: T): T {
  if (!isRecord(element)) return element;
  const customData = hasOwn(element, "customData") ? element.customData : undefined;
  const dirtyData = isRecord(customData) && ("generationData" in customData || needsRebuild(customData));
  if (!dirtyData && !needsRebuild(element)) return element;
  const copy = ownProps(element, []);
  if (isRecord(customData)) copy.customData = ownProps(customData, ["generationData"]);
  return copy as T;
}

export const elementsWithoutGeneratedHtml = <T>(elements: readonly T[]): T[] => elements.map(withoutGeneratedHtml);

// Library items are { elements: [...] } (v2) or a bare array of elements (v1).
export function libraryItemsWithoutGeneratedHtml<T>(items: T): T {
  if (!Array.isArray(items)) return items;
  return items.map((item: unknown) => {
    if (Array.isArray(item)) return elementsWithoutGeneratedHtml(item);
    if (isRecord(item) && Array.isArray(item.elements)) {
      return { ...ownProps(item, []), elements: elementsWithoutGeneratedHtml(item.elements) };
    }
    return item;
  }) as T;
}

export function libraryWithoutGeneratedHtml(lib: unknown): unknown {
  if (Array.isArray(lib)) return libraryItemsWithoutGeneratedHtml(lib);
  if (!isRecord(lib)) return lib;
  const copy = ownProps(lib, []);
  if ("libraryItems" in copy) copy.libraryItems = libraryItemsWithoutGeneratedHtml(copy.libraryItems);
  if ("library" in copy) copy.library = libraryItemsWithoutGeneratedHtml(copy.library);
  return copy;
}

const IMAGE_TYPES: readonly string[] = [
  MIME_TYPES.svg, MIME_TYPES.png, MIME_TYPES.jpg, MIME_TYPES.gif, MIME_TYPES.webp,
  MIME_TYPES.bmp, MIME_TYPES.ico, MIME_TYPES.avif, MIME_TYPES.jfif,
];

function sniffImageType(bytes: Uint8Array): string | null {
  const starts = (sig: number[]) => sig.every((b, i) => bytes[i] === b);
  if (starts([137, 80, 78, 71, 13, 10, 26, 10])) return MIME_TYPES.png;
  if (starts([255, 216, 255])) return MIME_TYPES.jpg;
  if (starts([71, 73, 70, 56, 57, 97])) return MIME_TYPES.gif;
  return null;
}

// Same MIME fix-ups Excalidraw applies to a dropped file before decoding it (normalizeFile
// in 0.18.1), so the file we inspect is decoded the same way Excalidraw would decode it.
async function normalizeDroppedFile(file: File): Promise<File> {
  if (!file.type) {
    if (file.name.endsWith(".excalidrawlib")) return new File([file], file.name, { type: MIME_TYPES.excalidrawlib });
    if (file.name.endsWith(".excalidraw")) return new File([file], file.name, { type: MIME_TYPES.excalidraw });
  } else if (!IMAGE_TYPES.includes(file.type)) {
    return file;
  }
  const sniffed = sniffImageType(new Uint8Array(await file.slice(0, 8).arrayBuffer()));
  return sniffed && sniffed !== file.type ? new File([file], file.name, { type: sniffed }) : file;
}

/** The file to hand Excalidraw for a drop: a dropped scene or library is decoded once and
 *  re-encoded without generation HTML; anything else is passed on unchanged. */
export async function sanitizedDropFile(original: File): Promise<File> {
  const file = await normalizeDroppedFile(original);
  let loaded: Awaited<ReturnType<typeof loadSceneOrLibraryFromBlob>>;
  try {
    loaded = await loadSceneOrLibraryFromBlob(file, null, null);
  } catch {
    return file;
  }
  if (loaded.type === MIME_TYPES.excalidraw) {
    const { elements, appState, files } = loaded.data;
    const json = serializeAsJSON(elementsWithoutGeneratedHtml(elements), appState, files, "local");
    return new File([json], "drawing.excalidraw", { type: MIME_TYPES.excalidraw });
  }
  const json = JSON.stringify(libraryWithoutGeneratedHtml(loaded.data));
  return new File([json], "library.excalidrawlib", { type: MIME_TYPES.excalidrawlib });
}
