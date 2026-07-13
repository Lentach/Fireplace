-- Private, per-viewer mute state. A missing row is unmuted; mutedUntil NULL means forever.
CREATE TABLE IF NOT EXISTS public.conversation_notification_preferences (
  id SERIAL PRIMARY KEY,
  "viewerId" integer NOT NULL,
  "conversationId" integer NOT NULL,
  "mutedUntil" timestamp NULL,
  "createdAt" timestamp NOT NULL DEFAULT NOW(),
  "updatedAt" timestamp NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_conversation_notification_preferences_viewer_conversation
    UNIQUE ("viewerId", "conversationId"),
  CONSTRAINT fk_conversation_notification_preferences_viewer
    FOREIGN KEY ("viewerId") REFERENCES public.users(id) ON DELETE CASCADE,
  CONSTRAINT fk_conversation_notification_preferences_conversation
    FOREIGN KEY ("conversationId") REFERENCES public.conversations(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_conversation_notification_preferences_active
  ON public.conversation_notification_preferences ("viewerId", "conversationId", "mutedUntil");
