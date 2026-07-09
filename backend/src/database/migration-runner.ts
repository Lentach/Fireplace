import { readdirSync, readFileSync } from 'fs';
import { join } from 'path';
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
  dotenv.config({ path: '.env.local' });
  dotenv.config({ path: '.env' });

  const client = new Client({
    host: process.env.DB_HOST ?? 'localhost',
    port: Number(process.env.DB_PORT ?? 5432),
    user: process.env.DB_USER ?? 'postgres',
    password: process.env.DB_PASS ?? 'postgres',
    database: process.env.DB_NAME ?? 'chatdb',
  });
  await client.connect();
  try {
    await client.query('SELECT pg_advisory_lock($1)', [MIGRATION_LOCK_KEY]);
    await client.query(
      `CREATE TABLE IF NOT EXISTS schema_migrations (
         filename text PRIMARY KEY,
         applied_at timestamptz NOT NULL DEFAULT now()
       )`,
    );
    const appliedRows = await client.query<{ filename: string }>(
      'SELECT filename FROM schema_migrations',
    );
    const applied = new Set(appliedRows.rows.map((r) => r.filename));
    const preexists = await client.query<{ x: boolean }>(
      "SELECT to_regclass('public.users') IS NOT NULL AS x",
    );

    const plan = planMigrations(files, applied, preexists.rows[0].x);

    for (const file of plan.stamp) {
      await client.query(
        'INSERT INTO schema_migrations (filename) VALUES ($1) ON CONFLICT DO NOTHING',
        [file],
      );
      log(`stamped ${file} (schema predates migration tracking; not executed)`);
    }

    for (const file of plan.run) {
      const sql = readFileSync(join(dir, file), 'utf8');
      log(`applying ${file}`);
      try {
        await client.query('BEGIN');
        await client.query("SET LOCAL lock_timeout = '10s'");
        await client.query(sql);
        await client.query(
          'INSERT INTO schema_migrations (filename) VALUES ($1)',
          [file],
        );
        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK');
        throw new Error(
          `migration ${file} failed: ${(error as Error).message}`,
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
