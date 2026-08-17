-- Phase 0a (multi-device spec docs/design/multi-device.md §6.0): durable
-- identity-change audit. Until now the only record of a key-bundle identity
-- replacement was the [identity-churn] warn log line, which dies with
-- container log rotation — the 2026-08-16 churn audit burned a day
-- reconstructing exactly this from logs. Rows are written by
-- KeyBundlesService.upsertKeyBundle whenever an upload's identityPublicKey
-- differs from the stored one. The pre-check is deliberately racy (telemetry
-- semantics), so concurrent uploads may produce duplicate rows — acceptable.
CREATE TABLE IF NOT EXISTS public.identity_change_audit (
  "id" SERIAL PRIMARY KEY,
  "userId" integer NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  "previousIdentityPublicKey" text NOT NULL,
  "newIdentityPublicKey" text NOT NULL,
  "createdAt" TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_identity_change_audit_user_created
  ON public.identity_change_audit ("userId", "createdAt");
