// Spec for embedded image addresses in .excalidraw files.
//
// These tests fail while a drawing can make the app request an image address
// that is not an inline data URL. They pass once Quick Look and the editor
// both drop those files before Excalidraw loads them.
//
// Run from web/:
//   node --test test/remote-image-address.test.mjs
//
// The command builds the production bundle (the one the app and Quick Look
// load) and opens it in headless Chrome. Thumbnail and preview extensions
// both hand the file string to window.macdrawRender, so the renderer cases
// cover both. The editor cases call window.macdraw.load and
// window.macdraw.exportImage, which is what opening and exporting a document
// do.

import assert from "node:assert/strict";
import { execFile, spawn } from "node:child_process";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import http from "node:http";
import https from "node:https";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, test, before, after } from "node:test";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const webRoot = path.resolve(import.meta.dirname, "..");
const distDir = path.join(webRoot, "dist");

const PNG = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
  "base64",
);
const DATA_PNG = `data:image/png;base64,${PNG.toString("base64")}`;

const hits = [];

function record(req) {
  hits.push(`${req.socket.encrypted ? "https" : "http"}://${req.headers.host}${req.url}`);
}

function pixelServer(create) {
  const server = create((req, res) => {
    record(req);
    res.writeHead(200, {
      "Content-Type": "image/png",
      "Content-Length": String(PNG.length),
      "Cache-Control": "no-store, no-cache, must-revalidate",
      Pragma: "no-cache",
      "Access-Control-Allow-Origin": "*",
    });
    res.end(PNG);
  });
  return new Promise((resolve) => {
    server.listen(0, "127.0.0.1", () => {
      resolve({ server, port: server.address().port });
    });
  });
}

function staticServer(rootDir) {
  const types = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript",
    ".css": "text/css",
    ".svg": "image/svg+xml",
    ".json": "application/json",
    ".woff2": "font/woff2",
    ".wasm": "application/wasm",
    ".png": "image/png",
  };
  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, "http://127.0.0.1");
    let rel = decodeURIComponent(url.pathname).replace(/^\/+/, "");
    if (rel.endsWith("/") || rel === "") rel += "index.html";
    const file = path.normalize(path.join(rootDir, rel));
    if (!file.startsWith(rootDir + path.sep) && file !== rootDir) {
      res.writeHead(403);
      res.end();
      return;
    }
    try {
      const body = await readFile(file);
      res.writeHead(200, {
        "Content-Type": types[path.extname(file)] || "application/octet-stream",
        "Cache-Control": "no-cache",
      });
      res.end(body);
    } catch {
      res.writeHead(404);
      res.end();
    }
  });
  return new Promise((resolve) => {
    server.listen(0, "127.0.0.1", () => resolve({ server, port: server.address().port }));
  });
}

function scene(dataURL) {
  return JSON.stringify({
    type: "excalidraw",
    version: 2,
    source: "https://excalidraw.com",
    elements: [
      {
        id: "rect-1",
        type: "rectangle",
        x: 0,
        y: 0,
        width: 180,
        height: 90,
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
        boundElements: [],
        updated: 1,
        link: null,
        locked: false,
      },
      {
        id: "image-1",
        type: "image",
        x: 20,
        y: 20,
        width: 100,
        height: 80,
        angle: 0,
        strokeColor: "transparent",
        backgroundColor: "transparent",
        fillStyle: "solid",
        strokeWidth: 1,
        strokeStyle: "solid",
        roughness: 0,
        opacity: 100,
        groupIds: [],
        frameId: null,
        roundness: null,
        seed: 2,
        version: 1,
        versionNonce: 2,
        isDeleted: false,
        boundElements: null,
        updated: 1,
        link: null,
        locked: false,
        status: "saved",
        fileId: "file-1",
        scale: [1, 1],
        crop: null,
      },
    ],
    appState: { viewBackgroundColor: "#ffffff", gridSize: 20 },
    files: {
      "file-1": {
        mimeType: "image/png",
        id: "file-1",
        dataURL,
        created: 1,
        lastRetrieved: 1,
      },
    },
  });
}

