// Deterministic real-Postgres reproduction of the stale-OTP bad-MAC defect and
// proof of the fix. Talks to REAL Postgres in an isolated throwaway DB
// (otp_epoch_repro); never touches the dev chatdb data.
//
//   docker compose up -d db && node otp_epoch_repro.mjs
//
// Three proofs:
//   RED    the CURRENT claim SQL (no identity filter) serves an OTP minted under
//          a SUPERSEDED identity epoch -> the dead key the recipient can't use.
//   GUARD  the FIXED claim SQL, filtered by the current identity, NEVER serves a
//          stale-epoch row even when purge did NOT run and the stale rows sit at
//          keyIds the new epoch never overwrote (isolates the fetch filter as the
//          load-bearing guard — delete the filter and this proof fails).
//   ORDER  full fixed path (upsert-with-tag + purge) under the UNSAFE production
//          upload order (OTPs racing the bundle) still ends epoch-2-only.

import { Client } from 'pg';
import { readFileSync } from 'fs';
import { join } from 'path';

const ADMIN = { host: 'localhost', port: 5433, user: 'postgres', password: 'postgres', database: 'postgres' };
const DBNAME = 'otp_epoch_repro';
const REPRO = { ...ADMIN, database: DBNAME };

const CURRENT_FETCH = `
  UPDATE one_time_pre_keys SET used = true
   WHERE id = (SELECT id FROM one_time_pre_keys
                WHERE "userId" = $1 AND used = false
                ORDER BY id ASC LIMIT 1)
  RETURNING id, "keyId", "publicKey"`;

const FIXED_FETCH = `
  UPDATE one_time_pre_keys SET used = true
   WHERE id = (SELECT id FROM one_time_pre_keys
                WHERE "userId" = $1 AND used = false AND "identityPublicKey" = $2
                ORDER BY id ASC LIMIT 1)
  RETURNING id, "keyId", "publicKey"`;

const I1 = 'IDENTITY_EPOCH_1_base64';
const I2 = 'IDENTITY_EPOCH_2_base64';
const USER = 42;

let passed = 0;
function assert(cond, msg) {
  if (!cond) { console.error(`\n  ✗ ASSERT FAILED: ${msg}`); process.exit(1); }
  passed++;
  console.log(`  ✓ ${msg}`);
}

async function recreateDb() {
  const admin = new Client(ADMIN);
  await admin.connect();
  await admin.query(`DROP DATABASE IF EXISTS ${DBNAME}`);
  await admin.query(`CREATE DATABASE ${DBNAME}`);
  await admin.end();
}

async function freshSchema(c) {
  await c.query(`DROP TABLE IF EXISTS one_time_pre_keys; DROP TABLE IF EXISTS key_bundles;`);
  await c.query(`
    CREATE TABLE key_bundles (
      "userId" int PRIMARY KEY, "registrationId" int NOT NULL,
      "identityPublicKey" text NOT NULL, "signedPreKeyId" int NOT NULL,
      "signedPreKeyPublic" text NOT NULL, "signedPreKeySignature" text NOT NULL);
    CREATE TABLE one_time_pre_keys (
      id serial PRIMARY KEY, "userId" int NOT NULL, "keyId" int NOT NULL,
      "publicKey" text NOT NULL, used boolean NOT NULL DEFAULT false,
      "createdAt" timestamptz NOT NULL DEFAULT now());`);
}

async function applyMigrations(c) {
  const migDir = join(process.cwd(), 'migrations');
  await c.query(readFileSync(join(migDir, '0004_unique_one_time_prekey_ids.sql'), 'utf8').replaceAll('public.', ''));
  await c.query(readFileSync(join(migDir, '0005_one_time_prekey_identity_epoch.sql'), 'utf8').replaceAll('public.', ''));
}

async function setBundle(c, identity) {
  await c.query(
    `INSERT INTO key_bundles ("userId","registrationId","identityPublicKey","signedPreKeyId","signedPreKeyPublic","signedPreKeySignature")
     VALUES ($1,1,$2,0,'spk','sig')
     ON CONFLICT ("userId") DO UPDATE SET "identityPublicKey" = EXCLUDED."identityPublicKey"`,
    [USER, identity]);
}

