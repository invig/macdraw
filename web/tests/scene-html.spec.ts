import { expect, test, type Page } from "@playwright/test";

/**
 * Spec for file-supplied diagram HTML.
 * These tests fail while an opened drawing can still put that HTML into a
 * script-enabled frame. They pass once the editor drops iframe elements, or
 * deletes customData.generationData, before the scene is shown — including
 * when the same elements arrive through paste, drop, or a library item.
 */

const PROBE = "macdraw-file-html-probe";

type SceneElement = Record<string, unknown>;

function element(overrides: SceneElement): SceneElement {
  return {
    id: "el",
    type: "rectangle",
    x: 80,
    y: 80,
    width: 360,
    height: 240,
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
    version: 1,
    versionNonce: 1,
    isDeleted: false,
    boundElements: null,
    updated: 1,
    link: null,
    locked: false,
    ...overrides,
  };
}

function label(id: string, text: string): SceneElement {
  return element({
    id,
    type: "text",
    text,
    originalText: text,
    fontSize: 20,
    fontFamily: 1,
    textAlign: "left",
    verticalAlign: "top",
    autoResize: true,
    lineHeight: 1.25,
    containerId: null,
    x: 40,
    y: 40,
    width: 180,
    height: 25,
    backgroundColor: "transparent",
  });
}

function attackerScript(via: string): string {
  return (
    "<" +
    "script>document.documentElement.dataset.macdrawProbe=" +
    JSON.stringify(via) +
    ";parent.postMessage({k:" +
    JSON.stringify(PROBE) +
    ",via:" +
    JSON.stringify(via) +
    "},'*')<" +
    "/script>"
  );
}

function attackerDocument(via: string): string {
  return `<!DOCTYPE html><html><body><p>${PROBE}-${via}</p>${attackerScript(via)}</body></html>`;
}

function attackerErrorMessage(via: string): string {
  return `${PROBE}-${via}</h3>${attackerScript(via)}<h3>`;
}

function iframe(id: string, generationData: Record<string, unknown>): SceneElement {
  return element({
    id,
    type: "iframe",
    x: 120,
    y: 120,
    width: 480,
    height: 320,
    customData: { generationData },
  });
}

function scene(elements: SceneElement[], type: string | undefined = "excalidraw"): string {
  const body: Record<string, unknown> = {
    version: 2,
    source: "https://example.invalid",
    elements,
    appState: { viewBackgroundColor: "#ffffff", gridSize: 20 },
    files: {},
  };
  if (type !== undefined) body.type = type;
  return JSON.stringify(body);
}

async function openEditor(page: Page) {
  await page.addInitScript((probe) => {
    const win = window as unknown as {
      webkit: { messageHandlers: { macdraw: { postMessage: () => void } } };
      __probes: unknown[];
    };
    win.webkit = { messageHandlers: { macdraw: { postMessage() {} } } };
    win.__probes = [];
    window.addEventListener("message", (event) => {
      const data = event.data as { k?: string } | null;
      if (data && data.k === probe) win.__probes.push(data);
    });
  }, PROBE);
  await page.goto("/");
  await page.waitForFunction(() => typeof window.macdraw?.load === "function");
}

async function loadScene(page: Page, sceneJSON: string) {
  await page.evaluate((json) => window.macdraw.load(json, null), sceneJSON);
}

async function waitForOutcome(page: Page, safeText: string) {
  await page.waitForFunction(
    (safe) => {
      try {
        return window.macdraw.serialize().includes(safe);
      } catch {
        return false;
      }
    },
    safeText,
    { timeout: 20_000 },
  );
  await page
    .waitForFunction(
      (probe) => {
        const win = window as unknown as { __probes?: unknown[] };
        if ((win.__probes ?? []).length > 0) return true;
        return [...document.querySelectorAll("iframe")].some((frame) =>
          (frame.getAttribute("srcdoc") ?? "").includes(probe),
        );
      },
      PROBE,
      { timeout: 4_000 },
    )
    .catch(() => undefined);
}

type Observation = {
  probes: { via?: string }[];
  frames: { srcdoc: string; sandbox: string; allow: string; src: string }[];
  serialized: string;
  childFrames: { url: string; probe: string | null; body: string | null }[];
};

async function observe(page: Page): Promise<Observation> {
  const dom = await page.evaluate(() => {
    const win = window as unknown as { __probes?: { via?: string }[] };
    return {
      probes: win.__probes ?? [],
      frames: [...document.querySelectorAll("iframe")].map((frame) => ({
        srcdoc: frame.getAttribute("srcdoc") ?? "",
        sandbox: frame.getAttribute("sandbox") ?? "",
        allow: frame.getAttribute("allow") ?? "",
        src: frame.getAttribute("src") ?? "",
      })),
      serialized: window.macdraw.serialize(),
    };
  });
  const childFrames = [];
  for (const frame of page.frames()) {
    if (frame === page.mainFrame()) continue;
    try {
      const info = await frame.evaluate(() => ({
        probe: document.documentElement.dataset.macdrawProbe ?? null,
        body: document.body?.innerText ?? "",
      }));
      childFrames.push({ url: frame.url(), ...info });
    } catch {
      childFrames.push({ url: frame.url(), probe: null, body: null });
    }
  }
  return { ...dom, childFrames };
}

