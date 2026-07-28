#!/usr/bin/env node
// Backend ESLint RATCHET.
//
//   node scripts/lint-ratchet.mjs            # fail if the error count grew
//   node scripts/lint-ratchet.mjs --update   # accept the current count as the new floor
//
// WHY A RATCHET AND NOT A GATE
// `npm run lint` has been failing on master for months. On 2026-07-08 it was 966
// problems / 726 errors; on 2026-07-27 it was 1603 / 1320 — roughly +30/day, unnoticed,
// because nothing in CI ran it. A plain `eslint` step in CI would be red on day one and
// would simply be ignored, which is how it got here.
//
// So this fails only when the count goes UP. Every commit either holds the line or
// improves it, and the floor drops automatically as debt is paid. The build never turns
// red for pre-existing debt, only for NEW debt.
//
// `npm run lint` is `eslint --fix` — it REWRITES ~510 files instead of reporting. This
// script never passes --fix. Use `npm run lint:check` for a plain human-readable report.

import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, "..");
const backend = path.join(repo, "backend");
const baselineFile = path.join(here, "lint-baseline.json");
const update = process.argv.includes("--update");

// eslint exits non-zero when it finds problems, which is the normal case here.
let raw;
try {
  raw = execFileSync(
    process.platform === "win32" ? "npx.cmd" : "npx",
    ["eslint", "{src,apps,libs,test}/**/*.ts", "-f", "json"],
    { cwd: backend, encoding: "utf8", maxBuffer: 256 * 1024 * 1024, shell: process.platform === "win32" },
  );
} catch (e) {
  raw = e.stdout;
  if (!raw) {
    console.error("lint-ratchet: eslint produced no JSON output.");
    console.error(e.stderr?.toString?.() ?? e.message);
    process.exit(2);
  }
}

let report;
try {
  report = JSON.parse(raw);
} catch {
  console.error("lint-ratchet: could not parse eslint JSON output.");
  process.exit(2);
}

let errors = 0;
let warnings = 0;
const byRule = new Map();
for (const file of report) {
  for (const m of file.messages) {
    if (m.severity === 2) errors++;
    else warnings++;
    const id = m.ruleId ?? "(parse error)";
    byRule.set(id, (byRule.get(id) ?? 0) + 1);
  }
}

const top = [...byRule.entries()].sort((a, b) => b[1] - a[1]).slice(0, 8);
console.log(`backend eslint: ${errors} errors, ${warnings} warnings`);
for (const [rule, n] of top) console.log(`  ${String(n).padStart(5)}  ${rule}`);

if (update) {
  writeFileSync(baselineFile, `${JSON.stringify({ errors, warnings }, null, 2)}\n`);
  console.log(`\nBaseline updated -> ${errors} errors, ${warnings} warnings.`);
  process.exit(0);
}

let baseline;
try {
  baseline = JSON.parse(readFileSync(baselineFile, "utf8"));
} catch {
  console.error(`\nlint-ratchet: missing or unreadable ${path.relative(repo, baselineFile)}.`);
  console.error("Create it with:  node scripts/lint-ratchet.mjs --update");
  process.exit(2);
}

console.log(`\nbaseline: ${baseline.errors} errors, ${baseline.warnings} warnings`);

if (errors > baseline.errors) {
  console.error(
    `\nFAIL: backend eslint errors went UP, ${baseline.errors} -> ${errors} (+${errors - baseline.errors}).`,
  );
  console.error("Fix the new findings. See them with:  cd backend && npm run lint:check");
  console.error("Do NOT run `npm run lint` to silence this — it is `--fix` and rewrites ~510 files.");
  console.error("If the increase is genuinely intentional:  node scripts/lint-ratchet.mjs --update");
  process.exit(1);
}

if (errors < baseline.errors) {
  console.log(
    `\nPASS — and the count IMPROVED, ${baseline.errors} -> ${errors} (-${baseline.errors - errors}).`,
  );
  console.log("Lower the floor so it cannot regress:  node scripts/lint-ratchet.mjs --update");
  process.exit(0);
}

console.log("\nPASS — error count held at the baseline.");
process.exit(0);
