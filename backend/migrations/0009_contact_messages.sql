-- Contact-form messages from the public landing page (POST /contact).
-- Read by the owner via psql; optional Web Push ping via CONTACT_NOTIFY_USER_ID.
CREATE TABLE IF NOT EXISTS public.contact_messages (
  "id" SERIAL PRIMARY KEY,
  "message" text NOT NULL,
  "replyTo" character varying(320),
  "createdAt" TIMESTAMP NOT NULL DEFAULT now()
);
