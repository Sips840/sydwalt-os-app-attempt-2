/* Runs assets/bridge.js in headless Chromium, with a stand-in for the
 * flutter_inappwebview JavaScript channel, and replays the exact patterns the
 * Sydwalt OS web app uses (copied from its source, with file references), so
 * a change to the bridge cannot silently break exports, printing or links.
 *
 *   cd test_js && npm ci && npx playwright install chromium && npm test
 */
import { test, before, after, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const bridge = readFileSync(fileURLToPath(new URL('../assets/bridge.js', import.meta.url)), 'utf8');

let server, origin, browser, page;

before(async () => {
  server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://x');
    if (url.pathname === '/') {
      res.writeHead(200, { 'Content-Type': 'text/html' });
      res.end('<!doctype html><title>Sydwalt OS</title><body><a id="plain" href="/#/projects">Projects</a></body>');
    } else if (url.pathname === '/api/files/f1') {
      if (url.searchParams.get('token') !== 'good') { res.writeHead(403); res.end('no'); return; }
      res.writeHead(200, { 'Content-Type': 'application/pdf', 'Content-Disposition': "inline; filename*=UTF-8''Tender%20pack.pdf" });
      res.end('%PDF-1.4 fake');
    } else {
      res.writeHead(404); res.end('missing');
    }
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  origin = `http://127.0.0.1:${server.address().port}`;
  browser = await chromium.launch();
});

after(async () => {
  await browser?.close();
  await new Promise((r) => server.close(r));
});

/** A page with the bridge injected first, like the app's AT_DOCUMENT_START
 *  user script, and the native channel recording every call. */
async function openPage({ channelReady = true } = {}) {
  page = await browser.newPage();
  await page.addInitScript(bridge);
  await page.addInitScript((ready) => {
    window.__calls = [];
    window.__installChannel = () => {
      window.flutter_inappwebview = {
        callHandler: (name, payload) => {
          window.__calls.push({ name, payload });
          return Promise.resolve({ ok: true });
        },
      };
      window.dispatchEvent(new Event('flutterInAppWebViewPlatformReady'));
    };
    if (ready) window.__installChannel();
  }, channelReady);
  await page.goto(origin + '/');
}

const calls = (name) => page.evaluate((n) => window.__calls.filter((c) => !n || c.name === n), name);

async function waitForCall(name) {
  await page.waitForFunction((n) => window.__calls.some((c) => c.name === n), name, { timeout: 5000 });
  return (await calls(name)).at(-1).payload;
}

const decode = (b64) => Buffer.from(b64, 'base64').toString('utf8');

beforeEach(() => openPage());
afterEach(() => page?.close());

test('company book export: detached anchor, blob revoked straight after click (app.js)', async () => {
  await page.evaluate(() => {
    const blob = new Blob([JSON.stringify({ db: { actions: [1, 2] } })], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'sydwalt-os-company-book-server-2026-10-20.json';
    document.body.appendChild(a); a.click(); a.remove();
    URL.revokeObjectURL(url);
  });
  const p = await waitForCall('download');
  assert.equal(p.name, 'sydwalt-os-company-book-server-2026-10-20.json');
  assert.equal(p.mime, 'application/json');
  assert.deepEqual(JSON.parse(decode(p.base64)), { db: { actions: [1, 2] } });
  const started = await calls('downloadStarted');
  assert.equal(started.length, 1);
  assert.equal(started[0].payload.token, p.token);
});

test('a revoked blob is still saved when the engine resolves blob URLs late (iOS WebKit)', async () => {
  /* Chromium resolves a blob: URL the moment fetch() starts, which hides the
     problem; WebKit may resolve it later, after the app has already revoked
     it. Delay fetch to reproduce that ordering. */
  await page.evaluate(() => {
    const realFetch = window.fetch;
    window.fetch = (...args) => new Promise((r) => setTimeout(r, 50)).then(() => realFetch(...args));
    const url = URL.createObjectURL(new Blob(['late'], { type: 'text/plain' }));
    const a = document.createElement('a');
    a.href = url; a.download = 'late.txt';
    a.click();
    URL.revokeObjectURL(url);
  });
  const p = await waitForCall('download');
  assert.equal(decode(p.base64), 'late');
});

test('CSV export on a never-attached anchor (tabs/minutes.js)', async () => {
  await page.evaluate(() => {
    const link = document.createElement('a');
    link.href = URL.createObjectURL(new Blob(['﻿a,b\n1,2\n'], { type: 'text/csv' }));
    link.download = 'resolutions-log-2026-10-20.csv';
    link.click();
  });
  const p = await waitForCall('download');
  assert.equal(p.name, 'resolutions-log-2026-10-20.csv');
  assert.equal(decode(p.base64), '﻿a,b\n1,2\n');
  assert.equal(p.size, 11);
});

test('uploaded document download uses the same-origin file URL (tabs/documents.js)', async () => {
  await page.evaluate(() => {
    const a = document.createElement('a');
    a.href = '/api/files/f1?token=good'; a.download = 'Tender pack v2.pdf';
    document.body.append(a); a.click(); a.remove();
  });
  const p = await waitForCall('download');
  assert.equal(p.name, 'Tender pack v2.pdf');
  assert.equal(p.mime, 'application/pdf');
  assert.equal(decode(p.base64), '%PDF-1.4 fake');
});

test('an empty download attribute takes the name from Content-Disposition', async () => {
  await page.evaluate(() => {
    const a = document.createElement('a');
    a.href = '/api/files/f1?token=good'; a.setAttribute('download', '');
    a.click();
  });
  const p = await waitForCall('download');
  assert.equal(p.name, 'Tender pack.pdf');
});

test('a failed fetch reports downloadFailed with the status, not a silent nothing', async () => {
  await page.evaluate(() => {
    const a = document.createElement('a');
    a.href = '/api/files/f1?token=bad'; a.download = 'x.pdf';
    a.click();
  });
  const p = await waitForCall('downloadFailed');
  assert.match(p.message, /403/);
  assert.equal((await calls('download')).length, 0);
});

test('a real tap on a download link is intercepted and does not navigate', async () => {
  await page.evaluate(() => {
    const a = document.createElement('a');
    a.id = 'dl'; a.textContent = 'Download';
    a.href = URL.createObjectURL(new Blob(['hello'], { type: 'text/plain' }));
    a.download = 'note.txt';
    document.body.append(a);
  });
  await page.click('#dl');
  const p = await waitForCall('download');
  assert.equal(decode(p.base64), 'hello');
  assert.equal(page.url(), origin + '/');
});

test('a cross-origin download link opens externally instead', async () => {
  await page.evaluate(() => {
    const a = document.createElement('a');
    a.href = 'https://example.com/file.pdf'; a.download = 'file.pdf';
    a.click();
  });
  const p = await waitForCall('openUrl');
  assert.equal(p.url, 'https://example.com/file.pdf');
  assert.equal((await calls('downloadStarted')).length, 0);
});

test('window.open of a file goes to the app with an absolute URL (tabs/documents.js)', async () => {
  const ret = await page.evaluate(() => window.open('/api/files/f1?token=good&inline=1', '_blank', 'noopener'));
  assert.equal(ret, null);
  const p = await waitForCall('openUrl');
  assert.equal(p.url, origin + '/api/files/f1?token=good&inline=1');
});

test('target=_blank links are routed through the app (app.js tender notes)', async () => {
  await page.evaluate(() => {
    const a = document.createElement('a');
    a.id = 'nt'; a.href = '/api/files/f1?token=good'; a.target = '_blank'; a.rel = 'noopener'; a.textContent = 'open';
    document.body.append(a);
  });
  await page.click('#nt');
  const p = await waitForCall('openUrl');
  assert.equal(p.url, origin + '/api/files/f1?token=good');
  assert.equal(page.url(), origin + '/');
});

test('plain in-app links and links the app already handled are left alone', async () => {
  await page.evaluate(() => {
    const a = document.createElement('a');
    a.id = 'handled'; a.href = '/x'; a.target = '_blank'; a.textContent = 'x';
    a.addEventListener('click', (e) => e.preventDefault());
    document.body.append(a);
  });
  await page.click('#handled');
  await page.click('#plain');
  await page.waitForFunction(() => location.hash === '#/projects');
  assert.equal((await calls()).length, 0);
});

test('window.print goes to the native dialog and still fires beforeprint/afterprint (tabs/controls.js)', async () => {
  await page.evaluate(() => {
    window.__events = [];
    window.addEventListener('beforeprint', () => window.__events.push('before'));
    window.addEventListener('afterprint', () => window.__events.push('after'));
    document.title = 'Board report 2026-10-20';
    window.print();
  });
  const p = await waitForCall('print');
  assert.equal(p.title, 'Board report 2026-10-20');
  await page.waitForFunction(() => window.__events.length === 2);
  assert.deepEqual(await page.evaluate(() => window.__events), ['before', 'after']);
});

test('calls made before the native channel is ready are delivered once it is', async () => {
  await page.close();
  await openPage({ channelReady: false });
  await page.evaluate(() => {
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob(['early'])); a.download = 'early.txt';
    a.click();
  });
  await page.evaluate(() => new Promise((r) => setTimeout(r, 100)));
  assert.equal(await page.evaluate(() => window.__calls.length), 0);
  await page.evaluate(() => window.__installChannel());
  const p = await waitForCall('download');
  assert.equal(decode(p.base64), 'early');
});

test('injecting the bridge twice does not double-handle downloads', async () => {
  await page.evaluate((src) => { (0, eval)(src); }, bridge);
  await page.evaluate(() => {
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob(['once'])); a.download = 'once.txt';
    a.click();
  });
  await waitForCall('download');
  await page.evaluate(() => new Promise((r) => setTimeout(r, 100)));
  assert.equal((await calls('download')).length, 1);
});
