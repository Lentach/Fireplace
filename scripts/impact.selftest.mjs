#!/usr/bin/env node
// Self-test for scripts/impact.mjs.
//
// Builds a throwaway git repo in the OS temp dir containing every import form the real
// tree uses, copies impact.mjs into it, and asserts the reported edges. Hermetic - it
// never touches the Fireplace working copy, so it is safe to run at any time:
//
//   node scripts/impact.selftest.mjs
//
// Add a case here whenever the parser or CLI grows a rule. Ad-hoc manual checks prove
// today's tree; this is what stops a future regex tweak from silently dropping edges.

import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, copyFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname, resolve } from 'node:path';

const SRC = join(import.meta.dirname, 'impact.mjs');
const repo = mkdtempSync(join(tmpdir(), 'impact-selftest-'));
const git = (...a) => execFileSync('git', a, { cwd: repo, encoding: 'utf8' });
const put = (rel, body) => {
  const p = join(repo, rel);
  mkdirSync(dirname(p), { recursive: true });
  writeFileSync(p, body);
};

// ---------------------------------------------------------------- fixture

const FILES = {
  // --- Dart: bare same-directory specifier (no leading './') ---
  'frontend/lib/services/badge.dart': `import 'bridge_stub.dart' if (dart.library.html) 'bridge_web.dart';\nvoid f() {}\n`,
  'frontend/lib/services/bridge_stub.dart': 'void b() {}\n',
  'frontend/lib/services/bridge_web.dart': 'void b() {}\n',

  // --- Dart: multiline conditional with TWO conditions ---
  'frontend/lib/providers/conv.dart':
    `import '../services/cleaner_stub.dart'\n` +
    `    if (dart.library.html) '../services/cleaner_web.dart'\n` +
    `    if (dart.library.io) '../services/cleaner_io.dart';\n` +
    `import '../services/badge.dart';\nvoid c() {}\n`,
  'frontend/lib/services/cleaner_stub.dart': 'void x() {}\n',
  'frontend/lib/services/cleaner_web.dart': 'void x() {}\n',
  'frontend/lib/services/cleaner_io.dart': 'void x() {}\n',

  // --- Dart: `as` alias, export, and a package:fireplace import from a test ---
  'frontend/lib/utils/alias.dart': `import 'helper.dart' as h;\nvoid a() {}\n`,
  'frontend/lib/utils/helper.dart': 'void h() {}\n',
  'frontend/test/conv_test.dart': `import 'package:fireplace/providers/conv.dart';\nvoid main() {}\n`,

  // --- TS: extensionless relative, index.ts barrel, side-effect import ---
  'backend/src/svc.ts': 'export const svc = 1;\n',
  'backend/src/barrel/index.ts': "export * from '../svc';\n",
  'backend/src/mod.ts': "import { svc } from './svc';\nimport './barrel';\nexport const m = svc;\n",
  'backend/src/mod.spec.ts': "import { m } from './mod';\ndescribe('m', () => it('works', () => expect(m).toBe(1)));\n",

  // --- noise that must NOT resolve to anything internal ---
  'frontend/lib/external.dart': `import 'package:flutter/material.dart';\nimport 'dart:async';\nvoid e() {}\n`,
  'backend/src/external.ts': "import { Injectable } from '@nestjs/common';\nexport const q = Injectable;\n",
};

for (const [rel, body] of Object.entries(FILES)) put(rel, body);
mkdirSync(join(repo, 'scripts'), { recursive: true });
copyFileSync(SRC, join(repo, 'scripts', 'impact.mjs'));

git('init', '-q', '-b', 'main');
git('config', 'user.email', 'selftest@local');
git('config', 'user.name', 'selftest');
git('config', 'commit.gpgsign', 'false');
git('config', 'core.autocrlf', 'false'); // fixture files are LF; silence Windows CRLF warnings
git('add', '-A');
git('commit', '-qm', 'fixture');

// ---------------------------------------------------------------- harness

const impact = (...args) => {
  const out = execFileSync(process.execPath, [join(repo, 'scripts', 'impact.mjs'), ...args], {
    cwd: repo,
    encoding: 'utf8',
  });
  return JSON.parse(out);
};

let failures = 0;
const eq = (name, actual, expected) => {
  const a = JSON.stringify([...actual].sort());
  const e = JSON.stringify([...expected].sort());
  if (a === e) return console.log(`  ok   ${name}`);
  failures++;
  console.log(`  FAIL ${name}\n         expected ${e}\n         actual   ${a}`);
};

