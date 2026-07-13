ALTER TABLE public.users ADD COLUMN IF NOT EXISTS about varchar(80) NULL;

CREATE TABLE IF NOT EXISTS public.user_profile_photos (
  id SERIAL PRIMARY KEY,
  "userId" integer NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  url text NOT NULL,
  "storageKey" text NULL,
  "isPrimary" boolean NOT NULL DEFAULT false,
  "createdAt" timestamp NOT NULL DEFAULT NOW()
);

INSERT INTO public.user_profile_photos ("userId", url, "storageKey", "isPrimary")
SELECT u.id, u."profilePictureUrl", u."profilePicturePublicId", true
FROM public.users u
WHERE u."profilePictureUrl" IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.user_profile_photos p WHERE p."userId" = u.id
  );

CREATE UNIQUE INDEX IF NOT EXISTS uq_user_profile_photos_primary
  ON public.user_profile_photos ("userId")
  WHERE "isPrimary";
CREATE INDEX IF NOT EXISTS idx_user_profile_photos_user_order
  ON public.user_profile_photos ("userId", "isPrimary" DESC, "createdAt", id);
