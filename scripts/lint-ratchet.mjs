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
//
// PLATFORM DELTA — how it is handled now.
// Raw counts are NOT identical across OSes: Windows reports 1320 errors where Linux CI
// reports 1318, and the two-error gap is CRLF-sensitive `prettier/prettier` findings.
//
// The FIRST version of this script pinned one baseline to the HIGHER (Windows) number so
// that neither platform failed spuriously. That was a bug: CI runs Linux, so the real
// enforcement point gained two errors of free headroom and a change adding 1-2 new errors
// passed green. Caught in review 2026-07-27.
//
// The count is now SPLIT (see below): `nonPrettier` is AST-derived and platform-identical,
// so it takes ONE baseline enforced strictly; `prettier` is formatting-only and gets a
// small tolerance. `--update` is therefore safe to run from either platform.

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

// GUARD: an empty report must never read as "clean". If a config/glob change ever makes
// eslint match zero files while still exiting 0, a naive count gives errors=0 — below any
// baseline — and would print "PASS, IMPROVED" on a build that linted nothing. A ratchet's
// worst failure is a confident false pass, so treat this as a tooling error.
if (!Array.isArray(report) || report.length === 0) {
  console.error("lint-ratchet: eslint reported ZERO files. Refusing to pass — that is a");
  console.error("config/glob failure, not a clean tree. Check backend/eslint.config.mjs.");
  process.exit(2);
}

// TWO CLASSES, TRACKED SEPARATELY.
//
// `prettier/prettier` findings are CRLF-sensitive, so their count differs by platform:
// Windows reports 1320 errors total where Linux CI reports 1318. The first version of
// this script pinned ONE baseline to the higher (Windows) number, which left TWO errors
// of slack at the real enforcement point (CI, on Linux) — a change adding 1-2 new errors
// stayed <= 1320 and passed green. That is exactly the silent regression this exists to
// stop. Found in review, 2026-07-27.
//
// Splitting the count fixes it without a per-platform baseline:
//   nonPrettier — AST-derived, platform-identical. Enforced STRICTLY (any increase fails).
//   prettier    — formatting only, auto-fixable, never a bug. Enforced with a small
//                 tolerance so the CRLF delta cannot cause a spurious failure, but a real
//                 pile-up (someone adding 200 unformatted lines) still trips it.
const IGNORED_FROM_STRICT = new Set(["prettier/prettier"]);
const PRETTIER_TOLERANCE = 5; // absorbs the cross-platform CRLF delta (observed: 2)

let errors = 0;
let warnings = 0;
let prettierErrors = 0;
const byRule = new Map();
for (const file of report) {
  for (const m of file.messages) {
    const id = m.ruleId ?? "(parse error)";
    if (IGNORED_FROM_STRICT.has(id)) {
      if (m.severity === 2) prettierErrors++;
      continue;
    }
    if (m.severity === 2) errors++;
    else warnings++;
    byRule.set(id, (byRule.get(id) ?? 0) + 1);
  }
}

const top = [...byRule.entries()].sort((a, b) => b[1] - a[1]).slice(0, 8);
console.log(`platform: ${process.platform} · ${report.length} files scanned`);
console.log(`real errors (gated strictly): ${errors}   warnings: ${warnings}`);
for (const [rule, n] of top) console.log(`  ${String(n).padStart(5)}  ${rule}`);
// Printed so a CI log CONFIRMS (or refutes) the claim that the whole Windows/Linux delta
// is prettier. If nonPrettier ever differs across platforms, that assumption was wrong.
console.log(`formatting errors (tolerance ±${PRETTIER_TOLERANCE}): ${prettierErrors}  [prettier/prettier]`);

if (update) {
  writeFileSync(
    baselineFile,
    `${JSON.stringify({ nonPrettier: errors, prettier: prettierErrors, warnings }, null, 2)}\n`,
  );
  console.log(`\nBaseline updated -> ${errors} real errors, ${prettierErrors} formatting.`);
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

if (typeof baseline.nonPrettier !== "number" || typeof baseline.prettier !== "number") {
  console.error(`\nlint-ratchet: ${path.relative(repo, baselineFile)} is missing`);
  console.error("`nonPrettier` / `prettier`. It predates the split-count format (2026-07-27).");
  console.error("Regenerate it with:  node scripts/lint-ratchet.mjs --update");
  process.exit(2);
}

console.log(`\nbaseline: ${baseline.nonPrettier} real errors, ${baseline.prettier} formatting`);

let failed = false;

if (errors > baseline.nonPrettier) {
  console.error(
    `\nFAIL: real eslint errors went UP, ${baseline.nonPrettier} -> ${errors} (+${errors - baseline.nonPrettier}).`,
  );
  console.error("These are type-safety findings, not formatting. See them with:");
  console.error("  cd backend && npm run lint:check");
  console.error("Do NOT run `npm run lint` to silence this — it is `--fix` and rewrites ~510 files.");
  console.error("If the increase is genuinely intentional:  node scripts/lint-ratchet.mjs --update");
  failed = true;
}

if (prettierErrors > baseline.prettier + PRETTIER_TOLERANCE) {
  console.error(
    `\nFAIL: formatting errors went UP well past tolerance, ${baseline.prettier} -> ${prettierErrors}.`,
  );
  console.error("This one IS safe to auto-fix:  cd backend && npx prettier --write \"src/**/*.ts\"");
  failed = true;
}

if (failed) process.exit(1);

if (errors < baseline.nonPrettier) {
  console.log(
    `\nPASS — and real errors IMPROVED, ${baseline.nonPrettier} -> ${errors} (-${baseline.nonPrettier - errors}).`,
  );
  console.log("Lower the floor so it cannot regress:  node scripts/lint-ratchet.mjs --update");
  process.exit(0);
}

console.log("\nPASS — real error count held at the baseline.");
process.exit(0);
