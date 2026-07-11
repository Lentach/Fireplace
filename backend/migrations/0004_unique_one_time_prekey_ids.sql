-- Enforce one row per (userId, keyId) so OTP upload can UPSERT instead of blindly
-- INSERTing duplicates. A user who regenerates their identity re-uploads keyId
-- 0..N under a NEW public key; without a unique slot those pile up as duplicate
-- (userId,keyId) rows and the oldest-first claim serves the dead one. The upsert
-- (see key-bundles.service.ts uploadOneTimePreKeys) collapses each epoch onto the
-- same keyId slot and refreshes publicKey + identityPublicKey + used.
--
-- Dedup BEFORE creating the unique index or the CREATE fails. Keep the highest
-- id per (userId, keyId) — the most recently uploaded row — and drop the rest.
-- 0003 already removed unused rows, so this dedups the historical used rows only.
--
-- Idempotent: the DELETE is a no-op once there are no duplicates, and the index
-- uses IF NOT EXISTS so a dev DB where TypeORM synchronize already built it (or a
-- re-run) does not error. No CREATE INDEX CONCURRENTLY — migrations run inside a
-- transaction (see migration-runner.ts). Schema-qualified for the fresh-DB path.

DELETE FROM public.one_time_pre_keys a
  USING public.one_time_pre_keys b
  WHERE a."userId" = b."userId"
    AND a."keyId" = b."keyId"
    AND a.id < b.id;

CREATE UNIQUE INDEX IF NOT EXISTS "UQ_one_time_pre_keys_user_key"
  ON public.one_time_pre_keys ("userId", "keyId");
