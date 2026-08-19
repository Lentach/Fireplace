-- Phase 2 T1 (multi-device spec docs/design/multi-device.md §4 + §12 Stage-0
-- amendments (a)/(f)/(g)): the deviceId allocator column and the two tables
-- the rest of Phase 2 hangs off. Nothing here changes behaviour for any
-- existing account — the column is metadata with a default, and both tables
-- start EMPTY by design.
--
-- ONE transaction, PLAIN indexes, no CONCURRENTLY (§8, same reasoning as
-- 0015): the runner wraps the file in a transaction and aborts boot on
-- failure, so a partial apply cannot exist.

-- The per-account deviceId allocator (§12 amendment: monotonic-never-reused).
-- Every existing account is single-device device 1, so the NEXT id for every
-- one of them is 2 — the default IS the backfill. Allocation is one atomic
-- UPDATE ... RETURNING "nextDeviceId" - 1 (the PRE-increment value); the
-- counter is never decremented, so an aborted provisioning ceremony leaves a
-- gap, which is expected and safe (gaps over reuse — reuse re-attaches stale
-- id-keyed state, the Matrix/Synapse #17375 class).
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS "nextDeviceId" integer NOT NULL DEFAULT 2;

-- The account's multi-device enrollment: DAK public key + the DAK-signed
-- device list (§3/§4). ONE row per account, first-write-wins, written lazily
-- when multi-device is first enabled — NO backfill (amendment (g)): a
-- single-device account has no enrollment, and inventing one server-side
-- would forge a signature chain only the primary's Keystore can mint (I1).
--
-- Column note vs the frozen §4 line: `enrollmentCreatedAt` is stored in
-- addition to §4's list because the enrollment record E = { userId, dakPub,
-- createdAt, sig_IK("fp-enroll-v1\0" ‖ userId ‖ dakPub ‖ createdAt) } (§3 +
-- amendment (d)) is unverifiable without the createdAt that went under the
-- signature — peers re-verify E, so the server must hand back the exact
-- signed bytes' inputs.
--
-- `listCanonical` is OPAQUE BASE64 BYTES (§3 transport rule): hash and
-- signature are computed over the decoded bytes verbatim, so it is stored as
-- text nobody ever re-serializes.
CREATE TABLE IF NOT EXISTS public.account_authorizations (
  "userId" integer PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  "dakPub" text NOT NULL,
  "enrollmentSig" text NOT NULL,
  "enrollmentCreatedAt" TIMESTAMP NOT NULL,
  "listVersion" integer NOT NULL,
  "listSignature" text NOT NULL,
  "listCanonical" text NOT NULL,
  "updatedAt" TIMESTAMP NOT NULL DEFAULT now()
);

-- Per-device ciphertext fan-out (§4): one envelope per message per recipient
-- device. Envelopes are retained, not mailbox-deleted — they live exactly as
-- long as the message row, and the messageId FK's ON DELETE CASCADE is the
-- SOLE mechanism destroying never-fetched envelopes at the §5.6 deadline
-- (every landed destruction path is a DB DELETE on messages; amendment (g)).
--
-- Deliberately NO FK on (recipientUserId, recipientDeviceId) to devices:
-- envelopes outlive device-row lifecycle (decision record F3).
--
-- NO backfill of pre-migration rows (amendment (g)): they are served by the
-- §5.3 device-gated legacy fallback, and a backfilled device-1 envelope would
-- change which device fallback order 1 serves. The table starts EMPTY.
CREATE TABLE IF NOT EXISTS public.message_envelopes (
  "id" SERIAL PRIMARY KEY,
  "messageId" integer NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  "recipientUserId" integer NOT NULL,
  "recipientDeviceId" integer NOT NULL,
  "ciphertext" text NOT NULL,
  "deliveredAt" TIMESTAMP NULL,
  "readAt" TIMESTAMP NULL,
  "createdAt" TIMESTAMP NOT NULL DEFAULT now()
);

-- One envelope per message per device — a re-fan of the same message to the
-- same device is an UPSERT target, never a second row.
CREATE UNIQUE INDEX IF NOT EXISTS "UQ_message_envelopes_message_recipient_device"
  ON public.message_envelopes ("messageId", "recipientUserId", "recipientDeviceId");

-- Per-device history reads filter on (recipientUserId, recipientDeviceId) and
-- join/order by messageId; this covers that path. (The FK column messageId is
-- also its trailing member, which doubles as the cascade's delete lookup.)
CREATE INDEX IF NOT EXISTS "idx_message_envelopes_recipient_device_message"
  ON public.message_envelopes ("recipientUserId", "recipientDeviceId", "messageId");
