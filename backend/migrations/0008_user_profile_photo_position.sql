ALTER TABLE public.user_profile_photos
  ADD COLUMN IF NOT EXISTS "position" integer NOT NULL DEFAULT 0;

WITH ordered_photos AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY "userId"
      ORDER BY "isPrimary" DESC, "createdAt", id
    ) - 1 AS position
  FROM public.user_profile_photos
)
UPDATE public.user_profile_photos AS photo
SET "position" = ordered_photos.position
FROM ordered_photos
WHERE photo.id = ordered_photos.id;

CREATE INDEX IF NOT EXISTS idx_user_profile_photos_user_position
  ON public.user_profile_photos ("userId", "position");
