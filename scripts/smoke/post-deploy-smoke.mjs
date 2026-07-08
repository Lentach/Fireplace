#!/usr/bin/env node
// Post-deploy smoke test for https://fireplace.ignorelist.com
//
// Run on the PC after `.\deploy-web.ps1` (and/or `./deploy-backend.sh` on the VPS):
//   cd scripts/smoke
//   npm install && npx playwright install chromium   # one-time
//   node post-deploy-smoke.mjs [--commit <shortSha>] [--url <base>]
//
// Checks (fails with exit 1 on any miss):
//   1. /health            -> {"status":"ok","db":"ok"}
//   2. /version.json      -> frontend semver present
//   3. /version           -> backend { version, gitCommit, buildTime } (not 0.0.1/0.0.2/dev/unknown)
//   4. main.dart.js       -> served bundle CONTAINS the expected git short-sha
//                            (the GIT_COMMIT dart-define is compiled into the JS; this is the
//                             definitive stale-build check — version.json alone can lie)
//   5. Playwright chromium boots the app (fresh profile = no stale SW) and the Flutter
//      view renders within 60 s. Screenshot saved next to this script.
//
// Expected commit defaults to `git rev-parse --short HEAD` of this repo; override with --commit.

import { execSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const args = process.argv.slice(2);
const argVal = (flag) => {
  const i = args.indexOf(flag);
  return i >= 0 ? args[i + 1] : undefined;
};

const BASE = (argVal("--url") ?? "https://fireplace.ignorelist.com").replace(/\/$/, "");
const here = path.dirname(fileURLToPath(import.meta.url));
const expectedCommit =
  argVal("--commit") ??
  execSync("git rev-parse --short HEAD", { cwd: path.resolve(here, "..", "..") })
    .toString()
    .trim();

let failures = 0;
const ok = (name, detail = "") => console.log(`  PASS  ${name}${detail ? ` — ${detail}` : ""}`);
const fail = (name, detail) => {
  failures++;
  console.error(`  FAIL  ${name} — ${detail}`);
};

const getJson = async (p) => {
  const res = await fetch(`${BASE}${p}`, { cache: "no-store" });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
};

console.log(`Smoke: ${BASE} (expecting commit ${expectedCommit})\n`);

// 1. /health
try {
  const h = await getJson("/health");
  h.status === "ok" && h.db === "ok"
    ? ok("/health", JSON.stringify(h))
    : fail("/health", JSON.stringify(h));
} catch (e) {
  fail("/health", e.message);
}

// 2. /version.json (frontend)
let feVersion = "?";
try {
  const v = await getJson("/version.json");
  feVersion = v.version;
  /^\d+\.\d+\.\d+$/.test(feVersion ?? "")
    ? ok("/version.json", `frontend ${feVersion}`)
    : fail("/version.json", `bad semver: ${JSON.stringify(v)}`);
} catch (e) {
  fail("/version.json", e.message);
}

// 3. /version (backend)
try {
  const v = await getJson("/version");
  const stale =
    ["0.0.1", "0.0.2"].includes(v.version) || ["dev", "unknown", ""].includes(v.gitCommit ?? "");
  !stale && v.version && v.gitCommit
    ? ok("/version", `backend ${v.version}/${v.gitCommit}`)
    : fail("/version", `stale/default metadata: ${JSON.stringify(v)}`);
} catch (e) {
  fail("/version", e.message);
}

// 4. served bundle contains the expected commit (stale-build detector)
try {
  const res = await fetch(`${BASE}/main.dart.js?smoke=${Date.now()}`, { cache: "no-store" });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const js = await res.text();
  js.includes(expectedCommit)
    ? ok("bundle commit", `main.dart.js contains ${expectedCommit}`)
    : fail(
        "bundle commit",
        `served main.dart.js does NOT contain ${expectedCommit} — stale build ` +
          `(served frontend is ${feVersion}; rebuild with flutter clean + deploy-web.ps1, ` +
          `or pass --commit <deployed-sha> if checking an older deploy on purpose)`,
      );
} catch (e) {
  fail("bundle commit", e.message);
}

// 5. browser boot (fresh profile — no service worker cache involved)
try {
  const { chromium } = await import("playwright");
  const browser = await chromium.launch();
  const page = await browser.newPage();
  const consoleErrors = [];
  page.on("pageerror", (err) => consoleErrors.push(String(err)));
  await page.goto(BASE, { waitUntil: "domcontentloaded", timeout: 60_000 });
  await page.waitForSelector("flutter-view, flt-glass-pane", { state: "attached", timeout: 60_000 });
  const shot = path.join(here, "smoke-latest.png");
  await page.screenshot({ path: shot });
  await browser.close();
  ok("app boot", `Flutter view rendered; screenshot ${path.basename(shot)}`);
  if (consoleErrors.length > 0)
    console.warn(`  WARN  page errors (not fatal): ${consoleErrors.slice(0, 3).join(" | ")}`);
} catch (e) {
  fail("app boot", e.message);
}

console.log(failures === 0 ? "\nSMOKE PASSED" : `\nSMOKE FAILED (${failures})`);
process.exit(failures === 0 ? 0 : 1);
