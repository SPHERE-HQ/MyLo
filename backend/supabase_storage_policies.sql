-- ============================================================================
-- Mylo — Supabase Storage RLS policies
-- ----------------------------------------------------------------------------
-- The Flutter app uploads avatars and feed media directly to Supabase Storage
-- using the project's anon key. By default Supabase locks down the
-- `storage.objects` table with strict RLS policies, which produces the error:
--
--   StorageException 403  "new row violates row-level security policy"
--
-- when the user tries to publish a post or change their avatar.
--
-- Run this script ONCE in the Supabase Dashboard → SQL Editor for the
-- production project (rfspqocehezwcqjpremr) so the buckets exist and accept
-- uploads from the mobile client.
-- ============================================================================

-- 1. Make sure the buckets exist and are public (so getPublicUrl returns a
--    fetch-able URL).
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', TRUE),
       ('media',   'media',   TRUE)
ON CONFLICT (id) DO UPDATE SET public = EXCLUDED.public;

-- 2. Drop any older permissive policies we may have created in a previous
--    run, so this script is idempotent.
DROP POLICY IF EXISTS "mylo_avatars_read"   ON storage.objects;
DROP POLICY IF EXISTS "mylo_avatars_write"  ON storage.objects;
DROP POLICY IF EXISTS "mylo_avatars_update" ON storage.objects;
DROP POLICY IF EXISTS "mylo_avatars_delete" ON storage.objects;
DROP POLICY IF EXISTS "mylo_media_read"     ON storage.objects;
DROP POLICY IF EXISTS "mylo_media_write"    ON storage.objects;
DROP POLICY IF EXISTS "mylo_media_update"   ON storage.objects;
DROP POLICY IF EXISTS "mylo_media_delete"   ON storage.objects;

-- 3. Allow anyone (anon + authenticated) to read public avatars/media.
CREATE POLICY "mylo_avatars_read" ON storage.objects FOR SELECT
  TO anon, authenticated USING (bucket_id = 'avatars');

CREATE POLICY "mylo_media_read" ON storage.objects FOR SELECT
  TO anon, authenticated USING (bucket_id = 'media');

-- 4. Allow uploads from the app. The Mylo backend has its own JWT auth so
--    Supabase doesn't see a per-user identity here; we therefore grant the
--    INSERT to the `anon` role too. The backend keeps the canonical record
--    of which user owns which file.
CREATE POLICY "mylo_avatars_write" ON storage.objects FOR INSERT
  TO anon, authenticated WITH CHECK (bucket_id = 'avatars');

CREATE POLICY "mylo_media_write" ON storage.objects FOR INSERT
  TO anon, authenticated WITH CHECK (bucket_id = 'media');

-- 5. Allow the app to overwrite an existing object (e.g. re-uploading an
--    avatar with the same filename).
CREATE POLICY "mylo_avatars_update" ON storage.objects FOR UPDATE
  TO anon, authenticated USING (bucket_id = 'avatars') WITH CHECK (bucket_id = 'avatars');

CREATE POLICY "mylo_media_update" ON storage.objects FOR UPDATE
  TO anon, authenticated USING (bucket_id = 'media') WITH CHECK (bucket_id = 'media');

-- 6. Allow deletes for cleanup operations.
CREATE POLICY "mylo_avatars_delete" ON storage.objects FOR DELETE
  TO anon, authenticated USING (bucket_id = 'avatars');

CREATE POLICY "mylo_media_delete" ON storage.objects FOR DELETE
  TO anon, authenticated USING (bucket_id = 'media');
