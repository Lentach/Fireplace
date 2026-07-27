#!/usr/bin/env node
// impact.mjs - who depends on what I just changed, and which tests import it?
//
// Builds a reverse-import index straight from source (deterministic, no LLM, no graph
// file) and answers: given the files I changed, who imports them transitively, and
// which test files land in that set. The import resolution is ground truth by
// construction - it parses the same directives the compiler reads.
//
// SCOPE LIMIT, read before trusting the test list: import reachability is NOT test
// coverage. This follows `--depth` hops (default 3) through STATIC IMPORTS only. It
// cannot see NestJS DI/module wiring, the client<->server wire contracts, assets or
// config, or any behaviour a test exercises without importing the changed file. Use it
// to retest fast while iterating. Running the full tier suite before a commit or PR is
// required by project policy — nothing on this repo enforces it mechanically.
//
// Why not graphify's graph.json: measured 2026-07-27 against resolved imports, its
// file->file import edges score 86.6% precision / 90.7% recall on backend TypeScript but
// 0.5% / 1.5% on frontend Dart (it collapses every relative specifier such as
// '../../theme/rpg_theme.dart' into one node attributed to an arbitrary file). Unusable
// for the tier that changes most, so this reads source instead.
//
//   node scripts/impact.mjs                  # uncommitted work (working tree + staged + untracked)
//   node scripts/impact.mjs --ref master     # everything since a ref
//   node scripts/impact.mjs a.dart b.ts      # explicit files
//   --depth N   transitive hops to follow (default 3)
//   --json      machine-readable
//   --all       do not truncate long lists

import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { resolve, dirname, join, relative } from 'node:path';

const ROOT = resolve(import.meta.dirname, '..');
const git = (...args) =>
  execFileSync('git', args, { cwd: ROOT, encoding: 'utf8', maxBuffer: 64 << 20 });
const posix = (p) => p.split('\\').join('/');
const nulList = (out) => out.split('\0').map((s) => posix(s.trim())).filter(Boolean);

// Indexed source roots. Everything outside these is invisible to the tool.
const ROOTS = [
  'frontend/lib',
  'frontend/test',
  'frontend/test_e2e',
  'backend/src',
  'backend/test',
];

const inRoots = (f) => ROOTS.some((r) => f.startsWith(`${r}/`));
const isTest = (f) =>
  f.startsWith('frontend/test') || f.endsWith('.spec.ts') || f.endsWith('_test.dart');
const langOf = (f) => (f.endsWith('.dart') ? 'dart' : f.endsWith('.ts') ? 'ts' : null);

// ---------------------------------------------------------------- path inventory

// Tracked AND untracked-but-not-ignored. `git ls-files` alone hides brand-new files, so
// a just-created widget would be invisible to the index and to the change set.
function inventory() {
  return new Set([
    ...nulList(git('ls-files', '-z')),
    ...nulList(git('ls-files', '--others', '--exclude-standard', '-z')),
  ]);
}

// ---------------------------------------------------------------- import parsing

