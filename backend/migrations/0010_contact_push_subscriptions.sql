-- Push subscriptions for the owner's contact inbox page (/contact/inbox).
-- Account-independent: the inbox doorbell survives any user-account deletion.
CREATE TABLE IF NOT EXISTS public.contact_push_subscriptions (
  "id" SERIAL PRIMARY KEY,
  "endpoint" text NOT NULL UNIQUE,
  "p256dh" text NOT NULL,
  "auth" text NOT NULL,
  "createdAt" TIMESTAMP NOT NULL DEFAULT now()
);
