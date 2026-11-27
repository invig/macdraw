// Renders an .excalidraw scene with the real @excalidraw/excalidraw 0.18.1 bundle.
// Confirms generation HTML is placed in a scriptable iframe without a click.
// Whether that navigation reaches Launch Services is the navigation-policy suite
// (tests/run.sh). Embeddable links outside the built-in domain list must not
// become an iframe.
import { createServer } from "node:http";
import { cp, mkdir, mkdtemp, readFile, rm, symlink } from "node:fs/promises";
import { spawn } from "node:child_process";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const web = path.join(root, "web");
const chromeBin = process.env.CHROME || "google-chrome";

const out = await mkdtemp(path.join(tmpdir(), "macdraw-iframe-"));
const stage = path.join(out, "stage");
const dist = path.join(out, "dist");
await mkdir(stage);
await cp(path.join(root, "tests/iframe/index.html"), path.join(stage, "index.html"));
await cp(path.join(root, "tests/iframe/main.jsx"), path.join(stage, "main.jsx"));
await symlink(path.join(web, "node_modules"), path.join(stage, "node_modules"));
const { build } = await import(pathToFileURL(path.join(web, "node_modules/vite/dist/node/index.js")).href);
const react = (await import(pathToFileURL(path.join(web, "node_modules/@vitejs/plugin-react/dist/index.js")).href)).default;
await build({
  root: stage,
  configFile: false,
  plugins: [react()],
  build: { outDir: dist, emptyOutDir: true },
  logLevel: "info",
});

