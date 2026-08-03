import { readdirSync, readFileSync } from 'fs';
import { join } from 'path';
import { setTimeout as sleep } from 'timers/promises';
import * as dotenv from 'dotenv';
import { Client } from 'pg';

/**
 * SQL migration runner — runs at bootstrap (main.ts) BEFORE Nest creates the app,
 * in every environment. Dev keeps TypeORM synchronize as well; production has
 * synchronize OFF, so these files are the ONLY way prod schema changes happen.
 *
 * Contract:
 * - Files live in `<cwd>/migrations/*.sql` (or MIGRATIONS_DIR), applied in
 *   lexical order, exactly once, tracked in `schema_migrations` by filename.
 * - Each file runs in ONE transaction with `lock_timeout = 10s`. No
 *   `CREATE INDEX CONCURRENTLY` here — that cannot run in a transaction and
 *   stays manual DBA work.
 * - Applied files are IMMUTABLE. Never edit one; add the next numbered file.
 * - A failed migration aborts bootstrap: the container never reports healthy
 *   and `deploy-backend.sh` fails loudly instead of serving a half-migrated app.
 */

/**
 * Only this file may be auto-stamped — recorded as applied WITHOUT executing —
 * when the runner meets a pre-existing schema that predates migration tracking
 * (the live prod DB, existing dev DBs). Every later migration runs everywhere.
 */
export const BASELINE_FILENAME = '0001_baseline.sql';

/**
 * `pg_dump` brackets its output with `\restrict` / `\unrestrict` — this baseline's own
 * header records pg_dump 16.13, so it is not a 17-and-up quirk. They are psql
 * META-COMMANDS, not SQL: psql eats them, but this runner ships the file straight to
 * the server via node-postgres, which answers `syntax error at or near "\"`.
 *
 * Consequence, invisible until CI booted a truly empty database: `0001_baseline.sql`
 * could NEVER execute. Live prod and existing dev DBs never noticed because the
 * baseline is STAMPED there, not run — so the only paths that hit this are a fresh
 * environment and disaster recovery, i.e. exactly when it matters most.
 *
 * The baseline is immutable (see the contract above), so the repair lives here.
 *
 * This match is LINE-BASED and therefore not safe in general — a `\restrict` line
 * inside a dollar-quoted body or a multi-line string literal would be stripped too.
 * What makes it safe is the CALLER, which applies it ONLY to `BASELINE_FILENAME`:
 * that file is frozen, contains zero `$$` bodies, and holds exactly the two
 * meta-command lines (verified 2026-07-27). Every other migration is executed
 * byte-for-byte. Do not widen this to all files.
 */
export function stripPsqlMetaCommands(sql: string): string {
  return sql.replace(/^[ \t]*\\(?:un)?restrict\b.*$/gm, '');
}

/** Session-scoped advisory lock so concurrent boots cannot interleave DDL. */
const MIGRATION_LOCK_KEY = 0x66697265; // 'fire'

export interface MigrationPlan {
  /** Record as applied without executing (baseline on a pre-existing schema). */
  stamp: string[];
  /** Execute + record, in lexical order. */
  run: string[];
}

/**
 * Pure planning core: decide what to stamp and what to execute.
 *
 * The baseline is stamped iff it is pending AND the schema already exists —
 * executing a full-schema dump against a live database must never happen.
 * A pending baseline on an EMPTY database executes normally (fresh dev/staging).
 * Everything else pending always executes; a naive "stamp all pending on
 * existing schema" would silently skip real migrations on prod.
 */
export function planMigrations(
  available: readonly string[],
  applied: ReadonlySet<string>,
  schemaPreexists: boolean,
): MigrationPlan {
  const pending = [...available].sort().filter((f) => !applied.has(f));
  const stamp: string[] = [];
  const run: string[] = [];
  for (const file of pending) {
    if (file === BASELINE_FILENAME && schemaPreexists) {
      stamp.push(file);
    } else {
      run.push(file);
    }
  }
  return { stamp, run };
}

export interface RunMigrationsOptions {
  /** Migration directory; defaults to MIGRATIONS_DIR or `<cwd>/migrations`. */
  dir?: string;
  log?: (message: string) => void;
}