async function main() {
  await recreateDb();
  const c = new Client(REPRO);
  await c.connect();

  // ---- RED: current code serves the stale epoch-1 key ----
  console.log('\n=== RED: current query (no identity filter, no purge) ===');
  await freshSchema(c);
  await setBundle(c, I1);
  for (const k of [0, 1, 2]) await c.query(
    `INSERT INTO one_time_pre_keys ("userId","keyId","publicKey") VALUES ($1,$2,$3)`, [USER, k, `E1K${k}`]);
  await setBundle(c, I2); // identity regenerated
  for (const k of [0, 1, 2]) await c.query(
    `INSERT INTO one_time_pre_keys ("userId","keyId","publicKey") VALUES ($1,$2,$3)`, [USER, k, `E2K${k}`]);
  const red = (await c.query(CURRENT_FETCH, [USER])).rows[0];
  console.log(`  served OTP: keyId=${red.keyId} publicKey=${red.publicKey}`);
  assert(red.publicKey.startsWith('E1'),
    'RED: current query serves an EPOCH-1 (dead) OTP -> recipient Bad Mac');

  // ---- GUARD: fixed fetch filter alone refuses stale rows (purge NOT run) ----
  // Stale epoch-1 rows sit at keyIds 2,3,4 which epoch-2 (keyIds 0,1) never
  // overwrote, and NO purge runs. Only the identity filter can keep them from
  // being served oldest-first. Delete "AND identityPublicKey = $2" and this fails.
  console.log('\n=== GUARD: fixed fetch filter is load-bearing (no purge, non-overlapping stale rows) ===');
  await freshSchema(c);
  await applyMigrations(c);
  await setBundle(c, I2); // current identity is epoch 2
  // Stale epoch-1 rows, tagged I1, at higher keyIds — never overwritten, never purged.
  for (const k of [2, 3, 4]) await c.query(
    `INSERT INTO one_time_pre_keys ("userId","keyId","publicKey","identityPublicKey") VALUES ($1,$2,$3,$4)`,
    [USER, k, `E1K${k}`, I1]);
  // Current epoch-2 rows at keyIds 0,1.
  for (const k of [0, 1]) await c.query(
    `INSERT INTO one_time_pre_keys ("userId","keyId","publicKey","identityPublicKey") VALUES ($1,$2,$3,$4)`,
    [USER, k, `E2K${k}`, I2]);

  const servedGuard = [];
  for (let i = 0; i < 5; i++) {
    const r = await c.query(FIXED_FETCH, [USER, I2]);
    if (r.rows.length === 0) break;
    servedGuard.push(r.rows[0].publicKey);
  }
  console.log(`  served sequence: [${servedGuard.join(', ')}]`);
  assert(servedGuard.length === 2, 'exactly the 2 epoch-2 OTPs were serveable, then exhausted');
  assert(servedGuard.every((p) => p.startsWith('E2')), 'every served OTP is epoch-2; epoch-1 keyIds 2,3,4 NEVER served');
  // After exhaustion the fetch returns nothing (OTP-less) — never a stale row.
  const afterExhaust = await c.query(FIXED_FETCH, [USER, I2]);
  assert(afterExhaust.rows.length === 0, 'exhausted current-epoch pool yields OTP-less bundle, never a stale key');
  // The stale rows are still physically present (purge never ran) yet unserved.
  const staleStill = await c.query(
    `SELECT count(*)::int n FROM one_time_pre_keys WHERE "userId"=$1 AND "publicKey" LIKE 'E1%' AND used=false`, [USER]);
  assert(staleStill.rows[0].n === 3, 'stale epoch-1 rows remain in the table, unused and unserved (filter, not deletion, protected)');

  // ---- ORDER: full fixed path under unsafe production upload order ----
  console.log('\n=== ORDER: upsert-with-tag + purge under unsafe upload order (OTPs race bundle) ===');
  await freshSchema(c);
  await applyMigrations(c);
  const upsertOtp = (identity, keyId, pub) => c.query(
    `INSERT INTO one_time_pre_keys ("userId","keyId","publicKey","identityPublicKey",used)
       VALUES ($1,$2,$3,$4,false)
     ON CONFLICT ("userId","keyId") DO UPDATE
       SET "publicKey"=EXCLUDED."publicKey", "identityPublicKey"=EXCLUDED."identityPublicKey", used=false`,
    [USER, keyId, pub, identity]);
  const purge = (identity) => c.query(
    `DELETE FROM one_time_pre_keys WHERE "userId"=$1 AND used=false
       AND ("identityPublicKey" IS NULL OR "identityPublicKey" <> $2)`, [USER, identity]);

  await setBundle(c, I1);
  for (const k of [0, 1, 2]) await upsertOtp(I1, k, `E1K${k}`);
  // Regeneration: emit epoch-2 OTPs and the new bundle+purge concurrently.
  await Promise.all([
    (async () => { for (const k of [0, 1, 2]) await upsertOtp(I2, k, `E2K${k}`); })(),
    (async () => { await setBundle(c, I2); await purge(I2); })(),
  ]);
  let servedOrder = 0;
  for (let i = 0; i < 5; i++) {
    const r = await c.query(FIXED_FETCH, [USER, I2]);
    if (r.rows.length === 0) break;
    servedOrder++;
    assert(r.rows[0].publicKey.startsWith('E2'), `claim ${i + 1}: epoch-2 OTP, never epoch-1`);
  }
  assert(servedOrder >= 1, 'epoch-2 pool non-empty after unsafe-order regeneration');
  const cnt = (await c.query(
    `SELECT count(*)::int n FROM one_time_pre_keys WHERE "userId"=$1 AND used=false AND "identityPublicKey"=$2`,
    [USER, I2])).rows[0].n;
  console.log(`  current-epoch unused count after drain = ${cnt}`);

  await c.end();
  console.log(`\nALL ${passed} ASSERTIONS PASSED on real Postgres (RED reproduced, fix proven, fetch filter isolated).\n`);
}

main().catch((e) => { console.error(e); process.exit(1); });