const server = createServer(async (req, res) => {
  const url = new URL(req.url, "http://127.0.0.1");
  let rel = decodeURIComponent(url.pathname);
  if (rel.endsWith("/")) rel += "index.html";
  const file = path.normalize(path.join(dist, rel));
  if (!file.startsWith(dist)) {
    res.writeHead(403);
    res.end("no");
    return;
  }
  try {
    const body = await readFile(file);
    const type = file.endsWith(".js")
      ? "text/javascript"
      : file.endsWith(".css")
        ? "text/css"
        : "text/html; charset=utf-8";
    res.writeHead(200, { "content-type": type });
    res.end(body);
  } catch {
    res.writeHead(404);
    res.end("missing");
  }
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const port = server.address().port;
const origin = `http://127.0.0.1:${port}`;

let failures = 0;
function check(name, ok, detail) {
  if (ok) console.log(`PASS ${name}`);
  else {
    failures += 1;
    console.log(`FAIL ${name} ${detail}`);
  }
}

const profile = await mkdtemp(path.join(tmpdir(), "macdraw-chrome-"));
const chrome = spawn(chromeBin, [
  "--headless=new",
  "--disable-gpu",
  "--no-sandbox",
  "--disable-dev-shm-usage",
  `--remote-debugging-port=0`,
  `--user-data-dir=${profile}`,
  "--window-size=1280,820",
  "about:blank",
], { stdio: "ignore" });

try {
  const debugPort = await readDebugPort(profile);
  const done = await inspect(`${origin}/?case=done`, debugPort);
  check(
    "generationHTMLIsRestored",
    done.restored?.status === "done" && done.restored.html.includes("https://attacker.example/from-iframe"),
    JSON.stringify(done.restored)?.slice(0, 300),
  );
  check(
    "generationHTMLRendersScriptableIframe",
    !!done.iframe &&
      done.iframe.sandbox.includes("allow-scripts") &&
      done.iframe.sandbox.includes("allow-popups") &&
      done.iframe.sandbox.includes("allow-popups-to-escape-sandbox") &&
      done.iframe.srcdoc.includes("location.assign") &&
      done.iframe.srcdoc.includes("https://attacker.example/from-iframe"),
    JSON.stringify(done.iframe)?.slice(0, 500),
  );
  check(
    "generationScriptRunsWithoutAClick",
    done.messages.some((m) => m && m.macdrawTest === "done-script"),
    JSON.stringify(done.messages),
  );
  const errorCase = await inspect(`${origin}/?case=error`, debugPort);
  check(
    "errorMessageRendersScriptableIframe",
    !!errorCase.iframe &&
      errorCase.iframe.sandbox.includes("allow-scripts") &&
      errorCase.iframe.srcdoc.includes("https://attacker.example/from-error"),
    JSON.stringify(errorCase.iframe)?.slice(0, 500),
  );
  const embed = await inspect(`${origin}/?case=embed`, debugPort);
  const embedSrc = embed.iframe?.src ?? "";
  check(
    "disallowedEmbeddableLinkIsNotFramed",
    embed.restoredType === "embeddable" &&
      embed.restoredLink === "https://attacker.example/not-allowed" &&
      !embedSrc.includes("attacker.example"),
    `type=${embed.restoredType} link=${embed.restoredLink} src=${embedSrc}`,
  );
} finally {
  chrome.kill("SIGKILL");
  server.close();
  await new Promise((r) => setTimeout(r, 200));
  await rm(out, { recursive: true, force: true }).catch(() => {});
  await rm(profile, { recursive: true, force: true }).catch(() => {});
}

console.log(failures === 0 ? "IFRAME ALL PASSED" : `${failures} IFRAME FAILED`);
process.exit(failures === 0 ? 0 : 1);

async function readDebugPort(dir) {
  const file = path.join(dir, "DevToolsActivePort");
  for (let i = 0; i < 50; i++) {
    try {
      const text = await readFile(file, "utf8");
      const port = text.split("\n")[0];
      if (port) return Number(port);
    } catch {}
    await new Promise((r) => setTimeout(r, 100));
  }
  throw new Error("Chrome did not open a DevTools port");
}

async function inspect(url, debugPort) {
  const list = await (await fetch(`http://127.0.0.1:${debugPort}/json/list`)).json();
  const page = list.find((t) => t.type === "page");
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    ws.addEventListener("open", resolve);
    ws.addEventListener("error", reject);
  });
  const client = cdp(ws);
  const requests = [];
  client.on((msg) => {
    if (msg.method === "Network.requestWillBeSent") requests.push(msg.params.request.url);
    if (msg.method === "Page.frameNavigated") requests.push(msg.params.frame?.url || "");
  });
  await client.send("Network.enable");
  await client.send("Page.enable");
  await client.send("Runtime.enable");
  await client.send("Page.navigate", { url });
  const exceptions = [];
  client.on((msg) => {
    if (msg.method === "Runtime.exceptionThrown") {
      exceptions.push(msg.params.exceptionDetails?.text || "exception");
    }
    if (msg.method === "Runtime.consoleAPICalled") {
      const text = (msg.params.args || []).map((arg) => arg.value ?? arg.description ?? "").join(" ");
      exceptions.push(`console:${text}`);
    }
  });
  let snapshot = null;
  for (let i = 0; i < 40; i++) {
    await new Promise((r) => setTimeout(r, 250));
    snapshot = await client.send("Runtime.evaluate", {
      expression: `({
        restored: window.__restoredGeneration ?? null,
        restoredType: window.__restoredType ?? null,
        restoredLink: window.__restoredLink ?? null,
        messages: window.__macdrawMessages ?? [],
        iframe: (() => {
          const frame = document.querySelector("iframe.excalidraw__embeddable");
          if (!frame) return null;
          const box = frame.getBoundingClientRect();
          return {
            sandbox: frame.getAttribute("sandbox") || "",
            srcdoc: frame.srcdoc || "",
            src: frame.src || "",
            display: getComputedStyle(frame).display,
            width: box.width,
            height: box.height,
          };
        })()
      })`,
      returnByValue: true,
    });
    const value = snapshot.result?.value;
    const sawNav = requests.some((u) => u.includes("attacker.example"));
    const sawLater = (value?.messages || []).some((m) => m && (m.macdrawTest === "href-later" || m.macdrawTest === "error-assign-returned"));
    if (sawNav || (sawLater && i > 4)) break;
    if (value?.restoredType === "embeddable" && i > 8) break;
  }
  if (snapshot?.result?.value) snapshot.result.value.exceptions = exceptions;
  ws.close();
  const value = snapshot?.result?.value ?? {};
  return { ...value, requests };
}

function cdp(ws) {
  let next = 0;
  const pending = new Map();
  const listeners = [];
  ws.addEventListener("message", (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pending.has(msg.id)) {
      pending.get(msg.id)(msg);
      pending.delete(msg.id);
    } else listeners.forEach((fn) => fn(msg));
  });
  return {
    on(fn) { listeners.push(fn); },
    send(method, params = {}) {
      const id = ++next;
      return new Promise((resolve, reject) => {
        pending.set(id, (msg) => (msg.error ? reject(new Error(JSON.stringify(msg.error))) : resolve(msg.result)));
        ws.send(JSON.stringify({ id, method, params }));
      });
    },
  };
}