export async function runMigrations(
  options: RunMigrationsOptions = {},
): Promise<void> {
  const log = options.log ?? ((m: string) => console.log(m));
  const dir =
    options.dir ?? process.env.MIGRATIONS_DIR ?? join(process.cwd(), 'migrations');

  const files = readdirSync(dir)
    .filter((f) => f.endsWith('.sql'))
    .sort();
  if (files.length === 0) {
    throw new Error(`no .sql migrations found in ${dir}`);
  }

  // Mirror ConfigModule's env loading (.env.local wins over .env); dotenv
  // never overrides variables that are already set (e.g. by docker compose).
  // `quiet` is explicit because dotenv 17 flipped its default to false: without
  // it every boot prints two "injected env (N) from ..." lines to stdout, ahead
  // of the Nest logger, in a prod container whose log level is deliberately narrow.
  dotenv.config({ path: '.env.local', quiet: true });
  dotenv.config({ path: '.env', quiet: true });

  const clientConfig = {
    host: process.env.DB_HOST ?? 'localhost',
    port: Number(process.env.DB_PORT ?? 5432),
    user: process.env.DB_USER ?? 'postgres',
    password: process.env.DB_PASS ?? 'postgres',
    database: process.env.DB_NAME ?? 'chatdb',
  };
  // Bounded connect retry: the runner starts BEFORE Nest/TypeORM (which has its
  // own retry), so on a cold start (VM reboot, db restart) the backend can beat
  // Postgres and crash-loop via restart:unless-stopped — self-healing but noisy
  // exactly during incident recovery. A pg Client cannot re-connect() after a
  // failed attempt, so each attempt gets a fresh instance.
  const CONNECT_ATTEMPTS = 10;
  let client = new Client(clientConfig);
  for (let attempt = 1; ; attempt++) {
    try {
      await client.connect();
      break;
    } catch (error) {
      if (attempt >= CONNECT_ATTEMPTS) throw error;
      // ECONNREFUSED arrives as an AggregateError with an empty .message.
      const reason =
        (error as Error).message || (error as Error & { code?: string }).code || String(error);
      log(
        `db not ready (attempt ${attempt}/${CONNECT_ATTEMPTS}): ${reason}; retrying in 3s`,
      );
      await sleep(3000);
      client = new Client(clientConfig);
    }
  }
  try {
    await client.query('SELECT pg_advisory_lock($1)', [MIGRATION_LOCK_KEY]);
    await client.query(
      `CREATE TABLE IF NOT EXISTS public.schema_migrations (
         filename text PRIMARY KEY,
         applied_at timestamptz NOT NULL DEFAULT now()
       )`,
    );
    const appliedRows = await client.query<{ filename: string }>(
      'SELECT filename FROM public.schema_migrations',
    );
    const applied = new Set(appliedRows.rows.map((r) => r.filename));
    const preexists = await client.query<{ x: boolean }>(
      "SELECT to_regclass('public.users') IS NOT NULL AS x",
    );

    const plan = planMigrations(files, applied, preexists.rows[0].x);

    for (const file of plan.stamp) {
      await client.query(
        'INSERT INTO public.schema_migrations (filename) VALUES ($1) ON CONFLICT DO NOTHING',
        [file],
      );
      log(`stamped ${file} (schema predates migration tracking; not executed)`);
    }

    for (const file of plan.run) {
      const raw = readFileSync(join(dir, file), 'utf8');
      // Only the frozen baseline gets the psql meta-command strip; everything else
      // is executed exactly as written.
      const sql = file === BASELINE_FILENAME ? stripPsqlMetaCommands(raw) : raw;
      log(`applying ${file}`);
      try {
        await client.query('BEGIN');
        await client.query("SET LOCAL lock_timeout = '10s'");
        await client.query(sql);
        await client.query(
          // MUST stay schema-qualified: the baseline we just executed ends with
          // pg_dump's `set_config('search_path', '', false)`, which empties the
          // search_path for the REST OF THE SESSION — including this INSERT, still
          // inside the same transaction. Unqualified, it fails with
          // `relation "schema_migrations" does not exist` on every fresh database.
          // The RESET ALL further down only runs after COMMIT, too late for this.
          'INSERT INTO public.schema_migrations (filename) VALUES ($1)',
          [file],
        );
        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK');
        // `cause` matters here more than anywhere else in the backend: a failed
        // migration ABORTS BOOT, and the pg error carries `code`, `detail`,
        // `hint` and `position` that the flattened `.message` throws away —
        // exactly the fields you need at 3am. Flagged by ESLint 10's new
        // `preserve-caught-error`, which arrived with @eslint/js 10.
        throw new Error(
          `migration ${file} failed: ${(error as Error).message}`,
          { cause: error },
        );
      }
      // pg_dump baselines clear search_path session-wide (set_config ...,false),
      // which would break unqualified names in the NEXT file. RESET ALL restores
      // session defaults and — unlike DISCARD ALL — keeps the advisory lock.
      await client.query('RESET ALL');
      log(`applied ${file}`);
    }

    if (plan.stamp.length === 0 && plan.run.length === 0) {
      log('schema up to date');
    }
  } finally {
    await client.end(); // session end releases the advisory lock
  }
}