const exportOpts = {
  format: "png",
  scale: 1,
  background: true,
  embedScene: false,
  selectionOnly: false,
  darkMode: false,
};

let httpPixel;
let httpsPixel;
let appServer;
let chrome;
let userData;
let debugPort;

function addressesFor(token) {
  const fromServer = hits.filter((hit) => hit.includes(token));
  return fromServer;
}

class Page {
  constructor(ws, id) {
    this.ws = ws;
    this.id = id;
    this.next = 0;
    this.pending = new Map();
    this.requests = [];
    this.console = [];
    ws.addEventListener("message", (event) => {
      const message = JSON.parse(event.data);
      if (message.id && this.pending.has(message.id)) {
        const pending = this.pending.get(message.id);
        this.pending.delete(message.id);
        if (message.error) pending.reject(new Error(message.error.message));
        else pending.resolve(message.result);
        return;
      }
      if (message.method === "Network.requestWillBeSent") {
        this.requests.push(message.params.request.url);
      } else if (message.method === "Runtime.consoleAPICalled") {
        const text = message.params.args.map((arg) => arg.value ?? arg.description ?? "").join(" ");
        this.console.push(text);
      } else if (message.method === "Runtime.exceptionThrown") {
        this.console.push(message.params.exceptionDetails?.exception?.description || "exception");
      } else if (message.method === "Page.loadEventFired" && this._load) {
        this._load();
      }
    });
  }

  send(method, params = {}) {
    const id = ++this.next;
    this.ws.send(JSON.stringify({ id, method, params }));
    return new Promise((resolve, reject) => this.pending.set(id, { resolve, reject }));
  }

  async eval(expression) {
    const result = await this.send("Runtime.evaluate", {
      expression,
      awaitPromise: true,
      returnByValue: true,
    });
    if (result.exceptionDetails) {
      const description = result.exceptionDetails.exception?.description || result.exceptionDetails.text;
      throw new Error(description);
    }
    return result.result?.value;
  }
}

async function openPage(url) {
  const created = await fetch(`http://127.0.0.1:${debugPort}/json/new?${url}`, { method: "PUT" });
  if (!created.ok) throw new Error(`opening a page failed: ${created.status}`);
  const info = await created.json();
  const ws = new WebSocket(info.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    ws.addEventListener("open", resolve, { once: true });
    ws.addEventListener("error", reject, { once: true });
  });
  const page = new Page(ws, info.id);
  await page.send("Network.enable");
  await page.send("Runtime.enable");
  await page.send("Page.enable");
  if (!info.url?.startsWith(url)) {
    const loaded = new Promise((resolve) => {
      page._load = resolve;
    });
    await page.send("Page.navigate", { url });
    await loaded;
  }
  return page;
}

async function closePage(page) {
  page.ws.close();
  await fetch(`http://127.0.0.1:${debugPort}/json/close/${page.id}`).catch(() => {});
}

async function waitFor(fn, timeoutMs, label) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    if (await fn()) return;
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error(`timeout: ${label}`);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function requestsFor(page, token) {
  return [...new Set([...addressesFor(token), ...page.requests.filter((url) => url.includes(token))])];
}

// exportToBlob rejects once a cross-origin image has been painted. The request
// has already been sent by then, so the assertion is on the request itself.
async function renderDrawing(page, dataURL) {
  let result;
  let error;
  try {
    result = await page.eval(`window.macdrawRender(${JSON.stringify(scene(dataURL))}, 256)`);
  } catch (err) {
    error = err;
  }
  await sleep(300);
  return { result, error };
}

