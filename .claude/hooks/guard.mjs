// Claude Code PreToolUse mirror of .omp/hooks/pre/guard.ts. Reads the hook JSON
// on stdin; exit 2 + stderr text = block (Claude Code hooks reference).
const RULES = [
  [/\bgit\b[^\n|;&]*\bcommit\b[^\n|;&]*(--no-verify|\s-n\b)/,
    'git commit --no-verify is forbidden: it skips gitleaks + scripts/verify-context-budget.mjs. Fix the gate failure instead.'],
  [/\bgh\s+run\s+list\b/,
    'gh run list is forbidden (CLAUDE.md §3): use gh api repos/Lentach/Fireplace/commits/master/check-runs.'],
];
let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => (raw += c));
process.stdin.on('end', () => {
  let cmd = '';
  try { cmd = String(JSON.parse(raw).tool_input?.command ?? ''); } catch { process.exit(0); }
  for (const [re, reason] of RULES) {
    if (re.test(cmd)) { process.stderr.write(reason + '\n'); process.exit(2); }
  }
});
