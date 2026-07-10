-- Add the missing foreign keys to users. These five tables historically had a
-- bare integer userId/creatorId with NO constraint; account deletion relied on
-- hand-maintained cleanup code, and any missed path left orphan rows forever.
--
-- ON DELETE CASCADE everywhere: account deletion must destroy everything the
-- account owns (privacy contract). secret_notes included — a note outliving its
-- deleted creator contradicts that contract, and notes expire within 12h anyway.
--
-- Orphan cleanup MUST precede the constraints or ADD CONSTRAINT fails.
-- All names schema-qualified: the baseline dump clears search_path when it runs
-- first on a fresh database.

DELETE FROM public.key_bundles kb
  WHERE NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = kb."userId");
DELETE FROM public.one_time_pre_keys k
  WHERE NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = k."userId");
DELETE FROM public.fcm_token t
  WHERE NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = t."userId");
DELETE FROM public.web_push_subscription s
  WHERE NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = s."userId");
DELETE FROM public.secret_notes n
  WHERE n."creatorId" IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = n."creatorId");

-- Guarded per (table, column): dev databases where TypeORM synchronize already
-- created a hash-named FK from the updated entities must not get a duplicate.
DO $$
DECLARE
  spec record;
BEGIN
  FOR spec IN
    SELECT * FROM (VALUES
      ('key_bundles',           'userId',    'fk_key_bundles_user'),
      ('one_time_pre_keys',     'userId',    'fk_one_time_pre_keys_user'),
      ('fcm_token',             'userId',    'fk_fcm_token_user'),
      ('web_push_subscription', 'userId',    'fk_web_push_subscription_user'),
      ('secret_notes',          'creatorId', 'fk_secret_notes_creator')
    ) AS t(tbl, col, cname)
  LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_constraint c
      JOIN unnest(c.conkey) AS k(attnum) ON true
      JOIN pg_attribute a
        ON a.attrelid = c.conrelid AND a.attnum = k.attnum
      WHERE c.contype = 'f'
        AND c.conrelid = format('public.%I', spec.tbl)::regclass
        AND c.confrelid = 'public.users'::regclass
        AND a.attname = spec.col
    ) THEN
      EXECUTE format(
        'ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY (%I) '
        || 'REFERENCES public.users(id) ON DELETE CASCADE',
        spec.tbl, spec.cname, spec.col
      );
    END IF;
  END LOOP;
END $$;
