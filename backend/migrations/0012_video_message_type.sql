-- Add VIDEO to the messages messageType enum for first-class video messages
-- (encrypted MP4 blobs uploaded through the same opaque msgs/ path as FILE).
--
-- This file must contain ONLY the ALTER TYPE: the migration runner wraps each
-- file in one BEGIN/COMMIT, and on PostgreSQL 16 ALTER TYPE ... ADD VALUE is
-- allowed inside a transaction only as long as the new value is not USED in
-- the same transaction. Any statement here that referenced 'VIDEO' would make
-- the migration fail at boot.
--
-- IF NOT EXISTS so a dev DB where TypeORM synchronize already added the value
-- (or a re-run) does not error. Enum types live in the public schema; the
-- baseline clears search_path when it executes first on a fresh DB, so the
-- type name is schema-qualified.

ALTER TYPE public.messages_messagetype_enum ADD VALUE IF NOT EXISTS 'VIDEO';