// Dart: a whole import/export/part directive, through its semicolon. Captured as one
// blob because conditional imports carry SEVERAL URIs -
//   import 'x_stub.dart' if (dart.library.html) 'x_web.dart' if (dart.library.io) 'x_io.dart';
// and grabbing only the first would leave every _web/_io implementation looking
// importer-less. 29 files in frontend/lib use this form, several across multiple lines.
const DART_DIRECTIVE = /^[ \t]*(?:import|export|part)\s+([^;]*);/gm;
const QUOTED = /['"]([^'"]+)['"]/g;
// TS: static import/export-from, bare side-effect import, dynamic import(), require().
const TS_SPEC =
  /(?:^\s*(?:import|export)\b[^;'"]*?from\s+['"]([^'"]+)['"])|(?:^\s*import\s+['"]([^'"]+)['"])|(?:\bimport\(\s*['"]([^'"]+)['"]\s*\))|(?:\brequire\(\s*['"]([^'"]+)['"]\s*\))/gm;

/** Every import specifier in a source file, conditional Dart URIs included. */
function* specsOf(src, lang) {
  if (lang === 'dart') {
    for (const d of src.matchAll(DART_DIRECTIVE))
      for (const q of d[1].matchAll(QUOTED)) yield q[1];
    return;
  }
  for (const m of src.matchAll(TS_SPEC)) {
    const spec = m[1] ?? m[2] ?? m[3] ?? m[4];
    if (spec) yield spec;
  }
}

/**
 * Resolve one import specifier to a repo-relative path, or null if external.
 * Membership is tested against `known` rather than the filesystem so that a DELETED
 * file still resolves - otherwise the blast radius of a deletion collapses to zero,
 * which is exactly when you most need to know who still imports it.
 */
function resolveSpec(fromFile, spec, lang, known) {
  let baseAbs;
  if (lang === 'dart' && spec.startsWith('package:fireplace/')) {
    // package:fireplace/x/y.dart -> frontend/lib/x/y.dart
    baseAbs = join(ROOT, 'frontend/lib', spec.slice('package:fireplace/'.length));
  } else if (spec.includes(':')) {
    return null; // package:flutter/..., dart:async - another package entirely
  } else if (spec.startsWith('.')) {
    baseAbs = resolve(dirname(join(ROOT, fromFile)), spec);
  } else if (lang === 'dart') {
    // Dart resolves a bare specifier against the importing file's own directory:
    // `import 'badging_bridge_web.dart';` is a sibling, not a package. TS has no
    // such form - there a bare specifier always means node_modules.
    baseAbs = resolve(dirname(join(ROOT, fromFile)), spec);
  } else {
    return null; // @nestjs/..., node builtins - not ours
  }

  const base = posix(relative(ROOT, baseAbs));
  const candidates =
    lang === 'dart' ? [base] : [base, `${base}.ts`, `${base}.d.ts`, `${base}/index.ts`];

  return candidates.find((c) => known.has(c)) ?? null;
}

function buildIndex(known) {
  const deps = new Map(); // file -> Set(files it imports)
  const rdeps = new Map(); // file -> Set(files that import it)
  const add = (m, k, v) => (m.get(k) ?? m.set(k, new Set()).get(k)).add(v);

  const files = [...known].filter((f) => inRoots(f) && langOf(f));

  for (const file of files) {
    const lang = langOf(file);
    let src;
    try {
      src = readFileSync(join(ROOT, file), 'utf8');
    } catch {
      continue; // deleted since inventory, or unreadable - still valid as a target
    }
    for (const spec of specsOf(src, lang)) {
      const target = resolveSpec(file, spec, lang, known);
      if (!target || target === file) continue;
      add(deps, file, target);
      add(rdeps, target, file);
    }
  }
  return { deps, rdeps, files };
}

// ---------------------------------------------------------------- cli + change set

/** Parse argv into options and positional file paths, consuming option values. */
function parseArgs(argv) {
  const opts = { json: false, all: false, depth: 3, ref: null, files: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--json') opts.json = true;
    else if (a === '--all') opts.all = true;
    else if (a === '--depth') {
      const n = Number(argv[++i]);
      if (!Number.isInteger(n) || n < 1)
        throw new Error(`--depth needs a positive integer, got "${argv[i]}"`);
      opts.depth = n;
    } else if (a === '--ref') {
      opts.ref = argv[++i];
      if (!opts.ref) throw new Error('--ref needs a git ref');
    } else if (a.startsWith('--')) throw new Error(`unknown option "${a}"`);
    else opts.files.push(a);
  }
  return opts;
}

function changedFiles({ files, ref }, known, tracked) {
  if (files.length) return files.map((f) => posix(relative(ROOT, resolve(f))));

  // Committed-since-ref plus everything still uncommitted. `git diff` reports deletions
  // (wanted) but never untracked files, so those are unioned in explicitly.
  // `-z` throughout: without it git C-quotes non-ASCII paths and they parse wrong.
  const diffs = ref
    ? [git('diff', '--name-only', '-z', `${ref}...HEAD`), git('diff', '--name-only', '-z', 'HEAD')]
    : [git('diff', '--name-only', '-z', 'HEAD'), git('diff', '--name-only', '-z', '--cached')];

  const fromDiff = diffs.flatMap(nulList);
  const untracked = [...known].filter(
    (f) => inRoots(f) && langOf(f) && !tracked.has(f),
  );

  return [...new Set([...fromDiff, ...untracked])];
}

/** Walk the reverse-import graph outward, recording the hop each file was reached at. */
function blastRadius(seeds, rdeps, maxDepth) {
  const seen = new Map(seeds.map((s) => [s, 0]));
  let frontier = seeds;
  for (let depth = 1; depth <= maxDepth && frontier.length; depth++) {
    const next = [];
    for (const f of frontier) {
      for (const dependent of rdeps.get(f) ?? []) {
        if (seen.has(dependent)) continue;
        seen.set(dependent, depth);
        next.push(dependent);
      }
    }
    frontier = next;
  }
  return seen;
}

// ---------------------------------------------------------------- report

const CAP = 12;
const list = (items, all) =>
  all || items.length <= CAP
    ? items
    : [...items.slice(0, CAP), `… ${items.length - CAP} more (--all)`];

/**
 * Naming 40 of 47 spec files is noise dressed up as precision - past half the suite,
 * the honest answer is "run the suite".
 */
function testCommand(hit, total, label, cmd, strip) {
  if (!hit.length) return null;
  if (total && hit.length / total >= 0.5)
    return `${cmd}   # ${hit.length}/${total} of the suite - narrowing buys nothing`;
  return `${cmd} ${hit.map((f) => f.replace(strip, '')).join(' ')}`;
}

function main() {
  const opts = parseArgs(process.argv.slice(2));

  const tracked = new Set(nulList(git('ls-files', '-z')));
  const known = inventory();
  const rawChanged = changedFiles(opts, known, tracked);
  // A deleted file is absent from the inventory but must still resolve as a target.
  for (const f of rawChanged) known.add(f);

  const changed = rawChanged.filter((f) => langOf(f) && inRoots(f));
  const ignored = rawChanged.length - changed.length;

  if (!changed.length) {
    const msg = ignored
      ? `No Dart/TS source changes in ${ROOTS.join(', ')}. ${ignored} other file(s) changed - nothing to trace.`
      : 'No changes detected.';
    console.log(opts.json ? JSON.stringify({ changed: [], note: msg }) : msg);
    return;
  }

  const { rdeps, files } = buildIndex(known);
  const reached = blastRadius(changed, rdeps, opts.depth);

  const changedSet = new Set(changed);
  const impacted = [...reached].filter(([f]) => !changedSet.has(f));
  const tests = impacted.filter(([f]) => isTest(f)).map(([f]) => f).sort();
  const src = impacted.filter(([f]) => !isTest(f));
  const direct = src.filter(([, d]) => d === 1).map(([f]) => f).sort();
  const indirect = src.filter(([, d]) => d > 1).map(([f]) => f).sort();
  // A changed file with no dependents at all is either an entry point or dead code.
  const orphans = changed.filter((f) => !rdeps.get(f)?.size);

  const suite = { dart: 0, ts: 0 };
  for (const f of files) if (isTest(f)) suite[f.endsWith('.dart') ? 'dart' : 'ts']++;

  const commands = [
    testCommand(
      tests.filter((f) => f.endsWith('.dart')),
      suite.dart,
      'flutter',
      'cd frontend && flutter test',
      /^frontend\//,
    ),
    testCommand(
      tests.filter((f) => f.endsWith('.ts')),
      suite.ts,
      'jest',
      'cd backend && npx jest',
      /^backend\//,
    ),
  ].filter(Boolean);

  if (opts.json) {
    console.log(JSON.stringify({ changed, direct, indirect, tests, orphans, commands }, null, 2));
    return;
  }

  console.log(
    `\nIMPACT  ${changed.length} changed · ${direct.length} direct · ${indirect.length} indirect · ${tests.length} tests (depth ${opts.depth})\n`,
  );
  console.log('Changed');
  for (const f of list([...changed].sort(), opts.all)) console.log(`  ${f}`);
  if (direct.length) {
    console.log('\nDirect dependents');
    for (const f of list(direct, opts.all)) console.log(`  ${f}`);
  }
  if (indirect.length) {
    console.log(`\nIndirect (2-${opts.depth} hops)`);
    for (const f of list(indirect, opts.all)) console.log(`  ${f}`);
  }
  if (tests.length) {
    console.log('\nTests that IMPORT this change');
    for (const f of list(tests, opts.all)) console.log(`  ${f}`);
    console.log('\nRetest (inner loop only — not a substitute for the tier suite)');
    for (const c of commands) console.log(`  ${c}`);
  } else {
    console.log('\nNo test imports this change. Nothing here proves it — verify by hand.');
  }
  if (orphans.length) {
    console.log('\nNo dependents (entry point or dead code)');
    for (const f of list(orphans, opts.all)) console.log(`  ${f}`);
  }
  const tiers = new Set(changed.map((f) => f.split('/')[0]));
  if (tiers.has('frontend') && tiers.has('backend')) {
    console.log('\nCROSS-TIER change. Imports do not cross the wire - check the');
    console.log('contract by hand: CLAUDE.md §7 (envelope/WS events) and §8.');
  }
  console.log('');
}

try {
  main();
} catch (err) {
  console.error(`impact: ${err.message}`);
  console.error('usage: node scripts/impact.mjs [files…] [--ref <git-ref>] [--depth N] [--json] [--all]');
  process.exit(1);
}