console.log(`\nimpact.mjs self-test  (fixture: ${repo})\n`);

// ---------------------------------------------------------------- cases

// Dart conditional URIs are ALL captured, and a bare specifier resolves to a sibling.
eq(
  'dart conditional + bare same-dir specifier',
  impact('--json', 'frontend/lib/services/bridge_web.dart').direct,
  ['frontend/lib/services/badge.dart'],
);

// Multiline conditional carrying two `if` clauses.
eq(
  'dart multiline conditional, second condition',
  impact('--json', 'frontend/lib/services/cleaner_io.dart').direct,
  ['frontend/lib/providers/conv.dart'],
);

// `import ... as h;`
eq(
  'dart aliased import',
  impact('--json', 'frontend/lib/utils/helper.dart').direct,
  ['frontend/lib/utils/alias.dart'],
);

// package:fireplace/... from the test tree maps back into frontend/lib.
eq(
  'package:fireplace import from a test',
  impact('--json', 'frontend/lib/providers/conv.dart').tests,
  ['frontend/test/conv_test.dart'],
);

// Transitive: badge.dart <- conv.dart <- conv_test.dart
eq(
  'transitive dart chain reaches the test',
  impact('--json', 'frontend/lib/services/badge.dart').tests,
  ['frontend/test/conv_test.dart'],
);

// TS extensionless relative import.
eq('ts extensionless relative', impact('--json', 'backend/src/svc.ts').direct, [
  'backend/src/barrel/index.ts',
  'backend/src/mod.ts',
]);

// TS `import './barrel'` -> barrel/index.ts
eq('ts index.ts barrel', impact('--json', 'backend/src/barrel/index.ts').direct, [
  'backend/src/mod.ts',
]);

eq('ts spec file detected as a test', impact('--json', 'backend/src/mod.ts').tests, [
  'backend/src/mod.spec.ts',
]);

// External packages must never produce internal edges.
eq('external package imports ignored', impact('--json', 'frontend/lib/external.dart').direct, []);

// --depth is parsed as an option, not as a filename, and actually limits the walk.
eq(
  '--depth 1 stops before the 2-hop test',
  impact('--json', '--depth', '1', 'frontend/lib/services/bridge_web.dart').tests,
  [],
);
eq(
  '--depth 3 reaches the 3-hop test',
  impact('--json', '--depth', '3', 'frontend/lib/services/bridge_web.dart').tests,
  ['frontend/test/conv_test.dart'],
);

// An untracked, never-committed file is indexed and reported.
put('frontend/lib/screens/fresh.dart', `import '../services/badge.dart';\nvoid s() {}\n`);
eq(
  'untracked new file appears as a dependent',
  impact('--json', 'frontend/lib/services/badge.dart').direct,
  ['frontend/lib/providers/conv.dart', 'frontend/lib/screens/fresh.dart'],
);
eq(
  'untracked new file is in the default change set',
  impact('--json').changed.filter((f) => f === 'frontend/lib/screens/fresh.dart'),
  ['frontend/lib/screens/fresh.dart'],
);
rmSync(join(repo, 'frontend/lib/screens/fresh.dart'));

// --ref is parsed as an option and diffs against the ref.
git('checkout', '-qb', 'feature');
put('frontend/lib/utils/helper.dart', 'void h() {}\nvoid h2() {}\n');
git('commit', '-qam', 'touch helper');
eq('--ref picks up the committed change', impact('--json', '--ref', 'main').changed, [
  'frontend/lib/utils/helper.dart',
]);

// A DELETED file must still resolve, or the blast radius of a removal reads as zero.
git('rm', '-q', 'frontend/lib/utils/helper.dart');
eq(
  'deleted file still reports its importers',
  impact('--json').direct,
  ['frontend/lib/utils/alias.dart'],
);
git('reset', '-q', '--hard'); // `git rm` staged the deletion; checkout alone cannot undo it
git('checkout', '-q', 'main');

// Unknown option exits non-zero rather than being read as a path.
let rejected = false;
try {
  execFileSync(process.execPath, [join(repo, 'scripts', 'impact.mjs'), '--bogus'], {
    cwd: repo,
    stdio: 'pipe',
  });
} catch {
  rejected = true;
}
eq('unknown option is rejected', [rejected], [true]);

// ---------------------------------------------------------------- teardown

rmSync(repo, { recursive: true, force: true });
console.log(failures ? `\n${failures} FAILED\n` : '\nall passed\n');
process.exit(failures ? 1 : 0);