function expectFileHtmlAbsent(seen: Observation, safeText: string) {
  expect(seen.serialized, "the drawing itself was not loaded").toContain(safeText);
  const executed = [
    ...seen.probes.map((probe) => probe.via ?? "message"),
    ...seen.childFrames.filter((frame) => frame.probe).map((frame) => frame.probe),
  ];
  expect(executed, "file HTML ran inside the editor").toEqual([]);
  const leakedFrames = seen.frames.filter((frame) => frame.srcdoc.includes(PROBE));
  expect(leakedFrames, "file HTML was placed in an iframe srcdoc").toEqual([]);
  expect(seen.serialized, "file HTML remained in the loaded scene").not.toContain(PROBE);
}

test("opening a drawing does not run iframe generation HTML", async ({ page }) => {
  await openEditor(page);
  const opened = scene([
    label("safe-open", "safe-open"),
    iframe("frame-done", { status: "done", html: attackerDocument("open-done") }),
    iframe("frame-error", {
      status: "error",
      message: attackerErrorMessage("open-error"),
    }),
    iframe("frame-unspecified", {
      message: attackerErrorMessage("open-message"),
    }),
  ]);
  await loadScene(page, opened);
  await waitForOutcome(page, "safe-open");
  expectFileHtmlAbsent(await observe(page), "safe-open");
});

test("a JSON object without a type field is still sanitized on open", async ({ page }) => {
  await openEditor(page);
  await loadScene(
    page,
    scene(
      [label("safe-untyped", "safe-untyped"), iframe("frame-untyped", { status: "done", html: attackerDocument("untyped") })],
      undefined,
    ),
  );
  await waitForOutcome(page, "safe-untyped");
  expectFileHtmlAbsent(await observe(page), "safe-untyped");
});

test("reloading a document does not run iframe generation HTML", async ({ page }) => {
  await openEditor(page);
  await loadScene(
    page,
    scene([label("safe-first", "safe-first"), iframe("frame-first", { status: "done", html: attackerDocument("revert-first") })]),
  );
  await waitForOutcome(page, "safe-first");
  await loadScene(
    page,
    scene([label("safe-revert", "safe-revert"), iframe("frame-second", { status: "done", html: attackerDocument("revert-second") })]),
  );
  await waitForOutcome(page, "safe-revert");
  const seen = await observe(page);
  expect(seen.serialized).toContain("safe-revert");
  expect(seen.serialized).not.toContain("safe-first");
  expectFileHtmlAbsent(seen, "safe-revert");
});

test("dropping a drawing on the canvas does not run iframe generation HTML", async ({ page }) => {
  await openEditor(page);
  await loadScene(page, scene([label("safe-before-drop", "safe-before-drop")]));
  await waitForOutcome(page, "safe-before-drop");
  const dropped = scene([
    label("safe-drop", "safe-drop"),
    iframe("frame-drop", { status: "done", html: attackerDocument("drop") }),
  ]);
  await page.evaluate((json) => {
    const transfer = new DataTransfer();
    transfer.items.add(new File([json], "drawing.excalidraw", { type: "application/vnd.excalidraw+json" }));
    const host = document.querySelector(".excalidraw");
    if (!host) throw new Error("editor is not mounted");
    host.dispatchEvent(new DragEvent("drop", { bubbles: true, cancelable: true, dataTransfer: transfer }));
  }, dropped);
  await waitForOutcome(page, "safe-drop");
  const seen = await observe(page);
  expect(seen.serialized).not.toContain("safe-before-drop");
  expectFileHtmlAbsent(seen, "safe-drop");
});

test("pasting diagram elements does not run iframe generation HTML", async ({ page }) => {
  await openEditor(page);
  await loadScene(page, scene([label("safe-before-paste", "safe-before-paste")]));
  await waitForOutcome(page, "safe-before-paste");
  await page.locator(".excalidraw").focus();
  await page.locator("canvas.excalidraw__canvas.interactive").hover({ position: { x: 420, y: 320 } });
  const pasted = JSON.stringify({
    type: "excalidraw/clipboard",
    elements: [label("safe-paste", "safe-paste"), iframe("frame-paste", { status: "done", html: attackerDocument("paste") })],
  });
  await page.evaluate((json) => {
    const transfer = new DataTransfer();
    transfer.setData("text/plain", json);
    const host = document.querySelector(".excalidraw");
    if (!host) throw new Error("editor is not mounted");
    host.focus();
    document.dispatchEvent(new ClipboardEvent("paste", { bubbles: true, cancelable: true, clipboardData: transfer }));
  }, pasted);
  await waitForOutcome(page, "safe-paste");
  const seen = await observe(page);
  expect(seen.serialized).toContain("safe-before-paste");
  expectFileHtmlAbsent(seen, "safe-paste");
});

test("inserting a library item does not run iframe generation HTML", async ({ page }) => {
  await openEditor(page);
  await loadScene(page, scene([label("safe-before-library", "safe-before-library")]));
  await waitForOutcome(page, "safe-before-library");
  const library = JSON.stringify({
    type: "excalidrawlib",
    version: 2,
    libraryItems: [
      {
        id: "lib-item",
        status: "published",
        created: 1,
        elements: [label("safe-library", "safe-library"), iframe("frame-library", { status: "done", html: attackerDocument("library") })],
      },
    ],
  });
  await page.evaluate(async (json) => {
    await window.macdraw.importLibrary(json);
  }, library);
  const item = page.locator(".library-unit__dragger").first();
  await item.waitFor({ state: "visible" });
  await item.click();
  await waitForOutcome(page, "safe-library");
  const seen = await observe(page);
  expect(seen.serialized).toContain("safe-before-library");
  expectFileHtmlAbsent(seen, "safe-library");
});
