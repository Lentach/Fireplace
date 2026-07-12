-- Bind every one-time pre-key to the identity epoch that uploaded it. This is the
-- DURABLE fix for the stale-OTP bad-MAC wave (see 0003): fetchPreKeyBundle only
-- claims OTP rows whose "identityPublicKey" equals the CURRENT key bundle's
-- identity, so a row minted under an old identity can never be served again —
-- regardless of upload order, old clients, multiple tabs, or reconnect races.
--
-- Nullable by design. Existing (post-0003) rows are all used=true historical rows
-- with no tag; a null tag never matches the current identity filter, so they are
-- never served. New client uploads send the tag explicitly; old clients omit it
-- and the server back-fills from the current bundle (still safe — the fetch
-- filter is the load-bearing guard, not the tag source).
--
-- Idempotent (IF NOT EXISTS). Schema-qualified for the fresh-DB baseline path.

ALTER TABLE public.one_time_pre_keys
  ADD COLUMN IF NOT EXISTS "identityPublicKey" text;
