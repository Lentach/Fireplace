-- Phase 0b (multi-device spec docs/design/multi-device.md §6.2 + §6.2.1):
-- account-identity reset ceremony and its optional recovery-key verifier.
--
-- Why durable: every timing decision in the ceremony must survive a container
-- restart. A 72 h delay held in memory would silently reset (or vanish) on the
-- next deploy, which is exactly the guarantee the delay exists to provide.
-- The reset row is the ONLY thing that authorizes replacing a stored identity
-- key without a signature from the previous one (§6.1), so its state machine
-- is terminal: 'pending' -> 'cancelled' | 'completed', never back.
CREATE TABLE IF NOT EXISTS public.identity_reset_requests (
  "id" SERIAL PRIMARY KEY,
  "userId" integer NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  -- 'pending' | 'cancelled' | 'completed'
  "status" text NOT NULL DEFAULT 'pending',
  "requestedAt" TIMESTAMP NOT NULL DEFAULT now(),
  -- When the delay elapses. 72 h normally, 1 h when a recovery key was
  -- presented (§6.2.1 shortens, never silences).
  "deadlineAt" TIMESTAMP NOT NULL,
  "shortened" boolean NOT NULL DEFAULT false,
  "cancelledAt" TIMESTAMP NULL,
  "completedAt" TIMESTAMP NULL,
  -- Stamped when a completed reset is spent authorizing one identity upload.
  -- Single-use by construction: the consuming UPDATE requires it to be NULL.
  "consumedAt" TIMESTAMP NULL
);

CREATE INDEX IF NOT EXISTS idx_identity_reset_requests_user_status
  ON public.identity_reset_requests ("userId", "status");

-- One pending ceremony per account (§6.2 rate limit), enforced by the database
-- rather than by a read-then-write check: two concurrent requests cannot both
-- create a pending row. Partial unique indexes are transactional, so this is
-- safe inside the migration runner's single-transaction contract.
CREATE UNIQUE INDEX IF NOT EXISTS uq_identity_reset_requests_one_pending
  ON public.identity_reset_requests ("userId")
  WHERE "status" = 'pending';

-- Recovery key: one optional phrase per account. The server stores ONLY an
-- Argon2id verifier hash (memory-hard by requirement — a database dump must
-- not make the phrase recoverable by brute force). The phrase itself is
-- generated on the client, shown once, and never stored there either.
CREATE TABLE IF NOT EXISTS public.recovery_keys (
  "id" SERIAL PRIMARY KEY,
  "userId" integer NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
  "verifierHash" text NOT NULL,
  "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
  -- Single-use: stamped on a successful presentation AND on any completed
  -- reset. A spent phrase never validates again.
  "usedAt" TIMESTAMP NULL,
  "failedAttempts" integer NOT NULL DEFAULT 0,
  "lockedUntil" TIMESTAMP NULL
);
