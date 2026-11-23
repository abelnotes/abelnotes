// Serves a built bench (tool/web_circuit_bench.sh, tool/web_abnn_bench.sh) on
// 127.0.0.1, opens it in headless Chromium and prints its report; exit 1 on
// any mismatch. Second argument: the report's tag (CIRCUIT, default, or ABNN).
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { extname, join, normalize } from 'node:path';

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_CORE || 'playwright');
const root = process.argv[2];
const tag = `${process.argv[3] || 'CIRCUIT'}_BENCH `;
const types = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json' };
const server = createServer(async (req, res) => {
  let path = normalize(decodeURIComponent(new URL(req.url, 'http://x').pathname)).replace(/^(\.\.[/\\])+/, '');
  if (path.endsWith('/')) path += 'index.html';
  try {
    const body = await readFile(join(root, path));
    res.writeHead(200, { 'content-type': types[extname(path)] || 'application/octet-stream' });
    res.end(body);
  } catch {
    res.writeHead(404);
    res.end();
  }
}).listen(0, '127.0.0.1');
await new Promise((r) => server.once('listening', r));
const url = `http://127.0.0.1:${server.address().port}/`;

const browser = await chromium.launch();
const page = await browser.newPage();
const report = new Promise((resolve) => {
  page.on('console', (m) => {
    const t = m.text();
    if (t.startsWith(tag)) resolve(JSON.parse(t.slice(tag.length)));
  });
});
page.on('pageerror', (e) => console.error('pageerror', String(e)));
if (process.env.BENCH_DEBUG) page.on('console', (m) => console.error('console', m.text().slice(0, 200)));
await page.goto(url);
const r = await Promise.race([report, new Promise((_, no) => setTimeout(() => no(new Error('timeout')), 900000).unref())]);
await browser.close();
server.closeAllConnections();
server.close();

console.log(JSON.stringify(r, null, 1));
const bad = tag === 'ABNN_BENCH '
  ? r.error || r.mismatches.length > 0 || r.featWorstRel > 1e-5 || r.probWorstVsNative > 1e-5 || r.ocrProbWorst > 1e-5
  : r.error || !r.wasm || !r.worker || r.cases.some((c) =>
  c.sameResult === false || c.sameWorker === false || c.sameDetections === false || c.traceSame === false || c.rasterSame === false ||
  c.leftoverSame === false || c.forwardWorstRel > 1e-3);
process.exitCode = bad ? 1 : 0;
