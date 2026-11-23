// Web smoke check: the editor must draw a page and a stroke.
//
//   node tool/web_smoke.mjs http://127.0.0.1:7390/ [out.png]
//
// Fresh Chromium profile at 1280x720: "Start without syncing", new notebook,
// page centre must be paper white, then a finger stroke (touch draws by
// default) must leave ink. Exit 0 when all pass. Needs `playwright` (or
// PLAYWRIGHT_CORE pointing at playwright-core).
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_CORE || 'playwright');
const [url, shot = 'web-smoke.png'] = process.argv.slice(2);
if (!url) {
  console.error('usage: node tool/web_smoke.mjs <url> [out.png]');
  process.exit(2);
}

const fail = (msg) => {
  console.error(`web smoke FAILED: ${msg}`);
  process.exitCode = 1;
};

const browser = await chromium.launch({
  args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader'],
});
const page = await browser.newPage({ viewport: { width: 1280, height: 720 }, hasTouch: true });
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
page.on('console', (m) => {
  // A static server answers 501 to a PUT (the ?diag=1 log upload): not an app error.
  if (m.type() === 'error' && !/status of 50[15]/.test(m.text())) errors.push(m.text());
});

// One pixel of the canvas as [r, g, b].
const pixel = async (x, y) => {
  const buf = await page.screenshot({ clip: { x, y, width: 1, height: 1 } });
  const { PNG } = await import('./web_smoke_png.mjs');
  return PNG.firstPixel(buf);
};
const waitFor = async (what, test, ms = 20000) => {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    if (await test()) return true;
    await page.waitForTimeout(500);
  }
  fail(what);
  return false;
};
const isWhite = ([r, g, b]) => r > 250 && g > 250 && b > 250;
const isInk = ([r, g, b]) => r + g + b < 200;

try {
  await page.goto(url, { waitUntil: 'load' });
  // Onboarding: the "Start without syncing" button sits under the two cards.
  await page.waitForTimeout(8000);
  await page.mouse.click(640, 528);
  await page.waitForTimeout(2500);
  // Library: the dashed "New" card, then Create in the dialog.
  await page.mouse.click(380, 530);
  await page.waitForTimeout(1500);
  await page.keyboard.type('Smoke');
  await page.mouse.click(829, 592);
  const drawn = await waitFor('the page is not drawn (centre not white)',
    async () => isWhite(await pixel(640, 300)));
  if (drawn) {
    const cdp = await page.context().newCDPSession(page);
    const touch = (type, x, y) => cdp.send('Input.dispatchTouchEvent', {
      type, touchPoints: type === 'touchEnd' ? [] : [{ x, y }],
    });
    await touch('touchStart', 560, 300);
    for (let i = 1; i <= 20; i++) {
      await touch('touchMove', 560 + i * 8, 300 + (i % 2 ? 6 : -6));
      await page.waitForTimeout(16);
    }
    await touch('touchEnd');
    await waitFor('a finger stroke left no ink', async () => {
      for (let x = 570; x <= 700; x += 4) {
        for (const y of [294, 297, 300, 303, 306]) {
          if (isInk(await pixel(x, y))) return true;
        }
      }
      return false;
    }, 8000);
  }
  if (errors.length) fail(`console errors:\n  ${errors.slice(0, 5).join('\n  ')}`);
} catch (e) {
  fail(String(e));
} finally {
  await page.screenshot({ path: shot });
  await browser.close();
}
if (!process.exitCode) console.log('web smoke OK');
