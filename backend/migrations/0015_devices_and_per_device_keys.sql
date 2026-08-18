-- Phase 1 (multi-device spec docs/design/multi-device.md §4 + §8): key material
-- and sessions become per DEVICE instead of per account.
--
-- Nothing here changes behaviour for a single-device account: every existing
-- row becomes device 1, and every new column carries a default or stays NULL.
-- What it removes is the collision that makes a second device impossible —
-- today a second device's bundle OVERWRITES the first (UNIQUE on "userId") and
-- its one-time pre-keys take over the first device's keyId slots, so a peer
-- draws a key whose private half the other device holds. That is the bad-MAC
-- shape this repo already paid for once (migrations 0003-0005).
--
-- ONE transaction, PLAIN indexes (§8, round-2 data-loss finding 5): the runner
-- wraps each file in a transaction and aborts boot on failure, so a partial
-- apply cannot exist. CONCURRENTLY cannot run in a transaction and an INVALID
-- index left behind by a failed concurrent build would block bundle upserts —
-- a key-delivery outage. Table sizes here do not justify that risk.

-- The account's devices. deviceId is a small per-account int from 1; existing
-- accounts are device 1 (§8) and stay that way until provisioning (Phase 2).
CREATE TABLE IF NOT EXISTS public.devices (
  "userId" integer NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  "deviceId" integer NOT NULL,
  "name" text NULL,
  "platform" text NULL,
  -- Only a Keystore-capable device may be primary (I2). Until Phase 2 there is
  -- exactly one device per account and it is the primary by construction.
  "isPrimary" boolean NOT NULL DEFAULT false,
  "addedAt" TIMESTAMP NOT NULL DEFAULT now(),
  -- Set when the device is revoked; its rows are KEPT so a returning session
  -- can be told it was revoked instead of silently re-authorizing.
  "revokedAt" TIMESTAMP NULL,
  "lastSeenAt" TIMESTAMP NULL,
  PRIMARY KEY ("userId", "deviceId")
);

-- Backfill: every existing account is its own primary device 1.
INSERT INTO public.devices ("userId", "deviceId", "isPrimary", "platform")
SELECT id, 1, true, 'legacy'
FROM public.users
ON CONFLICT DO NOTHING;

-- Key bundles: one per (account, device).
ALTER TABLE public.key_bundles
  ADD COLUMN IF NOT EXISTS "deviceId" integer NOT NULL DEFAULT 1;

-- The old UNIQUE("userId") is precisely the constraint that made a second
-- device overwrite the first. Its name is whatever Postgres generated for the
-- column-level UNIQUE, so drop it by lookup rather than by guess.
DO $$
DECLARE
  constraint_name text;
BEGIN
  SELECT con.conname INTO constraint_name
  FROM pg_constraint con
  JOIN pg_class rel ON rel.oid = con.conrelid
  JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
  WHERE nsp.nspname = 'public'
    AND rel.relname = 'key_bundles'
    AND con.contype = 'u'
    AND con.conkey = ARRAY[(
      SELECT attnum FROM pg_attribute
      WHERE attrelid = rel.oid AND attname = 'userId'
    )]::smallint[];
  IF constraint_name IS NOT NULL THEN
    EXECUTE format(
      'ALTER TABLE public.key_bundles DROP CONSTRAINT %I', constraint_name
    );
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS "UQ_key_bundles_user_device"
  ON public.key_bundles ("userId", "deviceId");

-- One-time pre-keys: keyId slots belong to a device, not to an account, so two
-- devices may both hold keyId 0 (falsification 1).
ALTER TABLE public.one_time_pre_keys
  ADD COLUMN IF NOT EXISTS "deviceId" integer NOT NULL DEFAULT 1;

ALTER TABLE public.one_time_pre_keys
  DROP CONSTRAINT IF EXISTS "UQ_one_time_pre_keys_user_key";
DROP INDEX IF EXISTS public."UQ_one_time_pre_keys_user_key";

CREATE UNIQUE INDEX IF NOT EXISTS "UQ_one_time_pre_keys_user_device_key"
  ON public.one_time_pre_keys ("userId", "deviceId", "keyId");

-- The claim query filters on (userId, deviceId, used, identityPublicKey) and
-- orders by id; this index covers the selective part of it.
CREATE INDEX IF NOT EXISTS "idx_one_time_pre_keys_user_device_used"
  ON public.one_time_pre_keys ("userId", "deviceId", "used");

-- Sessions become the per-device anchor: revoking a device deletes its refresh
-- rows and kicks its sockets. NULL means a session issued before this
-- migration, which is device 1 by definition (§8) but is left honest rather
-- than backfilled with a guess. This table is snake_case, unlike the key
-- tables above — follow each table's own convention, not a global one.
ALTER TABLE public.refresh_tokens
  ADD COLUMN IF NOT EXISTS "device_id" integer NULL;
ALTER TABLE public.refresh_tokens
  ADD COLUMN IF NOT EXISTS "device_name" text NULL;

-- Push targeting per device, so a revoked device stops receiving and a
-- notification is not delivered to the device that is already reading it.
ALTER TABLE public.fcm_token
  ADD COLUMN IF NOT EXISTS "deviceId" integer NULL;
ALTER TABLE public.web_push_subscription
  ADD COLUMN IF NOT EXISTS "deviceId" integer NULL;

-- Which of the sender's devices produced a message, and the client-generated
-- token that makes a send idempotent across a lost ack (§5.4). NULL on every
-- pre-migration row and on legacy-client sends.
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS "originDeviceId" integer NULL;
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS "sendToken" text NULL;

-- A duplicate token from one sender is a RETRY of a send the server already
-- committed, never a second message. Partial so the flood of NULLs on legacy
-- rows does not collide with itself. Sender lives in `sender_id` (the entity's
-- JoinColumn name), not `senderId`.
CREATE UNIQUE INDEX IF NOT EXISTS "UQ_messages_sender_send_token"
  ON public.messages ("sender_id", "sendToken")
  WHERE "sendToken" IS NOT NULL;
