#!/usr/bin/env node
/**
 * Ensures CLAUDE.md backend test counts match Jest output.
 * Usage:
 *   node scripts/verify-claude-backend-test-counts.mjs
 *   node scripts/verify-claude-backend-test-counts.mjs --log backend/test-output.txt
 */
import { readFileSync, existsSync } from 'fs';
import { spawnSync } from 'child_process';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const claudePath = join(root, 'CLAUDE.md');

function parseClaudeCounts(text) {
  const m = text.match(/(\d+)\s+unit tests,\s*(\d+)\s+suites/);
  if (!m) {
    throw new Error(
      'CLAUDE.md: expected pattern like "277 unit tests, 39 suites" in Tests line',
    );
  }
  return { tests: Number(m[1]), suites: Number(m[2]) };
}

function parseJestLog(text) {
  const testsM = text.match(/Tests:\s+(\d+)\s+passed,\s+(\d+)\s+total/);
  const suitesM = text.match(
    /Test Suites:\s+(\d+)\s+passed,\s+(\d+)\s+total/,
  );
  if (!testsM || !suitesM) {
    throw new Error(
      'Jest output: expected "Test Suites: N passed, N total" and "Tests: N passed, N total"',
    );
  }
  return {
    tests: Number(testsM[1]),
    suites: Number(suitesM[1]),
  };
}

function runBackendTests() {
  const r = spawnSync('npm', ['test'], {
    cwd: join(root, 'backend'),
    encoding: 'utf8',
    shell: true,
  });
  const out = `${r.stdout ?? ''}${r.stderr ?? ''}`;
  if (r.status !== 0) {
    console.error(out);
    process.exit(r.status ?? 1);
  }
  return out;
}

const logArg = process.argv.indexOf('--log');
let jestOutput;
if (logArg !== -1) {
  const logPath = process.argv[logArg + 1];
  if (!logPath || !existsSync(logPath)) {
    console.error('Missing or invalid --log path');
    process.exit(1);
  }
  jestOutput = readFileSync(logPath, 'utf8');
} else {
  jestOutput = runBackendTests();
}

const claude = readFileSync(claudePath, 'utf8');
const expected = parseClaudeCounts(claude);
const actual = parseJestLog(jestOutput);

if (
  expected.tests !== actual.tests ||
  expected.suites !== actual.suites
) {
  console.error(
    `CLAUDE.md drift: documented ${expected.tests} tests / ${expected.suites} suites, ` +
      `Jest has ${actual.tests} tests / ${actual.suites} suites.\n` +
      `Update the Tests line in CLAUDE.md (and re-run).`,
  );
  process.exit(1);
}

console.log(
  `OK: CLAUDE.md matches Jest (${actual.tests} tests, ${actual.suites} suites)`,
);
