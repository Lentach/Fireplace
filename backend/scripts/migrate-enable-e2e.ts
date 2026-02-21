/**
 * One-time migration: clear ALL messages when enabling E2E encryption.
 * Old messages were stored as plaintext and cannot be retroactively encrypted.
 * Run from backend dir: npx ts-node scripts/migrate-enable-e2e.ts
 * Requires DB connection (same .env as backend).
 */
import { config } from 'dotenv';
import { Pool } from 'pg';

config({ path: '.env' });

async function main() {
  const pool = new Pool({
    host: process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT || '5432', 10),
    user: process.env.DB_USER || 'postgres',
    password: process.env.DB_PASS || 'postgres',
    database: process.env.DB_NAME || 'chatdb',
  });

  const countRes = await pool.query('SELECT COUNT(*) as count FROM messages');
  const count = parseInt(countRes.rows[0].count, 10);

  if (count === 0) {
    console.log('No messages to clear.');
    await pool.end();
    return;
  }

  console.log(`About to delete ${count} message(s)...`);
  await pool.query('DELETE FROM messages');
  console.log(`Deleted ${count} message(s). E2E encryption migration complete.`);

  await pool.end();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