describe("embedded image addresses", { concurrency: 1 }, () => {
  before(async () => {
    await execFileAsync("npm", ["run", "build"], { cwd: webRoot, timeout: 180_000 });

    httpPixel = await pixelServer((handler) => http.createServer(handler));
    const certDir = await mkdtemp(path.join(tmpdir(), "macdraw-cert-"));
    const key = path.join(certDir, "key.pem");
    const cert = path.join(certDir, "cert.pem");
    await execFileAsync("openssl", [
      "req",
      "-x509",
      "-newkey",
      "rsa:2048",
      "-keyout",
      key,
      "-out",
      cert,
      "-days",
      "1",
      "-nodes",
      "-subj",
      "/CN=127.0.0.1",
      "-addext",
      "subjectAltName=IP:127.0.0.1",
    ]);
    const tls = { key: await readFile(key), cert: await readFile(cert) };
    httpsPixel = await pixelServer((handler) => https.createServer(tls, handler));
    await rm(certDir, { recursive: true, force: true });
    appServer = await staticServer(distDir);

    userData = await mkdtemp(path.join(tmpdir(), "macdraw-chrome-"));
    chrome = spawn(
      "google-chrome",
      [
        "--headless=new",
        "--disable-gpu",
        "--no-sandbox",
        "--disable-dev-shm-usage",
        "--no-first-run",
        "--no-default-browser-check",
        "--allow-insecure-localhost",
        "--ignore-certificate-errors",
        "--remote-allow-origins=*",
        "--window-size=1280,800",
        `--user-data-dir=${userData}`,
        "--remote-debugging-port=0",
        "about:blank",
      ],
      { stdio: "ignore", detached: true },
    );
    const portFile = path.join(userData, "DevToolsActivePort");
    const started = Date.now();
    while (Date.now() - started < 20_000) {
      try {
        const text = await readFile(portFile, "utf8");
        debugPort = Number(text.split("\n")[0]);
        if (debugPort) break;
      } catch {
        await sleep(50);
      }
    }
    if (!debugPort) throw new Error("Chrome did not open a debugging port");
  }, { timeout: 240_000 });

  after(async () => {
    if (chrome?.pid) {
      try {
        process.kill(-chrome.pid, "SIGKILL");
      } catch {
        chrome.kill("SIGKILL");
      }
    }
    await sleep(200);
    httpPixel?.server.close();
    httpsPixel?.server.close();
    appServer?.server.close();
    if (userData) await rm(userData, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
  });

  test("an inline data URL still renders and does not contact another host", async () => {
    const page = await openPage(`http://127.0.0.1:${appServer.port}/render.html`);
    try {
      await waitFor(() => page.eval(`typeof window.macdrawRender === "function"`), 20_000, "renderer");
      const before = hits.length;
      const png = await page.eval(`window.macdrawRender(${JSON.stringify(scene(DATA_PNG))}, 256)`);
      assert.equal(typeof png, "string");
      assert.ok(png.startsWith("iVBORw0KGgo"), "renderer did not return a PNG");
      await sleep(300);
      assert.deepEqual(hits.slice(before), []);
    } finally {
      await closePage(page);
    }
  });

  test("Quick Look renderer does not request an https image address", async () => {
    const token = `/pixel/quicklook-https-${Date.now()}`;
    const address = `https://127.0.0.1:${httpsPixel.port}${token}`;
    const page = await openPage(`http://127.0.0.1:${appServer.port}/render.html`);
    try {
      await waitFor(() => page.eval(`typeof window.macdrawRender === "function"`), 20_000, "renderer");
      const { result, error } = await renderDrawing(page, address);
      assert.deepEqual(requestsFor(page, token), [], `Quick Look requested ${address}`);
      if (error) throw error;
      assert.equal(typeof result, "string", "renderer should still return the rest of the drawing");
    } finally {
      await closePage(page);
    }
  });

  test("Quick Look renderer does not request an http image address", async () => {
    const token = `/pixel/quicklook-http-${Date.now()}`;
    const address = `http://127.0.0.1:${httpPixel.port}${token}`;
    const page = await openPage(`http://127.0.0.1:${appServer.port}/render.html`);
    try {
      await waitFor(() => page.eval(`typeof window.macdrawRender === "function"`), 20_000, "renderer");
      const { error } = await renderDrawing(page, address);
      assert.deepEqual(requestsFor(page, token), [], `Quick Look requested ${address}`);
      if (error) throw error;
    } finally {
      await closePage(page);
    }
  });

  test("Quick Look renderer does not resolve a protocol-relative image address", async () => {
    const token = `/pixel/quicklook-protocol-relative-${Date.now()}`;
    const address = `//127.0.0.1:${httpPixel.port}${token}`;
    const page = await openPage(`http://127.0.0.1:${appServer.port}/render.html`);
    try {
      await waitFor(() => page.eval(`typeof window.macdrawRender === "function"`), 20_000, "renderer");
      const { error } = await renderDrawing(page, address);
      assert.deepEqual(requestsFor(page, token), [], `Quick Look requested ${address}`);
      if (error) throw error;
    } finally {
      await closePage(page);
    }
  });

  test("opening a drawing in the editor does not request its image address", async () => {
    const token = `/pixel/editor-load-${Date.now()}`;
    const address = `https://127.0.0.1:${httpsPixel.port}${token}`;
    const page = await openPage(`http://127.0.0.1:${appServer.port}/index.html`);
    try {
      await waitFor(() => page.eval(`typeof window.macdraw?.load === "function"`), 30_000, "editor");
      await page.eval(`window.macdraw.load(${JSON.stringify(scene(address))}, null); true`);
      await waitFor(
        () => page.eval(`window.macdraw.exportInfo().isEmpty === false`),
        30_000,
        "editor scene",
      );
      await sleep(500);
      assert.deepEqual(requestsFor(page, token), [], `the editor requested ${address}`);
    } finally {
      await closePage(page);
    }
  });

  test("exporting PNG does not request an image address stored in the drawing", async () => {
    const token = `/pixel/editor-export-png-${Date.now()}`;
    const address = `https://127.0.0.1:${httpsPixel.port}${token}`;
    const page = await openPage(`http://127.0.0.1:${appServer.port}/index.html`);
    try {
      await waitFor(() => page.eval(`typeof window.macdraw?.load === "function"`), 30_000, "editor");
      await page.eval(`window.macdraw.load(${JSON.stringify(scene(address))}, null); true`);
      await waitFor(
        () => page.eval(`window.macdraw.exportInfo().isEmpty === false`),
        30_000,
        "editor scene",
      );
      await sleep(500);
      let png;
      let error;
      try {
        png = await page.eval(
          `window.macdraw.exportImage(${JSON.stringify({ ...exportOpts, format: "png" })})`,
        );
      } catch (err) {
        error = err;
      }
      await sleep(300);
      assert.deepEqual(requestsFor(page, token), [], `PNG export requested ${address}`);
      if (error) throw error;
      assert.equal(typeof png, "string");
      assert.ok(png.startsWith("iVBORw0KGgo"), "export did not return a PNG");
    } finally {
      await closePage(page);
    }
  });

  test("exporting SVG does not embed or request an image address stored in the drawing", async () => {
    const token = `/pixel/editor-export-svg-${Date.now()}`;
    const address = `https://127.0.0.1:${httpsPixel.port}${token}`;
    const page = await openPage(`http://127.0.0.1:${appServer.port}/index.html`);
    try {
      await waitFor(() => page.eval(`typeof window.macdraw?.load === "function"`), 30_000, "editor");
      await page.eval(`window.macdraw.load(${JSON.stringify(scene(address))}, null); true`);
      await waitFor(
        () => page.eval(`window.macdraw.exportInfo().isEmpty === false`),
        30_000,
        "editor scene",
      );
      await sleep(500);
      const svg = await page.eval(
        `window.macdraw.exportImage(${JSON.stringify({ ...exportOpts, format: "svg" })})`,
      );
      assert.equal(typeof svg, "string");
      assert.ok(!svg.includes(token), `SVG export embedded ${address}`);
      await sleep(300);
      assert.deepEqual(requestsFor(page, token), [], `the editor requested ${address}`);
    } finally {
      await closePage(page);
    }
  });
});
