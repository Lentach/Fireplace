#!/usr/bin/env node
// Context-budget gate (workflow 2.0, 2026-09-10). Run by .githooks/pre-commit on the STAGED tree.
// Ratchet semantics: every limit below sits just above the post-migration size, so the check is
// green the day it lands and only bites on regrowth. Raise a limit deliberately, in the same
// commit as the growth, with the reason in the commit message.
//
//   node scripts/verify-context-budget.mjs            # staged tree (pre-commit)
//   node scripts/verify-context-budget.mjs --worktree # working files
import { execFileSync } from "node:child_process";
import { readFileSync, existsSync } from "node:fs";

const WORKTREE = process.argv.includes("--worktree");
const LATEST = ".cursor/session-summaries/LATEST.md";

const BYTE_LIMITS = {
  "CLAUDE.md": 24_000, // 20.6 KB after §7 moved out (was 52 KB)
  "frontend/CLAUDE.md": 28_000, // 23.7 KB after §5/§7/§10 moved out (was 84 KB)
  "backend/CLAUDE.md": 26_000,
  [LATEST]: 10_000,
};
const LATEST_MAX_ENTRIES = 5;
const LATEST_MAX_ENTRY_CHARS = 1_000; // rule says ≤ 900; 100 chars of slack for links
const SUMMARY_MAX_BYTES = 8_000; // rule says ≤ 6 KB; slack for proof tables
const SUMMARY_REQUIRED = ["## What was done", "## Key files", "## Verification", "## Notes for next session"];

function staged(path) {
  try {
    return execFileSync("git", ["show", `:${path}`], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
  } catch {
    return null; // not staged and not tracked
  }
}
function content(path) {
  if (WORKTREE) return existsSync(path) ? readFileSync(path, "utf8") : null;
  return staged(path);
}
// Dated summaries touched by this commit. Size cap applies to added AND modified
// (a summary committed mid-session and re-staged must not escape); the template
// check applies to ADDED only (pre-2.0 summaries use older headings).
function summaryTargets() {
  const re = /^\.cursor\/session-summaries\/\d{4}-\d{2}-\d{2}-.*\.md$/;
  const args = WORKTREE ? ["diff", "--name-status", "HEAD"] : ["diff", "--cached", "--name-status"];
  return execFileSync("git", args, { encoding: "utf8" })
    .split(/\r?\n/)
    .filter(Boolean)
    .map((l) => l.split(/\t/))
    .filter(([st, p]) => re.test(p) && /^[AM]/.test(st))
    .map(([st, p]) => ({ path: p, added: st.startsWith("A") }));
}

const failures = [];
const bytesOf = (s) => Buffer.byteLength(s, "utf8");

for (const [path, limit] of Object.entries(BYTE_LIMITS)) {
  const s = content(path);
  if (s == null) continue;
  const n = bytesOf(s);
  if (n > limit) failures.push(`${path}: ${n} bytes > ${limit}. Move the new material to an on-demand doc (docs/contracts, frontend/docs) and leave a pointer.`);
}

const latest = content(LATEST);
if (latest != null) {
  const entries = latest.split(/\r?\n(?=\*\*Date:\*\*)/).slice(1);
  if (entries.length > LATEST_MAX_ENTRIES) failures.push(`${LATEST}: ${entries.length} dated entries (cap ${LATEST_MAX_ENTRIES}). Put yours on top and DELETE the oldest — its traps go to docs/agents/traps.md.`);
  entries.forEach((e, i) => {
    const len = e.trim().length;
    if (len > LATEST_MAX_ENTRY_CHARS) failures.push(`${LATEST}: entry ${i + 1} is ${len} chars (cap ${LATEST_MAX_ENTRY_CHARS}). Detail belongs in the dated file it links.`);
  });
  if (/^> /m.test(latest)) failures.push(`${LATEST}: blockquote banner detected. Standing warnings go to docs/agents/traps.md, one line each.`);
}

for (const { path, added } of summaryTargets()) {
  const s = content(path);
  if (s == null) continue;
  const n = bytesOf(s);
  if (n > SUMMARY_MAX_BYTES) failures.push(`${path}: ${n} bytes > ${SUMMARY_MAX_BYTES}. Investigation narrative belongs in .planning/<task>/findings.md or docs/agents/workflow-2.0.md; the summary is Done / Proof / Open / Traps.`);
  if (added) for (const h of SUMMARY_REQUIRED) if (!s.includes(h)) failures.push(`${path}: missing section "${h}".`);
}

if (failures.length) {
  console.error("BLOCKED by scripts/verify-context-budget.mjs:");
  for (const f of failures) console.error("  - " + f);
  process.exit(1);
}
console.log("context budget OK");
