// backend/src/database/migration-runner.spec.ts
import { mkdtempSync, rmSync, writeFileSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';
import {
  BASELINE_FILENAME,
  planMigrations,
  runMigrations,
} from './migration-runner';

// pg is mocked so the executor never touches a real database. Each executor
// test installs its own Client implementation via MockedClient.mockImplementation.
jest.mock('pg', () => ({ Client: jest.fn() }));
// eslint-disable-next-line @typescript-eslint/no-var-requires
const { Client } = require('pg') as { Client: jest.Mock };

const FK_MIGRATION = '0002_user_foreign_keys.sql';

describe('planMigrations', () => {
  it('stamps a pending baseline on a pre-existing schema and still RUNS every other pending file', () => {
    // Critical prod-safety case: a naive "stamp all pending" would skip the FK
    // migration. Only the baseline may be stamped; 0002 must still execute.
    const plan = planMigrations(
      [BASELINE_FILENAME, FK_MIGRATION],
      new Set<string>(),
      true,
    );

    expect(plan.stamp).toEqual([BASELINE_FILENAME]);
    expect(plan.run).toEqual([FK_MIGRATION]);
    expect(plan.run).not.toContain(BASELINE_FILENAME);
  });

  it('runs a pending baseline first (and stamps nothing) on an empty schema', () => {
    const plan = planMigrations(
      [BASELINE_FILENAME, FK_MIGRATION],
      new Set<string>(),
      false,
    );

    expect(plan.stamp).toEqual([]);
    expect(plan.run).toEqual([BASELINE_FILENAME, FK_MIGRATION]);
    expect(plan.run[0]).toBe(BASELINE_FILENAME);
  });

  it('never re-runs or re-stamps already-applied files', () => {
    const applied = new Set([BASELINE_FILENAME, FK_MIGRATION]);

    // schemaPreexists true would otherwise be the stamping path for the baseline.
    const plan = planMigrations([BASELINE_FILENAME, FK_MIGRATION], applied, true);

    expect(plan.stamp).toEqual([]);
    expect(plan.run).toEqual([]);
  });

  it('preserves lexical ordering in run regardless of input order', () => {
    const plan = planMigrations(
      ['0003_c.sql', '0001_a.sql', '0002_b.sql'],
      new Set<string>(),
      false,
    );

    expect(plan.run).toEqual(['0001_a.sql', '0002_b.sql', '0003_c.sql']);
  });

  it('never stamps a non-baseline file even on a pre-existing schema', () => {
    const plan = planMigrations([FK_MIGRATION], new Set<string>(), true);

    expect(plan.stamp).toEqual([]);
    expect(plan.run).toEqual([FK_MIGRATION]);
  });
});

/** One recorded client.query invocation. */
interface QueryCall {
  text: string;
  params?: unknown[];
}

interface MockClientOptions {
  applied?: string[];
  preexists?: boolean;
  /** Any file SQL containing this substring throws when executed. */
  failSqlContaining?: string;
}

function createMockClient(opts: MockClientOptions = {}) {
  const calls: QueryCall[] = [];
  const client = {
    connect: jest.fn().mockResolvedValue(undefined),
    end: jest.fn().mockResolvedValue(undefined),
    query: jest.fn(async (text: string, params?: unknown[]) => {
      calls.push({ text, params });
      // Match by SQL substring — not call index — so the spec survives
      // incidental reordering of the runner's bookkeeping queries.
      if (text.includes('SELECT filename FROM schema_migrations')) {
        return { rows: (opts.applied ?? []).map((f) => ({ filename: f })) };
      }
      if (text.includes('to_regclass')) {
        return { rows: [{ x: opts.preexists ?? false }] };
      }
      if (opts.failSqlContaining && text.includes(opts.failSqlContaining)) {
        throw new Error('boom');
      }
      return { rows: [] };
    }),
  };
  return { client, calls };
}

const texts = (calls: QueryCall[]) => calls.map((c) => c.text);
/** First index whose query text contains `needle`, else -1. */
const idxOf = (calls: QueryCall[], needle: string) =>
  calls.findIndex((c) => c.text.includes(needle));

describe('runMigrations', () => {
  let tmpDirs: string[] = [];

  const makeDir = (files: Record<string, string>): string => {
    const dir = mkdtempSync(join(tmpdir(), 'migrunner-'));
    tmpDirs.push(dir);
    for (const [name, sql] of Object.entries(files)) {
      writeFileSync(join(dir, name), sql, 'utf8');
    }
    return dir;
  };

  beforeEach(() => {
    Client.mockReset();
    tmpDirs = [];
  });

  afterEach(() => {
    for (const dir of tmpDirs) {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it('rolls back, throws naming the file, records no INSERT for it, and still ends the client on failing SQL', async () => {
    const { client, calls } = createMockClient({
      preexists: true,
      failSqlContaining: 'FAIL_MARKER',
    });
    Client.mockImplementation(() => client);
    // preexists true, but 0002 is not the baseline so it executes and throws.
    const dir = makeDir({ '0002_boom.sql': 'CREATE TABLE FAIL_MARKER ();' });

    await expect(
      runMigrations({ dir, log: () => {} }),
    ).rejects.toThrow(/migration 0002_boom\.sql failed/);

    const t = texts(calls);
    expect(t).toContain('ROLLBACK');
    // No successful INSERT for the failing file.
    const insertedFail = calls.some(
      (c) =>
        c.text.includes('INSERT INTO schema_migrations') &&
        Array.isArray(c.params) &&
        c.params.includes('0002_boom.sql'),
    );
    expect(insertedFail).toBe(false);
    expect(client.end).toHaveBeenCalledTimes(1);
  });

  it('runs BEGIN / SET LOCAL lock_timeout / file SQL / INSERT / COMMIT in order per file and RESET ALL after each applied file', async () => {
    const { client, calls } = createMockClient({ preexists: false });
    Client.mockImplementation(() => client);
    const dir = makeDir({
      '0001_baseline.sql': 'CREATE TABLE users (id int); -- BASELINE_SQL',
      '0002_user_foreign_keys.sql': 'ALTER TABLE users ADD COLUMN x int; -- FK_SQL',
    });

    await runMigrations({ dir, log: () => {} });

    const t = texts(calls);
    const begin = idxOf(calls, 'BEGIN');
    const setLocal = idxOf(calls, "SET LOCAL lock_timeout = '10s'");
    const baselineSql = idxOf(calls, 'BASELINE_SQL');
    const insert = calls.findIndex(
      (c) =>
        c.text.includes('INSERT INTO schema_migrations') &&
        Array.isArray(c.params) &&
        c.params.includes(BASELINE_FILENAME),
    );
    const commit = idxOf(calls, 'COMMIT');
    const reset = idxOf(calls, 'RESET ALL');

    // Ordering within the first (baseline) file.
    expect(begin).toBeGreaterThanOrEqual(0);
    expect(begin).toBeLessThan(setLocal);
    expect(setLocal).toBeLessThan(baselineSql);
    expect(baselineSql).toBeLessThan(insert);
    expect(insert).toBeLessThan(commit);
    expect(commit).toBeLessThan(reset);

    // Both files applied: two BEGINs, two COMMITs, RESET ALL after each.
    expect(t.filter((x) => x === 'BEGIN')).toHaveLength(2);
    expect(t.filter((x) => x === 'COMMIT')).toHaveLength(2);
    expect(t.filter((x) => x === 'RESET ALL')).toHaveLength(2);
    // No stamping on an empty schema.
    expect(t.some((x) => x.includes('ON CONFLICT'))).toBe(false);
    expect(client.end).toHaveBeenCalledTimes(1);
  });

  it('throws on an empty migrations directory', async () => {
    const dir = makeDir({});

    await expect(runMigrations({ dir, log: () => {} })).rejects.toThrow(
      /no \.sql migrations found/,
    );
    // Never reached the DB.
    expect(Client).not.toHaveBeenCalled();
  });

  it('stamps a pending baseline with ON CONFLICT and NEVER executes its contents on a pre-existing schema', async () => {
    const { client, calls } = createMockClient({ preexists: true });
    Client.mockImplementation(() => client);
    const dir = makeDir({
      '0001_baseline.sql':
        'DROP TABLE users; -- BASELINE_BODY_MUST_NOT_RUN',
      '0002_user_foreign_keys.sql': 'ALTER TABLE users ADD COLUMN y int; -- FK_BODY',
    });

    await runMigrations({ dir, log: () => {} });

    // Baseline stamped via ON CONFLICT insert...
    const stampInsert = calls.find(
      (c) =>
        c.text.includes('INSERT INTO schema_migrations') &&
        c.text.includes('ON CONFLICT') &&
        Array.isArray(c.params) &&
        c.params.includes(BASELINE_FILENAME),
    );
    expect(stampInsert).toBeDefined();
    // ...and its body never executed.
    expect(texts(calls).some((x) => x.includes('BASELINE_BODY_MUST_NOT_RUN'))).toBe(
      false,
    );
    // The FK migration still runs (prod-safety).
    expect(texts(calls).some((x) => x.includes('FK_BODY'))).toBe(true);
    expect(client.end).toHaveBeenCalledTimes(1);
  });

  // Regression: pg_dump brackets its output with `\restrict` / `\unrestrict` (our
  // baseline header says pg_dump 16.13), which are psql meta-commands, not SQL.
  // Sent through node-postgres they raise
  // `syntax error at or near "\"`, so the baseline could never execute on a FRESH
  // database — the disaster-recovery path. Caught only when CI first booted an
  // empty Postgres; prod and existing dev DBs stamp the baseline instead of running it.
  it('strips psql meta-commands from the baseline so it can execute on a fresh database', async () => {
    const { client, calls } = createMockClient({ preexists: false });
    Client.mockImplementation(() => client);
    const dir = makeDir({
      [BASELINE_FILENAME]:
        '\\restrict AbC123\nCREATE TABLE public.users (id uuid);\n\\unrestrict AbC123\n',
    });

    await runMigrations({ dir, log: () => {} });

    const executed = texts(calls).find((x) => x.includes('CREATE TABLE public.users'));
    expect(executed).toBeDefined();
    // The meta-commands are gone; the real DDL survives untouched.
    expect(executed).not.toContain('\\restrict');
    expect(executed).not.toContain('\\unrestrict');
  });

  it('executes non-baseline migrations byte-for-byte, meta-command strip NOT applied', async () => {
    const { client, calls } = createMockClient({ preexists: false });
    Client.mockImplementation(() => client);
    // A later migration must never be rewritten. If a line like this ever appears
    // legitimately (inside a dollar-quoted body, say), it has to reach the server intact.
    const body = "INSERT INTO public.t (s) VALUES ($$\n\\restrict not-a-meta-command\n$$);\n";
    const dir = makeDir({
      [BASELINE_FILENAME]: 'CREATE TABLE public.users (id uuid);\n',
      '0002_later.sql': body,
    });

    await runMigrations({ dir, log: () => {} });

    expect(texts(calls)).toContain(body);
  });
});
