-- BE-250: enforce one conversation row per unordered user pair. findOrCreate in
-- conversations.service.ts was check-then-insert with NO backing constraint, so
-- two concurrent startConversation calls (or a client double-submit) could both
-- pass the existence check and INSERT, splitting history / unread counts /
-- last-message across two rows; a later delete removed only one — silent,
-- user-visible data loss. The catch-based "race recovery" in findOrCreate was
-- dead code because save() never raised 23505 with nothing enforcing uniqueness.
--
-- The pair is unordered: (A,B) and (B,A) are the SAME conversation. A plain
-- composite unique on (user_one_id, user_two_id) would NOT catch the reversed
-- insert, so this is a FUNCTIONAL unique index on LEAST/GREATEST of the two ids.
--
-- No dedupe step: production has zero duplicate pairs (verified read-only). If an
-- unexpected duplicate exists this CREATE UNIQUE INDEX fails LOUDLY and aborts
-- boot rather than silently destroying messages — the deliberate BE-250 choice.
--
-- IF NOT EXISTS so a dev DB where TypeORM synchronize already built an equivalent
-- index (or a re-run) does not error. No CREATE INDEX CONCURRENTLY — migrations
-- run inside a single transaction (see migration-runner.ts). Schema-qualified
-- because the baseline clears search_path when it executes first on a fresh DB.

CREATE UNIQUE INDEX IF NOT EXISTS "UQ_conversations_user_pair"
  ON public.conversations (
    LEAST(user_one_id, user_two_id),
    GREATEST(user_one_id, user_two_id)
  );
