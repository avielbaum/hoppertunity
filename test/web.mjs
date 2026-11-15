// Does the web build draw anything in a browser? Run after exporting to build/web:
//   node test/web.mjs [path to chrome]        (Node 22+: it uses the built-in WebSocket)
// It serves build/web, opens "?stress" (the largest floor, every tile a conveyor) in headless Chrome with software WebGL,
// waits, and then checks three things: the page logged no script error, the game reported its frame rate (so the main
// loop is running), and a screenshot of the middle of the view is not one flat colour. That last check is crude (it
// compares the PNG's size, since a flat picture compresses to almost nothing), but it is exactly what went wrong twice:
// a few hundred Label3D nodes made the browser build draw no 3D at all while the desktop build was fine.
// Exit code 0: passed, or the browser has no WebGL 2 here (said so, nothing proven). 1: failed.
import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { readFile, mkdtemp, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, extname, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const web = join(dirname(fileURLToPath(import.meta.url)), "..", "build", "web");
const chromePath = process.argv[2] || ["/usr/bin/google-chrome", "/usr/bin/chromium-browser", "/usr/bin/chromium",
  "C:/Program Files/Google/Chrome/Application/chrome.exe"].find(existsSync);
const types = { ".html": "text/html", ".js": "text/javascript", ".wasm": "application/wasm", ".png": "image/png" };
const server = createServer(async (req, res) => {
  const name = req.url.split("?")[0] === "/" ? "index.html" : req.url.split("?")[0].slice(1);
  let body;
  try { body = await readFile(join(web, name)); } catch { return res.writeHead(404).end(); }
  res.writeHead(200, { "Content-Type": types[extname(name)] || "application/octet-stream" }).end(body);
}).listen(0);
const url = `http://127.0.0.1:${server.address().port}/?stress`;
const chrome = spawn(chromePath, ["--headless=new", "--no-sandbox", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
  "--remote-debugging-port=9334", "--user-data-dir=" + await mkdtemp(join(tmpdir(), "hop-web-")), "--window-size=1280,720", url]);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const finish = (code, text) => { console.log(text); chrome.kill(); server.close(); process.exit(code); };
setTimeout(() => finish(1, "FAIL the browser did not answer in 3 minutes"), 180000);

let page;
for (let i = 0; i < 60 && !page; i++) {
  await sleep(500);
  try { page = (await (await fetch("http://127.0.0.1:9334/json")).json()).find((t) => t.type === "page"); } catch {}
}
if (!page) finish(1, "FAIL could not reach Chrome at " + chromePath);
const ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((r) => (ws.onopen = r));
const log = [];
const waiting = new Map();
let nextId = 0;
const send = (method, params = {}) => new Promise((r) => { waiting.set(++nextId, r); ws.send(JSON.stringify({ id: nextId, method, params })); });
ws.onmessage = (m) => {
  const d = JSON.parse(m.data);
  if (d.method === "Runtime.consoleAPICalled") log.push(d.params.args.map((a) => a.value ?? a.description ?? "").join(" "));
  if (d.id && waiting.has(d.id)) waiting.get(d.id)(d.result ?? d);
};
await send("Runtime.enable");

// the game writes "<n> fps, <n> buildings" into its top bar in stress mode; it also prints it once a second for this test
let fps = "";
for (let i = 0; i < 100 && !fps; i++) {
  await sleep(1000);
  fps = log.find((l) => l.startsWith("STRESS ")) || "";
  if (log.some((l) => /WebGL 2|WebGL2/i.test(l) && /not|unavailable|error/i.test(l))) finish(0, "SKIP this browser has no WebGL 2: nothing proven\n" + log.join("\n"));
}
// only the middle of the page, well clear of the bars at the top and bottom, whose text would hide a blank 3D view
const view = (await send("Page.getLayoutMetrics")).cssVisualViewport;
const clip = { x: view.clientWidth * 0.3, y: view.clientHeight * 0.3, width: view.clientWidth * 0.4, height: view.clientHeight * 0.3, scale: 1 };
const shot = await send("Page.captureScreenshot", { format: "png", clip });
const bytes = Buffer.from(shot.data || "", "base64");
if (process.argv[3]) await writeFile(process.argv[3], bytes);
const errors = log.filter((l) => /SCRIPT ERROR|Parse Error/.test(l));
console.log(fps || "(no STRESS line)", "| screenshot of the middle:", bytes.length, "bytes | script errors:", errors.length);
if (errors.length) finish(1, "FAIL script errors in the browser:\n" + errors.join("\n"));
if (!fps) finish(1, "FAIL the game never reported a frame: its main loop is not running\n" + log.slice(-10).join("\n"));
if (bytes.length < 6000) finish(1, "FAIL the middle of the view is (nearly) one flat colour: the 3D view is not being drawn");
finish(0, "ok   the browser build runs its main loop and draws the full floor");
