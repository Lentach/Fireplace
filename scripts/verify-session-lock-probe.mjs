#!/usr/bin/env node
/**
 * Runs the origin-wide Web Lock probe in a real headless browser and fails if
 * it does not pass.
 *
 * WHY THIS EXISTS. The 0.0.126 fix (`fd89e7e`) stops a cross-PWA-engine Signal
 * ratchet race with an origin-wide `navigator.locks` acquisition layered on the
 * process-local per-peer queue. Nothing automated actually exercised that
 * layer: `test/services/session_cross_context_lock_web_test.dart` only runs
 * under `--platform chrome`, and the two-engine race probes inject a FAKE
 * in-memory lock. Production could stop calling `navigator.locks` entirely and
 * the whole suite would stay green.
 *
 * `frontend/tool/session_cross_context_lock_probe.dart` does exercise the real
 * API — it asserts same-name requests queue AND that a missing `navigator.locks`
 * fails closed instead of silently running unlocked. It was a manual runbook
 * step; this makes it a command, so CI can run it.
 *
 * Usage:
 *   node scripts/verify-session-lock-probe.mjs
 *
 * Exits 0 only when the probe page reports SESSION_LOCK_PASS.
 */
import { spawn, spawnSync } from 'child_process';
import { createReadStream, existsSync, mkdtempSync, rmSync, statSync } from 'fs';
import { createServer } from 'http';
import { tmpdir } from 'os';
import { dirname, join, normalize, resolve, sep } from 'path';
import { fileURLToPath } from 'url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const frontend = join(root, 'frontend');
const probePage = '/tool/session_cross_context_lock_probe.html';
const expectedTitle = 'SESSION_LOCK_PASS';
const overallTimeoutMs = 120_000;

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.map': 'application/json; charset=utf-8',
};

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exit(1);
}

function compileProbe() {
  const out = spawnSync(
    'dart',
    [
      'compile',
      'js',
      'tool/session_cross_context_lock_probe.dart',
      '-o',
      'build/session_lock_probe/probe.js',
    ],
    { cwd: frontend, encoding: 'utf8', shell: process.platform === 'win32' },
  );
  if (out.error) fail(`could not run \`dart\`: ${out.error.message}`);
  if (out.status !== 0) {
    fail(`dart compile js failed:\n${out.stdout ?? ''}${out.stderr ?? ''}`);
  }
}

/**
 * Static server rooted at `frontend`, on an ephemeral port (CI reuses ports).
 *
 * Also exposes `/__probe_result?title=...`, which the probe page calls the
 * moment its verdict is known. That is what the runner waits on: `--dump-dom`
 * snapshots at load completion — before the async Web Lock round trip resolves
 * — and `--virtual-time-budget` does not advance real Web Locks, so reading
 * the DOM is a race that always loses.
 */
function startServer() {
  let onResult = () => {};
  const reported = new Promise((ok) => {
    onResult = ok;
  });
  const server = createServer((req, res) => {
    const [rawPath, rawQuery] = (req.url ?? '/').split('?');
    const urlPath = decodeURIComponent(rawPath);
    if (urlPath === '/__probe_result') {
      const title = new URLSearchParams(rawQuery ?? '').get('title') ?? '';
      res.writeHead(204).end();
      onResult(title);
      return;
    }
    const target = normalize(join(frontend, urlPath));
    // Path traversal guard: never serve outside the frontend directory.
    if (target !== frontend && !target.startsWith(frontend + sep)) {
      res.writeHead(403).end('forbidden');
      return;
    }
    if (!existsSync(target) || !statSync(target).isFile()) {
      res.writeHead(404).end('not found');
      return;
    }
    const ext = target.slice(target.lastIndexOf('.'));
    res.writeHead(200, { 'content-type': MIME[ext] ?? 'application/octet-stream' });
    createReadStream(target).pipe(res);
  });
  return new Promise((ok, err) => {
    server.on('error', err);
    server.listen(0, '127.0.0.1', () => ok({ server, reported }));
  });
}

function findChrome() {
  const explicit = process.env.CHROME_EXECUTABLE || process.env.CHROME_PATH;
  const candidates = [
    ...(explicit ? [explicit] : []),
    'google-chrome',
    'google-chrome-stable',
    'chromium',
    'chromium-browser',
    'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
  ];
  for (const candidate of candidates) {
    if (candidate.includes(sep) || candidate.includes('/')) {
      if (existsSync(candidate)) return candidate;
      continue;
    }
    const probe = spawnSync(candidate, ['--version'], { encoding: 'utf8' });
    if (!probe.error && probe.status === 0) return candidate;
  }
  fail(
    `no Chrome found. Set CHROME_EXECUTABLE. Tried:\n  ${candidates.join('\n  ')}`,
  );
}

/** Launch the page and leave it running; the verdict arrives over HTTP. */
function launchChrome(chrome, url, profileDir) {
  const child = spawn(
    chrome,
    [
      '--headless=new',
      '--disable-gpu',
      '--no-sandbox',
      `--user-data-dir=${profileDir}`,
      url,
    ],
    { stdio: ['ignore', 'pipe', 'pipe'] },
  );
  let stderr = '';
  child.stderr.on('data', (d) => (stderr += d));
  const died = new Promise((_, err) => {
    child.on('error', (e) => err(e));
    child.on('close', (code) => {
      if (code !== 0) err(new Error(`Chrome exited ${code}: ${stderr}`));
    });
  });
  return { child, died };
}

function timeout(ms, message) {
  return new Promise((_, err) => {
    // unref: a pending timer must not hold the process open after we already
    // have a verdict.
    setTimeout(() => err(new Error(message)), ms).unref();
  });
}

let server;
let chromeChild;
let profileDir;
try {
  compileProbe();
  const started = await startServer();
  server = started.server;
  profileDir = mkdtempSync(join(tmpdir(), 'fireplace-session-lock-'));
  const { port } = server.address();
  const url = `http://127.0.0.1:${port}${probePage}`;

  const launched = launchChrome(findChrome(), url, profileDir);
  chromeChild = launched.child;

  const title = await Promise.race([
    started.reported,
    launched.died,
    timeout(
      overallTimeoutMs,
      `probe did not report a verdict within ${overallTimeoutMs / 1000}s`,
    ),
  ]);

  if (title.startsWith('SESSION_LOCK_FAIL')) {
    fail(
      `${title}\n` +
        'The origin-wide Web Lock is BROKEN: same-name requests stopped ' +
        'queuing, or a missing navigator.locks stopped failing closed. This ' +
        'is the guard against the cross-engine ratchet race that caused the ' +
        '0.0.126 incident — do not merge past it.',
    );
  }
  if (title === 'SESSION_LOCK_PENDING' || title === '') {
    fail(
      'the probe never reached a verdict (still SESSION_LOCK_PENDING). It ' +
        'hung instead of asserting — a harness or browser problem, not ' +
        'evidence either way about the lock.',
    );
  }
  if (title !== expectedTitle) {
    fail(`probe reported "${title}", expected ${expectedTitle}`);
  }
  console.log(`OK: session lock probe reported ${expectedTitle}`);
} catch (e) {
  fail(e.message);
} finally {
  chromeChild?.kill('SIGKILL');
  server?.close();
  // Best effort: Windows holds the profile dir briefly after Chrome exits, and
  // a leftover temp directory must never turn a passing verification red.
  if (profileDir) {
    try {
      rmSync(profileDir, { recursive: true, force: true, maxRetries: 5 });
    } catch (_) {
      /* the OS will reap it */
    }
  }
}
