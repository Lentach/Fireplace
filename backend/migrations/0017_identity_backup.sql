-- Amendment (lxxviii) clause 1 (multi-device spec docs/design/multi-device.md
-- §12 D26): the recovery phrase is a KEY BACKUP. The server may hold the
-- account's IK/registrationId/DAK ONLY as an AES-256-GCM blob sealed under a
-- key derived from the 12-word phrase (PBKDF2-HMAC-SHA256 over the
-- NFKD-normalized phrase with a random salt). The blob is useless without the
-- phrase; the verifier column next to it never learns the phrase either.
--
-- Columns live on recovery_keys because the blob's lifecycle IS the phrase's
-- lifecycle: every phrase (re)generation re-uploads the blob in the same
-- transaction, so the blob is always sealed under the latest phrase. All
-- nullable: an account enrolled before this amendment has a verifier and no
-- backup (hasIdentityBackup == false) until its client re-uploads.
ALTER TABLE public.recovery_keys
  ADD COLUMN IF NOT EXISTS "backupBlob" text NULL,
  ADD COLUMN IF NOT EXISTS "backupSalt" text NULL,
  ADD COLUMN IF NOT EXISTS "backupIterations" integer NULL,
  ADD COLUMN IF NOT EXISTS "backupVersion" integer NULL,
  ADD COLUMN IF NOT EXISTS "backupUpdatedAt" TIMESTAMP NULL;
